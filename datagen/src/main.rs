//! Self-play data generator. Output lines (bullet text format):
//!   <FEN> | <score cp, white POV> | <result: 1.0 white win, 0.5 draw, 0.0 black win>
//!
//! Usage: wyrdmate-datagen [games] [nodes] [seed] [out.txt] [net.bin (optional)]

use std::fs::File;
use std::io::{BufWriter, Write};
use std::sync::Arc;
use wyrdmate_engine::{legal_moves, nnue::Network, Board, Color, GameStatus, Searcher, MATE};

type Net = Option<Arc<Network>>;

fn searcher(nodes: u64, net: &Net) -> Searcher {
    let s = Searcher::new(nodes);
    match net {
        Some(n) => s.with_net(n.clone()),
        None => s,
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        // xorshift64*
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545F4914F6CDD1D)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const MAX_PLIES: usize = 300;
const OPENING_PLIES: usize = 8;
const ADJ_SCORE: i32 = 1500;
const ADJ_COUNT: usize = 4;

fn random_opening(rng: &mut Rng, nodes: u64, net: &Net) -> Option<Board> {
    let mut b = Board::default();
    let plies = OPENING_PLIES + rng.below(2);
    for _ in 0..plies {
        let ms = legal_moves(&b);
        if ms.is_empty() {
            return None;
        }
        b.play_unchecked(ms[rng.below(ms.len())]);
        if b.status() != GameStatus::Ongoing {
            return None;
        }
    }
    // reject lopsided openings
    let (_, s) = searcher(nodes, net).search(&b, 8)?;
    (s.abs() <= 300).then_some(b)
}

/// Returns (fen, white-POV score) samples and the white-POV result.
fn play_game(rng: &mut Rng, nodes: u64, net: &Net) -> Option<(Vec<(String, i32)>, f32)> {
    let mut board = random_opening(rng, nodes, net)?;
    let mut samples = Vec::new();
    let (mut win_streak, mut loss_streak) = (0usize, 0usize); // white POV

    let result = 'game: {
        for _ in 0..MAX_PLIES {
            match board.status() {
                GameStatus::Won => {
                    // side to move is checkmated
                    break 'game if board.side_to_move() == Color::White { 0.0 } else { 1.0 };
                }
                GameStatus::Drawn => break 'game 0.5,
                GameStatus::Ongoing => {}
            }
            let (mv, score) = searcher(nodes, net).search(&board, 64)?;
            let white_score = if board.side_to_move() == Color::White { score } else { -score };

            let quiet = board.checkers().is_empty()
                && !board.colors(!board.side_to_move()).has(mv.to)
                && mv.promotion.is_none()
                && score.abs() < MATE - 1000;
            if quiet {
                samples.push((board.to_string(), white_score));
            }

            win_streak = if white_score >= ADJ_SCORE { win_streak + 1 } else { 0 };
            loss_streak = if white_score <= -ADJ_SCORE { loss_streak + 1 } else { 0 };
            if win_streak >= ADJ_COUNT {
                break 'game 1.0;
            }
            if loss_streak >= ADJ_COUNT {
                break 'game 0.0;
            }
            board.play_unchecked(mv);
        }
        0.5
    };
    Some((samples, result))
}

fn main() -> std::io::Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let games: usize = a.get(1).and_then(|s| s.parse().ok()).unwrap_or(100);
    let nodes: u64 = a.get(2).and_then(|s| s.parse().ok()).unwrap_or(5_000);
    let seed: u64 = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
    let path = a.get(4).cloned().unwrap_or_else(|| "data/selfplay.txt".into());
    let net: Net = a.get(5).map(|p| Arc::new(Network::load(p).expect("load net")));

    if let Some(dir) = std::path::Path::new(&path).parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut out = BufWriter::new(File::create(&path)?);
    let mut rng = Rng(seed.wrapping_mul(0x9E3779B97F4A7C15) | 1);
    let (mut done, mut positions) = (0usize, 0usize);

    while done < games {
        let Some((samples, result)) = play_game(&mut rng, nodes, &net) else { continue };
        for (fen, score) in &samples {
            writeln!(out, "{fen} | {score} | {result:.1}")?;
        }
        positions += samples.len();
        done += 1;
        if done % 10 == 0 {
            eprintln!("{done}/{games} games, {positions} positions");
        }
    }
    out.flush()?;
    eprintln!("done: {games} games, {positions} positions -> {path}");
    Ok(())
}
