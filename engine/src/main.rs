//! Minimal UCI front end for Wyrdmate.
//! Strength is set by a node limit: `setoption name Nodes value N`, or `go nodes N`.
//! `setoption name EvalFile value <quantised.bin>` switches from material eval to NNUE.

use std::io::{self, BufRead};
use std::sync::Arc;
use wyrdmate_engine::{nnue::Network, Board, Searcher};
use cozy_chess::util::{display_uci_move, parse_uci_move};

fn main() {
    let mut board = Board::default();
    let mut nodes: u64 = 20_000;
    let mut net: Option<Arc<Network>> = None;

    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        let t: Vec<&str> = line.split_whitespace().collect();
        match t.first().copied() {
            Some("uci") => {
                println!("id name Wyrdmate");
                println!("option name Nodes type spin default 20000 min 1 max 100000000");
                println!("option name EvalFile type string default <empty>");
                println!("uciok");
            }
            Some("isready") => println!("readyok"),
            Some("ucinewgame") => board = Board::default(),
            Some("setoption") => {
                // setoption name <N> value <V>
                let name = t.iter().position(|&x| x == "name").map(|i| t[i + 1]);
                let value = t.iter().position(|&x| x == "value").map(|i| t[i + 1..].join(" "));
                match (name, value) {
                    (Some("Nodes"), Some(v)) => nodes = v.parse().unwrap_or(nodes),
                    (Some("EvalFile"), Some(v)) if v != "<empty>" => match Network::load(&v) {
                        Ok(n) => net = Some(Arc::new(n)),
                        Err(e) => println!("info string cannot load net: {e}"),
                    },
                    _ => {}
                }
            }
            Some("position") => {
                let mut i = 1;
                if t.get(1) == Some(&"startpos") {
                    board = Board::default();
                    i = 2;
                } else if t.get(1) == Some(&"fen") {
                    let end = t.iter().position(|&x| x == "moves").unwrap_or(t.len());
                    board = t[2..end].join(" ").parse().expect("bad fen");
                    i = end;
                }
                if t.get(i) == Some(&"moves") {
                    for m in &t[i + 1..] {
                        match parse_uci_move(&board, m) {
                            Ok(mv) => board.play_unchecked(mv),
                            Err(_) => break,
                        }
                    }
                }
            }
            Some("go") => {
                let n = t.iter().position(|&x| x == "nodes").and_then(|i| t.get(i + 1)).and_then(|s| s.parse().ok()).unwrap_or(nodes);
                let mut s = Searcher::new(n);
                if let Some(net) = &net {
                    s = s.with_net(net.clone());
                }
                match s.search(&board, 64) {
                    Some((mv, score)) => {
                        println!("info score cp {score} nodes {}", s.nodes);
                        println!("bestmove {}", display_uci_move(&board, mv));
                    }
                    None => println!("bestmove 0000"),
                }
            }
            Some("quit") => break,
            _ => {}
        }
    }
}
