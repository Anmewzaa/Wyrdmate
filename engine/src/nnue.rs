//! NNUE inference for the `(768 -> H)x2 -> 1` net produced by `wyrdmate-trainer`.
//!
//! Must match trainer/src/main.rs and bullet's `Chess768` feature mapping:
//! pieces are stored relative to the side to move (own pieces = "c 0"; the board
//! is flipped vertically when black is to move), and the second (NTM) view
//! is the vertical mirror with colours swapped.
//!
//! The two views are kept per colour (white view, black view) so they can be
//! updated incrementally move by move; the side to move picks which one is "us".
//!
//! File layout (bullet `quantised.bin`, little-endian i16, possibly zero-padded):
//!   l0w [768][H] (QA), l0b [H] (QA), l1w [2H] (QB), l1b [1] (QA*QB)

use crate::{Board, Color, Move, Piece};

pub const QA: i32 = 255;
pub const QB: i32 = 64;
pub const SCALE: i32 = 400;
const INPUTS: usize = 768;

pub struct Network {
    hidden: usize,
    feature_weights: Vec<i16>, // INPUTS * hidden, feature-major
    feature_bias: Vec<i16>,
    output_weights: Vec<i16>, // 2 * hidden
    output_bias: i16,
}

/// Hidden-layer sums for both colour views; updated per move instead of rebuilt.
#[derive(Clone)]
pub struct Accumulator {
    white: Vec<i32>,
    black: Vec<i32>,
}

