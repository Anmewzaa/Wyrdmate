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

pub struct Searcher {
    pub nodes: u64,
    pub node_limit: u64,
    stopped: bool,
    net: Option<Arc<nnue::Network>>,
}

impl Searcher {
    pub fn new(node_limit: u64) -> Self {
        Self { nodes: 0, node_limit, stopped: false, net: None }
    }

    /// Use an NNUE instead of the material eval.
    pub fn with_net(mut self, net: Arc<nnue::Network>) -> Self {
        self.net = Some(net);
        self
    }

    fn eval(&self, board: &Board) -> i32 {
        match &self.net {
            Some(n) => n.evaluate(board),
            None => evaluate(board),
        }
    }

    fn tick(&mut self) {
        self.nodes += 1;
        if self.nodes >= self.node_limit {
            self.stopped = true;
        }
    }

    fn quiesce(&mut self, board: &Board, mut alpha: i32, beta: i32, ply: i32) -> i32 {
        self.tick();
        let stand = self.eval(board);
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
            let score = -self.quiesce(&next, -beta, -alpha, ply + 1);
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

    fn negamax(&mut self, board: &Board, depth: i32, mut alpha: i32, beta: i32, ply: i32) -> i32 {
        match board.status() {
            GameStatus::Won => return -MATE + ply,
            GameStatus::Drawn => return 0,
            GameStatus::Ongoing => {}
        }
        if depth <= 0 {
            return self.quiesce(board, alpha, beta, ply);
        }
        self.tick();
        if self.stopped {
            return 0;
        }
        let mut moves = legal_moves(board);
        moves.sort_by_key(|&m| -order_key(board, m));
        let mut best = -INF;
        for mv in moves {
            let mut next = board.clone();
            next.play_unchecked(mv);
            let score = -self.negamax(&next, depth - 1, -beta, -alpha, ply + 1);
            if self.stopped {
                return 0;
            }
            best = best.max(score);
            alpha = alpha.max(score);
            if alpha >= beta {
                break;
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
        let mut best = (root[0], 0);
        for depth in 1..=max_depth {
            root.sort_by_key(|&m| -order_key(board, m));
            let mut iter_best: Option<(Move, i32)> = None;
            let mut alpha = -INF;
            for &mv in &root {
                let mut next = board.clone();
                next.play_unchecked(mv);
                let score = -self.negamax(&next, depth - 1, -INF, -alpha, 1);
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
                // put the best move first for the next iteration
                if let Some(i) = root.iter().position(|&m| m == b.0) {
                    root.swap(0, i);
                }
            }
        }
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

    #[test]
    fn respects_node_limit() {
        let mut s = Searcher::new(5_000);
        assert!(s.search(&Board::default(), 20).is_some());
        assert!(s.nodes <= 5_100);
    }
}
