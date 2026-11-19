//! NNUE inference for the `(768 -> H)x2 -> 1` net produced by `wyrdmate-trainer`.
//!
//! Must match trainer/src/main.rs and bullet's `Chess768` feature mapping:
//! pieces are stored relative to the side to move (own pieces = "c 0"; the board
//! is flipped vertically when black is to move), and the second (NTM) view
//! is the vertical mirror with colours swapped.
//!
//! File layout (bullet `quantised.bin`, little-endian i16, possibly zero-padded):
//!   l0w [768][H] (QA), l0b [H] (QA), l1w [2H] (QB), l1b [1] (QA*QB)

use crate::{Board, Color, Piece};

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

    fn add(&self, acc: &mut [i32], feature: usize) {
        let w = &self.feature_weights[feature * self.hidden..(feature + 1) * self.hidden];
        for (a, &x) in acc.iter_mut().zip(w) {
            *a += i32::from(x);
        }
    }

    /// Evaluation in centipawns from the side to move's perspective.
    /// (Recomputes accumulators from scratch: simple, not yet incremental.)
    pub fn evaluate(&self, board: &Board) -> i32 {
        let h = self.hidden;
        let stm = board.side_to_move();
        let mut us: Vec<i32> = self.feature_bias.iter().map(|&b| i32::from(b)).collect();
        let mut them = us.clone();

        for color in Color::ALL {
            let c = usize::from(color != stm);
            for (pt, piece) in Piece::ALL.into_iter().enumerate() {
                for sq in board.colors(color) & board.pieces(piece) {
                    let s = sq as usize;
                    let rel = if stm == Color::Black { s ^ 56 } else { s };
                    self.add(&mut us, [0, 384][c] + 64 * pt + rel);
                    self.add(&mut them, [384, 0][c] + 64 * pt + (rel ^ 56));
                }
            }
        }

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
}
