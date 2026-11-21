//! Wyrdmate engine: eval + search on top of cozy-chess movegen.

pub mod nnue;

pub use cozy_chess::{Board, Color, GameStatus, Move, Piece};
use cozy_chess::Square;
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
const LMR_MIN_DEPTH: i32 = 3;
const LMR_MIN_INDEX: usize = 2;
const DELTA_MARGIN: i32 = 200; // centipawns of slack for delta pruning in quiescence
const FUT_MAX_DEPTH: i32 = 2;
const FUT_MARGIN: i32 = 150; // centipawns per remaining ply

const TT_EXACT: u8 = 1;
const TT_LOWER: u8 = 2; // score is a lower bound (a beta cutoff happened)
const TT_UPPER: u8 = 3; // score is an upper bound (nothing beat alpha)
const TT_MOVE_SCORE: i32 = 30_000;
/// Default transposition table size in KiB (8 bytes per entry).
pub const DEFAULT_TT_KB: usize = 64;

/// One transposition-table slot, 8 bytes. `flag == 0` means empty.
#[derive(Clone, Copy, Default)]
struct TtEntry {
    key: u16, // upper 16 bits of the position hash
    mv: u16,  // best move: from | to << 6 | promotion << 12 (0 = none)
    score: i16,
    depth: i8,
    flag: u8,
}

fn encode_move(mv: Move) -> u16 {
    let promo = match mv.promotion {
        None => 0,
        Some(Piece::Knight) => 1,
        Some(Piece::Bishop) => 2,
        Some(Piece::Rook) => 3,
        _ => 4,
    };
    (mv.from as u16) | ((mv.to as u16) << 6) | (promo << 12)
}

fn decode_move(code: u16) -> Option<Move> {
    if code == 0 {
        return None;
    }
    let promotion = match code >> 12 {
        0 => None,
        1 => Some(Piece::Knight),
        2 => Some(Piece::Bishop),
        3 => Some(Piece::Rook),
        _ => Some(Piece::Queen),
    };
    Some(Move { from: Square::index((code & 63) as usize), to: Square::index(((code >> 6) & 63) as usize), promotion })
}

/// Mate scores depend on the distance from the root, so store them relative to the node.
fn score_to_tt(score: i32, ply: i32) -> i16 {
    (if score >= MATE - 1_000 {
        score + ply
    } else if score <= -MATE + 1_000 {
        score - ply
    } else {
        score
    }) as i16
}

fn score_from_tt(score: i16, ply: i32) -> i32 {
    let s = i32::from(score);
    if s >= MATE - 1_000 {
        s - ply
    } else if s <= -MATE + 1_000 {
        s + ply
    } else {
        s
    }
}

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
    /// Transposition table: buckets of two entries; empty means the table is disabled.
    tt: Vec<TtEntry>,
}

/// Number of table entries for `kb` KiB: the largest power of two that fits (0 disables the table).
fn tt_entries(kb: usize) -> usize {
    let n = kb * 1024 / std::mem::size_of::<TtEntry>();
    if n < 2 { 0 } else { 1 << (usize::BITS - 1 - n.leading_zeros()) }
}

impl Searcher {
    /// Set the transposition table size in KiB (0 turns it off). Replaces the current table.
    pub fn with_tt_kb(mut self, kb: usize) -> Self {
        self.tt = vec![TtEntry::default(); tt_entries(kb)];
        self
    }

    fn tt_probe(&self, hash: u64) -> Option<TtEntry> {
        if self.tt.is_empty() {
            return None;
        }
        let base = (hash as usize) & (self.tt.len() - 1) & !1;
        let key = (hash >> 48) as u16;
        self.tt[base..base + 2].iter().copied().find(|e| e.flag != 0 && e.key == key)
    }

    fn tt_store(&mut self, hash: u64, mv: Option<Move>, score: i32, depth: i32, flag: u8, ply: i32) {
        if self.tt.is_empty() {
            return;
        }
        let base = (hash as usize) & (self.tt.len() - 1) & !1;
        let key = (hash >> 48) as u16;
        // Reuse this position's slot, else an empty one, else replace the shallower entry.
        let slot = (0..2)
            .find(|&i| self.tt[base + i].flag != 0 && self.tt[base + i].key == key)
            .or_else(|| (0..2).find(|&i| self.tt[base + i].flag == 0))
            .unwrap_or_else(|| usize::from(self.tt[base + 1].depth < self.tt[base].depth));
        let old = self.tt[base + slot];
        // Keep the old best move when this entry has none (an upper bound).
        let mv_code = mv.map_or(if old.flag != 0 && old.key == key { old.mv } else { 0 }, encode_move);
        self.tt[base + slot] = TtEntry { key, mv: mv_code, score: score_to_tt(score, ply), depth: depth.clamp(-127, 127) as i8, flag };
    }

    pub fn new(node_limit: u64) -> Self {
        Self { nodes: 0, node_limit, stopped: false, net: None, hist: Vec::new(), killers: [[None; 2]; MAX_PLY], history: [[[0; 64]; 64]; 2], after_null: false, tt: vec![TtEntry::default(); tt_entries(DEFAULT_TT_KB)] }
    }

