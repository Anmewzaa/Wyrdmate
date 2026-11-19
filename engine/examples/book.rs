//! Writes balanced random openings (one FEN per line) for engine matches.
//! Usage: cargo run --release -p wyrdmate-engine --example book -- <count> <seed> <out.epd>
use wyrdmate_engine::{legal_moves, Board, GameStatus, Searcher};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let count: usize = a[1].parse().unwrap();
    let mut x: u64 = a[2].parse::<u64>().unwrap().wrapping_mul(0x9E3779B97F4A7C15) | 1;
    let mut rnd = |n: usize| {
        x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
        (x.wrapping_mul(0x2545F4914F6CDD1D) % n as u64) as usize
    };
    let mut out = String::new();
    let mut made = 0;
    while made < count {
        let mut b = Board::default();
        let mut ok = true;
        for _ in 0..8 {
            let ms = legal_moves(&b);
            if ms.is_empty() { ok = false; break; }
            b.play_unchecked(ms[rnd(ms.len())]);
            if b.status() != GameStatus::Ongoing { ok = false; break; }
        }
        if !ok { continue; }
        // keep only roughly balanced openings
        if let Some((_, s)) = Searcher::new(20_000).search(&b, 8) {
            if s.abs() <= 100 { out.push_str(&format!("{b}\n")); made += 1; }
        }
    }
    std::fs::write(&a[3], out).unwrap();
    println!("wrote {made} openings");
}
