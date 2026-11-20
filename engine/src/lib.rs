//! Wyrdmate engine: eval + search on top of cozy-chess movegen.

pub mod nnue;

pub use cozy_chess::{Board, Color, GameStatus, Move, Piece};
use std::sync::Arc;

pub const MATE: i32 = 30_000;
const INF: i32 = 32_000;

fn piece_value(p: Piece) -> i32 {
    match p {
        Piece::Pawn => 100,
        Piece::Knight => 320,
        Piece::Bishop => 330,
        Piece::Rook => 500,
        Piece::Queen => 900,
        Piece::King => 0,
    }
}

/// Static eval in centipawns from the side to move's perspective.
/// Placeholder (material only) to be replaced by the NNUE.
pub fn evaluate(board: &Board) -> i32 {
    let mut score = 0;
    for p in Piece::ALL {
        let w = (board.colors(Color::White) & board.pieces(p)).len() as i32;
        let b = (board.colors(Color::Black) & board.pieces(p)).len() as i32;
        score += (w - b) * piece_value(p);
    }
    if board.side_to_move() == Color::White { score } else { -score }
}

pub fn legal_moves(board: &Board) -> Vec<Move> {
    let mut v = Vec::with_capacity(40);
    board.generate_moves(|ms| {
        v.extend(ms);
        false
    });
    v
}

fn is_capture(board: &Board, mv: Move) -> bool {
    board.colors(!board.side_to_move()).has(mv.to)
}

fn order_key(board: &Board, mv: Move) -> i32 {
    let mut k = 0;
    if is_capture(board, mv) {
        let victim = board.piece_on(mv.to).map_or(0, piece_value);
        let attacker = board.piece_on(mv.from).map_or(0, piece_value);
        k += 10_000 + victim * 10 - attacker;
    }
    if mv.promotion.is_some() {
        k += 9_000;
    }
    k
}

const MAX_PLY: usize = 128;
const KILLER_1: i32 = 8_000;
const KILLER_2: i32 = 7_000;
const HIST_LIMIT: i32 = 16_384;
const NULL_MIN_DEPTH: i32 = 3;
const NULL_REDUCTION: i32 = 2;

pub struct Searcher {
    pub nodes: u64,
    pub node_limit: u64,
    stopped: bool,
    net: Option<Arc<nnue::Network>>,
    /// Hashes of the positions played so far (game history, then the search path).
    /// Used to score repeated positions as draws.
    hist: Vec<u64>,
    /// Two quiet moves per ply that recently caused a beta cutoff.
    killers: [[Option<Move>; 2]; MAX_PLY],
    /// Cutoff statistics for quiet moves, indexed [side][from][to] (16 KB).
    history: [[[i16; 64]; 64]; 2],
    /// Set just before searching a null-move child so that child does not try a null move too.
    after_null: bool,
}

impl Searcher {
    pub fn new(node_limit: u64) -> Self {
        Self { nodes: 0, node_limit, stopped: false, net: None, hist: Vec::new(), killers: [[None; 2]; MAX_PLY], history: [[[0; 64]; 64]; 2], after_null: false }
    }

    /// Positions that occurred earlier in the game, as `Board::hash()` values, oldest
    /// first, not including the position being searched. Without this the search can
    /// only see repetitions inside its own tree.
    pub fn with_history(mut self, hashes: Vec<u64>) -> Self {
        self.hist = hashes;
        self
    }

    /// Move ordering score: captures/promotions by the static key, then killers, then history.
    fn move_score(&self, board: &Board, mv: Move, ply: i32) -> i32 {
        let k = order_key(board, mv);
        if k > 0 {
            return k;
        }
        if let Some(slot) = self.killers.get(ply as usize) {
            if slot[0] == Some(mv) {
                return KILLER_1;
            }
            if slot[1] == Some(mv) {
                return KILLER_2;
            }
        }
        i32::from(self.history[board.side_to_move() as usize][mv.from as usize][mv.to as usize]) / 8
    }

    fn bump_history(&mut self, side: Color, mv: Move, bonus: i32) {
        let h = &mut self.history[side as usize][mv.from as usize][mv.to as usize];
        let v = i32::from(*h);
        *h = (v + bonus - v * bonus.abs() / HIST_LIMIT) as i16; // gravity keeps |h| < HIST_LIMIT
    }

    /// A quiet move caused a cutoff: remember it as a killer and reward it; penalise the quiet
    /// moves tried before it.
    fn reward_cutoff(&mut self, board: &Board, mv: Move, tried: &[Move], depth: i32, ply: i32) {
        if let Some(slot) = self.killers.get_mut(ply as usize) {
            if slot[0] != Some(mv) {
                slot[1] = slot[0];
                slot[0] = Some(mv);
            }
        }
        let bonus = (depth * depth).min(400);
        let side = board.side_to_move();
        self.bump_history(side, mv, bonus);
        for &m in tried {
            self.bump_history(side, m, -bonus);
        }
    }