    /// Positions that occurred earlier in the game, as `Board::hash()` values, oldest
    /// first, not including the position being searched. Without this the search can
    /// only see repetitions inside its own tree.
    pub fn with_history(mut self, hashes: Vec<u64>) -> Self {
        self.hist = hashes;
        self
    }

    /// Move ordering score: captures/promotions by the static key, then killers, then history.
    fn move_score(&self, board: &Board, mv: Move, ply: i32, tt_move: Option<Move>) -> i32 {
        if tt_move == Some(mv) {
            return TT_MOVE_SCORE;
        }
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
        // Delta pruning: even winning the captured piece plus a margin cannot reach alpha.
        let in_check = !board.checkers().is_empty();
        for mv in moves {
            if !in_check && mv.promotion.is_none() {
                let victim = board.piece_on(mv.to).map_or(piece_value(Piece::Pawn), piece_value); // en passant: a pawn
                if stand + victim + DELTA_MARGIN <= alpha {
                    continue;
                }
            }
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
        let hash = board.hash();
        let alpha0 = alpha;
        let mut tt_move = None;
        if let Some(e) = self.tt_probe(hash) {
            tt_move = decode_move(e.mv);
            if ply > 0 && i32::from(e.depth) >= depth {
                let s = score_from_tt(e.score, ply);
                match e.flag {
                    TT_EXACT => return s,
                    TT_LOWER if s >= beta => return s,
                    TT_UPPER if s <= alpha => return s,
                    _ => {}
                }
            }
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
        moves.sort_by_cached_key(|&m| -self.move_score(board, m, ply, tt_move)); // each score computed once
        let mut best = -INF;
        let mut best_mv: Option<Move> = None;
        let mut tried_quiet: Vec<Move> = Vec::new();
        let in_check = !board.checkers().is_empty();
        // Futility pruning: near the leaves, if the static eval plus a margin is still below
        // alpha, a quiet non-checking move is very unlikely to raise it, so skip it.
        let futile = depth <= FUT_MAX_DEPTH && !in_check && alpha.abs() < MATE - 1_000 && self.eval(board, acc) + FUT_MARGIN * depth <= alpha;
        for (i, mv) in moves.into_iter().enumerate() {
            let quiet = !is_capture(board, mv) && mv.promotion.is_none();
            let mut next = board.clone();
            next.play_unchecked(mv);
            if futile && i > 0 && quiet && best > -MATE + 1_000 && next.checkers().is_empty() {
                continue;
            }
            let nacc = self.child_acc(acc, board, mv);
            // Late move reductions: ordinary quiet moves far down the list are probably bad, so
            // search them shallower first and only redo the full depth if they beat alpha.
            let is_killer = self.killers.get(ply as usize).is_some_and(|k| k[0] == Some(mv) || k[1] == Some(mv));
            let reduce = depth >= LMR_MIN_DEPTH && i >= LMR_MIN_INDEX && quiet && !is_killer && !in_check && next.checkers().is_empty();
            let mut score;
            if reduce {
                let r = 1 + i32::from(i >= 5 && depth >= 5);
                score = -self.negamax(&next, &nacc, depth - 1 - r, -beta, -alpha, ply + 1);
                if !self.stopped && score > alpha {
                    score = -self.negamax(&next, &nacc, depth - 1, -beta, -alpha, ply + 1);
                }
            } else {
                score = -self.negamax(&next, &nacc, depth - 1, -beta, -alpha, ply + 1);
            }
            if self.stopped {
                return 0;
            }
            if score > best {
                best = score;
                best_mv = Some(mv);
            }
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
        let flag = if best >= beta {
            TT_LOWER
        } else if best > alpha0 {
            TT_EXACT
        } else {
            TT_UPPER
        };
        self.tt_store(hash, if flag == TT_UPPER { None } else { best_mv }, best, depth, flag, ply);
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
    fn tt_move_encoding_round_trips() {
        for from in Square::ALL {
            for to in Square::ALL {
                for promotion in [None, Some(Piece::Knight), Some(Piece::Bishop), Some(Piece::Rook), Some(Piece::Queen)] {
                    let mv = Move { from, to, promotion };
                    // a1a1 with no promotion encodes to 0, which means "no move"; it is never a legal move
                    if encode_move(mv) != 0 {
                        assert_eq!(decode_move(encode_move(mv)), Some(mv));
                    }
                }
            }
        }
    }

    #[test]
    fn tt_mate_scores_are_stored_relative_to_the_node() {
        // a mate found 5 plies from the root, stored at ply 3 and read back at ply 7, is 2 plies further away
        let stored = score_to_tt(MATE - 5, 3);
        assert_eq!(score_from_tt(stored, 7), MATE - 9);
        let stored = score_to_tt(-MATE + 5, 3);
        assert_eq!(score_from_tt(stored, 7), -MATE + 9);
        assert_eq!(score_from_tt(score_to_tt(123, 9), 4), 123);
    }

    #[test]
    fn table_sizes_round_down_to_a_power_of_two() {
        assert_eq!(tt_entries(0), 0);
        assert_eq!(tt_entries(64), 8192);
        assert_eq!(tt_entries(100), 8192);
        let mut s = Searcher::new(10).with_tt_kb(0);
        assert!(s.tt.is_empty());
        assert!(s.search(&Board::default(), 2).is_some()); // searching works with the table off
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
