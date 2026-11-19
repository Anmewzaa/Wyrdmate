//! Compares NNUE eval with the scores stored in a datagen text file.
//! Usage: cargo run --release -p wyrdmate-engine --example validate -- <net.bin> <data.txt> [max_lines]
use wyrdmate_engine::{nnue::Network, Board, Color};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let net = Network::load(&a[1]).expect("load net");
    let max: usize = a.get(3).and_then(|s| s.parse().ok()).unwrap_or(50_000);
    let text = std::fs::read_to_string(&a[2]).expect("read data");
    let (mut n, mut sx, mut sy, mut sxx, mut syy, mut sxy, mut sae) = (0f64, 0f64, 0f64, 0f64, 0f64, 0f64, 0f64);
    for line in text.lines().take(max) {
        let mut p = line.split('|');
        let fen = p.next().unwrap().trim();
        let score: f64 = p.next().unwrap().trim().parse().unwrap();
        let board: Board = fen.parse().unwrap();
        let e = net.evaluate(&board) as f64;
        let e = if board.side_to_move() == Color::White { e } else { -e };
        n += 1.0; sx += e; sy += score; sxx += e * e; syy += score * score; sxy += e * score; sae += (e - score).abs();
    }
    let cov = sxy / n - (sx / n) * (sy / n);
    let corr = cov / ((sxx / n - (sx / n).powi(2)).sqrt() * (syy / n - (sy / n).powi(2)).sqrt());
    println!("hidden={} positions={} correlation={:.4} mean_abs_err={:.1}cp", net.hidden_size(), n, corr, sae / n);
    let start = Board::default();
    println!("startpos eval = {} cp", net.evaluate(&start));
}