    /// True if `board` already occurred earlier in `hist` (same side to move, within the
    /// reversible window set by the halfmove clock). One earlier occurrence counts as a
    /// draw, the usual search shortcut for the threefold rule.
    fn is_repetition(&self, board: &Board) -> bool {
        let h = board.hash();
        let n = self.hist.len();
        let reach = (board.halfmove_clock() as usize).min(n);
        (2..=reach).step_by(2).any(|k| self.hist[n - k] == h)
    }

    /// Use an NNUE instead of the material eval.
    pub fn with_net(mut self, net: Arc<nnue::Network>) -> Self {
        self.net = Some(net);
        self
    }

    fn eval(&self, board: &Board, acc: &Option<nnue::Accumulator>) -> i32 {
        match (&self.net, acc) {
            (Some(n), Some(a)) => n.evaluate_accumulator(a, board.side_to_move()),
            _ => evaluate(board),
        }
    }

    /// Accumulators after `mv` (None when searching with the material eval).
    fn child_acc(&self, acc: &Option<nnue::Accumulator>, board: &Board, mv: Move) -> Option<nnue::Accumulator> {
        match (&self.net, acc) {
            (Some(n), Some(a)) => Some(n.accumulator_after(a, board, mv)),
            _ => None,
        }
    }

    fn tick(&mut self) {
        self.nodes += 1;
        if self.nodes >= self.node_limit {
            self.stopped = true;
        }
    }

    fn quiesce(&mut self, board: &Board, acc: &Option<nnue::Accumulator>, mut alpha: i32, beta: i32, ply: i32) -> i32 {
        self.tick();
        let stand = self.eval(board, acc);
        if self.stopped || stand >= beta {
            return stand;
        }
        alpha = alpha.max(stand);
        let mut moves: Vec<Move> = legal_moves(board)
            .into_iter()
            .filter(|&m| is_capture(board, m) || m.promotion.is_some())
            .collect();
        moves.sort_by_key(|&m| -order_key(board, m));
        for mv in moves {
            let mut next = board.clone();
            next.play_unchecked(mv);
            let nacc = self.child_acc(acc, board, mv);
            let score = -self.quiesce(&next, &nacc, -beta, -alpha, ply + 1);
            if self.stopped {
                return alpha;
            }
            if score >= beta {
                return score;
            }
            alpha = alpha.max(score);
        }
        alpha
    }

    fn negamax(&mut self, board: &Board, acc: &Option<nnue::Accumulator>, depth: i32, alpha: i32, beta: i32, ply: i32) -> i32 {
        if self.is_repetition(board) {
            return 0;
        }
        self.hist.push(board.hash());
        let score = self.negamax_node(board, acc, depth, alpha, beta, ply);
        self.hist.pop();
        score
    }

    fn negamax_node(&mut self, board: &Board, acc: &Option<nnue::Accumulator>, depth: i32, mut alpha: i32, beta: i32, ply: i32) -> i32 {
        match board.status() {
            GameStatus::Won => return -MATE + ply,
            GameStatus::Drawn => return 0,
            GameStatus::Ongoing => {}
        }
        if depth <= 0 {
            return self.quiesce(board, acc, alpha, beta, ply);
        }
        self.tick();
        if self.stopped {
            return 0;
        }
        // Null-move pruning: if passing the move still leaves us at or above beta after a
        // reduced search, a real move would too. Not in check, not twice in a row, and only
        // with some piece besides pawns and the king (otherwise zugzwang makes it unsound).
        let allow_null = !std::mem::take(&mut self.after_null);
        let stm = board.side_to_move();
        let has_pieces = !(board.colors(stm) & !(board.pieces(Piece::Pawn) | board.pieces(Piece::King))).is_empty();
        if allow_null && depth >= NULL_MIN_DEPTH && has_pieces && beta.abs() < MATE - 1_000 {
            if let Some(null_board) = board.null_move() {
                self.after_null = true;
                let score = -self.negamax(&null_board, acc, depth - 1 - NULL_REDUCTION, -beta, -beta + 1, ply + 1);
                self.after_null = false;
                if self.stopped {
                    return 0;
                }
                if score >= beta {
                    return beta;
                }
            }
        }
        let mut moves = legal_moves(board);
        moves.sort_by_cached_key(|&m| -self.move_score(board, m, ply)); // each score computed once
        let mut best = -INF;
        let mut tried_quiet: Vec<Move> = Vec::new();
        for mv in moves {
            let quiet = !is_capture(board, mv) && mv.promotion.is_none();
            let mut next = board.clone();
            next.play_unchecked(mv);
            let nacc = self.child_acc(acc, board, mv);
            let score = -self.negamax(&next, &nacc, depth - 1, -beta, -alpha, ply + 1);
            if self.stopped {
                return 0;
            }
            best = best.max(score);
            alpha = alpha.max(score);
            if alpha >= beta {
                if quiet {
                    self.reward_cutoff(board, mv, &tried_quiet, depth, ply);
                }
                break;
            }
            if quiet {
                tried_quiet.push(mv);
            }
        }
        best
    }