impl Network {
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let n = bytes.len() / 2;
        if n < INPUTS + 3 + 1 {
            return Err(format!("net file too small ({} bytes)", bytes.len()));
        }
        let hidden = (n - 1) / (INPUTS + 3);
        let need = INPUTS * hidden + hidden + 2 * hidden + 1;
        // bullet pads the file to a multiple of 64 bytes (< 32 extra i16)
        if need > n || n - need >= 32 {
            return Err(format!("net file size {} bytes does not fit (768->H)x2->1", bytes.len()));
        }
        let vals: Vec<i16> = bytes.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]])).collect();
        let (fw, rest) = vals.split_at(INPUTS * hidden);
        let (fb, rest) = rest.split_at(hidden);
        let (ow, rest) = rest.split_at(2 * hidden);
        Ok(Self {
            hidden,
            feature_weights: fw.to_vec(),
            feature_bias: fb.to_vec(),
            output_weights: ow.to_vec(),
            output_bias: rest[0],
        })
    }

    pub fn load(path: &str) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
        Self::from_bytes(&bytes)
    }

    pub fn hidden_size(&self) -> usize {
        self.hidden
    }

    fn weights(&self, feature: usize) -> &[i16] {
        &self.feature_weights[feature * self.hidden..(feature + 1) * self.hidden]
    }

    /// Feature indices of a piece for the (white view, black view) accumulators.
    /// White view: White pieces first, squares as is. Black view: Black pieces
    /// first, board flipped vertically.
    fn features(color: Color, piece: Piece, sq: usize) -> (usize, usize) {
        let pt = 64 * piece as usize;
        let (w_side, b_side) = if color == Color::White { (0, 384) } else { (384, 0) };
        (w_side + pt + sq, b_side + pt + (sq ^ 56))
    }

    fn add_piece(&self, acc: &mut Accumulator, color: Color, piece: Piece, sq: usize) {
        let (fw, fb) = Self::features(color, piece, sq);
        for (a, &x) in acc.white.iter_mut().zip(self.weights(fw)) {
            *a += i32::from(x);
        }
        for (a, &x) in acc.black.iter_mut().zip(self.weights(fb)) {
            *a += i32::from(x);
        }
    }

    fn sub_piece(&self, acc: &mut Accumulator, color: Color, piece: Piece, sq: usize) {
        let (fw, fb) = Self::features(color, piece, sq);
        for (a, &x) in acc.white.iter_mut().zip(self.weights(fw)) {
            *a -= i32::from(x);
        }
        for (a, &x) in acc.black.iter_mut().zip(self.weights(fb)) {
            *a -= i32::from(x);
        }
    }

    /// Accumulators for `board`, computed from scratch.
    pub fn new_accumulator(&self, board: &Board) -> Accumulator {
        let bias: Vec<i32> = self.feature_bias.iter().map(|&b| i32::from(b)).collect();
        let mut acc = Accumulator { white: bias.clone(), black: bias };
        for color in Color::ALL {
            for piece in Piece::ALL {
                for sq in board.colors(color) & board.pieces(piece) {
                    self.add_piece(&mut acc, color, piece, sq as usize);
                }
            }
        }
        acc
    }

    /// Accumulators after `mv` is played on `board` (the position *before* the move).
    /// `mv` must be legal. Handles captures, en passant, promotion and castling
    /// (cozy-chess encodes castling as king-takes-own-rook).
    pub fn accumulator_after(&self, acc: &Accumulator, board: &Board, mv: Move) -> Accumulator {
        let mut next = acc.clone();
        let us = board.side_to_move();
        let them = !us;
        let from = mv.from as usize;
        let to = mv.to as usize;
        let mover = board.piece_on(mv.from).expect("legal move has a piece on `from`");

        if board.colors(us).has(mv.to) {
            // castling: king and rook go to their final squares on the same rank
            let rank = from / 8 * 8;
            let (king_to, rook_to) = if to > from { (rank + 6, rank + 5) } else { (rank + 2, rank + 3) };
            self.sub_piece(&mut next, us, Piece::King, from);
            self.sub_piece(&mut next, us, Piece::Rook, to);
            self.add_piece(&mut next, us, Piece::King, king_to);
            self.add_piece(&mut next, us, Piece::Rook, rook_to);
            return next;
        }

        if let Some(victim) = board.piece_on(mv.to) {
            self.sub_piece(&mut next, them, victim, to);
        } else if mover == Piece::Pawn && from % 8 != to % 8 {
            // en passant: the captured pawn sits beside the mover's origin
            self.sub_piece(&mut next, them, Piece::Pawn, from / 8 * 8 + to % 8);
        }
        self.sub_piece(&mut next, us, mover, from);
        self.add_piece(&mut next, us, mv.promotion.unwrap_or(mover), to);
        next
    }

    /// Evaluation in centipawns from the side to move's perspective.
    pub fn evaluate_accumulator(&self, acc: &Accumulator, stm: Color) -> i32 {
        let h = self.hidden;
        let (us, them) = if stm == Color::White { (&acc.white, &acc.black) } else { (&acc.black, &acc.white) };
        let screlu = |x: i32| {
            let y = x.clamp(0, QA);
            y * y
        };
        let mut out: i32 = 0;
        for i in 0..h {
            out += screlu(us[i]) * i32::from(self.output_weights[i]);
            out += screlu(them[i]) * i32::from(self.output_weights[h + i]);
        }
        out /= QA;
        out += i32::from(self.output_bias);
        out *= SCALE;
        out / (QA * QB)
    }

    /// Evaluation of a single position (builds the accumulators from scratch).
    pub fn evaluate(&self, board: &Board) -> i32 {
        self.evaluate_accumulator(&self.new_accumulator(board), board.side_to_move())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::legal_moves;

    fn test_net() -> Network {
        let h = 8;
        let n = INPUTS * h + h + 2 * h + 1;
        let mut x: u32 = 12345;
        let mut bytes = Vec::new();
        for _ in 0..n {
            x = x.wrapping_mul(1664525).wrapping_add(1013904223);
            let v = ((x >> 16) % 201) as i16 - 100;
            bytes.extend_from_slice(&v.to_le_bytes());
        }
        Network::from_bytes(&bytes).unwrap()
    }

    /// Walk a sampled game tree (castling, en passant, promotion included) and
    /// check the incremental accumulator equals one built from scratch.
    fn walk(net: &Network, board: &Board, acc: &Accumulator, depth: u32, seed: &mut u32) {
        if depth == 0 {
            return;
        }
        for mv in legal_moves(board) {
            *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            if depth > 1 && (*seed >> 24) % 3 != 0 {
                continue; // sample the tree to keep the test fast
            }
            let mut next = board.clone();
            next.play_unchecked(mv);
            let inc = net.accumulator_after(acc, board, mv);
            let fresh = net.new_accumulator(&next);
            assert_eq!(inc.white, fresh.white, "white view differs after {mv} on {board}");
            assert_eq!(inc.black, fresh.black, "black view differs after {mv} on {board}");
            walk(net, &next, &inc, depth - 1, seed);
        }
    }

    #[test]
    fn incremental_matches_scratch() {
        let net = test_net();
        let fens = [
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            // castling, both sides and colours
            "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1",
            "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R b KQkq - 0 1",
            // en passant available
            "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3",
            // promotions, with and without capture
            "1n2k3/P6P/8/8/8/8/p6p/1N2K3 w - - 0 1",
            "1n2k3/P6P/8/8/8/8/p6p/1N2K3 b - - 0 1",
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        ];
        let mut seed = 7;
        for fen in fens {
            let board: Board = fen.parse().unwrap();
            let acc = net.new_accumulator(&board);
            walk(&net, &board, &acc, 3, &mut seed);
        }
    }
}