    /// Iterative deepening up to `max_depth` or the node limit.
    /// Returns the best move and its score (centipawns, side-to-move view).
    pub fn search(&mut self, board: &Board, max_depth: i32) -> Option<(Move, i32)> {
        let mut root = legal_moves(board);
        if root.is_empty() {
            return None;
        }
        let root_acc = self.net.as_ref().map(|n| n.new_accumulator(board));
        self.hist.push(board.hash()); // root; popped before returning
        self.killers = [[None; 2]; MAX_PLY];
        self.history = [[[0; 64]; 64]; 2];
        let mut best = (root[0], 0);
        root.sort_by_key(|&m| -order_key(board, m));
        for depth in 1..=max_depth {
            let mut iter_best: Option<(Move, i32)> = None;
            let mut alpha = -INF;
            for &mv in &root {
                let mut next = board.clone();
                next.play_unchecked(mv);
                let nacc = self.child_acc(&root_acc, board, mv);
                let score = -self.negamax(&next, &nacc, depth - 1, -INF, -alpha, 1);
                if self.stopped {
                    break;
                }
                if iter_best.map_or(true, |(_, s)| score > s) {
                    iter_best = Some((mv, score));
                }
                alpha = alpha.max(score);
            }
            if self.stopped {
                break;
            }
            if let Some(b) = iter_best {
                best = b;
                // Best move first for the next iteration; the others keep their order.
                // (The old code re-sorted by the static key every iteration, which undid this.)
                if let Some(i) = root.iter().position(|&m| m == b.0) {
                    root[..=i].rotate_right(1);
                }
            }
        }
        self.hist.pop();
        Some(best)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn startpos_eval_is_zero() {
        assert_eq!(evaluate(&Board::default()), 0);
    }

    #[test]
    fn finds_mate_in_one() {
        // White: Qh5 -> Qxf7# (scholar's mate setup)
        let b: Board = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 1"
            .parse()
            .unwrap();
        let mut s = Searcher::new(1_000_000);
        let (mv, score) = s.search(&b, 3).unwrap();
        assert_eq!(mv.to.to_string(), "f7");
        assert!(score > MATE - 10);
    }

    /// White has a queen, black only a knight. Black to move can undo its last knight move,
    /// which repeats the position from four plies ago. Seeing the history, that draw (0) beats
    /// every other move; without it the search just sees a lost position.
    #[test]
    fn repetition_is_a_draw() {
        let mut board: Board = "4k1n1/8/8/8/8/8/8/Q3K3 w - - 0 1".parse().unwrap();
        let mut hist = Vec::new();
        for m in ["a1a2", "g8f6", "a2a1"] {
            hist.push(board.hash());
            board.play_unchecked(cozy_chess::util::parse_uci_move(&board, m).unwrap());
        }
        // `board` is now the position after Qa1; black to move, halfmove clock 3.
        let (mv, score) = Searcher::new(100_000).with_history(hist).search(&board, 3).unwrap();
        assert_eq!(mv.to_string(), "f6g8");
        assert_eq!(score, 0);

        let (_, blind) = Searcher::new(100_000).search(&board, 3).unwrap();
        assert!(blind < -300, "without history black should see a lost position, got {blind}");
    }

    #[test]
    fn history_scores_stay_bounded() {
        let board = Board::default();
        let mv = legal_moves(&board)[0];
        let mut s = Searcher::new(1);
        for _ in 0..100_000 {
            s.bump_history(Color::White, mv, 400);
        }
        let top = s.history[Color::White as usize][mv.from as usize][mv.to as usize];
        assert!(i32::from(top) <= HIST_LIMIT && top > 0, "top = {top}"); // converges towards HIST_LIMIT
        for _ in 0..100_000 {
            s.bump_history(Color::White, mv, -400);
        }
        let bottom = s.history[Color::White as usize][mv.from as usize][mv.to as usize];
        assert!(i32::from(bottom) >= -HIST_LIMIT && bottom < 0, "bottom = {bottom}");
    }

    #[test]
    fn search_does_not_leak_history() {
        let board = Board::default();
        let mut s = Searcher::new(5_000);
        s.search(&board, 4).unwrap();
        assert!(s.hist.is_empty());
    }

    #[test]
    fn respects_node_limit() {
        let mut s = Searcher::new(5_000);
        assert!(s.search(&Board::default(), 20).is_some());
        assert!(s.nodes <= 5_100);
    }
}
