//! WebAssembly front door for the Wyrdmate engine.
//!
//! Plain C ABI (no wasm-bindgen): the page copies bytes into this module's
//! memory with `alloc`, calls `best_move`, then reads the answer back from
//! `result_ptr()` / the returned length. See `backend.js`.

use cozy_chess::util::display_uci_move;
use std::cell::RefCell;
use std::sync::Arc;
use wyrdmate_engine::{nnue::Network, Board, Searcher};

thread_local! {
    static RESULT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Reserve `len` bytes inside the module for the page to write into.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(len.max(1));
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

/// Release a buffer from `alloc` (same `len` that was passed to `alloc`).
///
/// # Safety
/// `ptr` must come from `alloc(len)` and not be freed twice.
#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len.max(1)));
}

/// Where the last `best_move` answer lives.
#[no_mangle]
pub extern "C" fn result_ptr() -> *const u8 {
    RESULT.with(|r| r.borrow().as_ptr())
}

fn set_result(s: String) -> usize {
    RESULT.with(|r| {
        *r.borrow_mut() = s.into_bytes();
        r.borrow().len()
    })
}

/// Search `fen` for at most `nodes` nodes. `net` holds a quantised net file;
/// an empty slice means the material eval (no net).
/// The answer is `"<uci move> <score cp>"`, or `"!<message>"` on error; returns its length.
///
/// # Safety
/// The pointer/length pairs must describe live buffers made with `alloc`.
#[no_mangle]
pub unsafe extern "C" fn best_move(
    fen_ptr: *const u8,
    fen_len: usize,
    nodes: u32,
    net_ptr: *const u8,
    net_len: usize,
) -> usize {
    let fen = match std::str::from_utf8(std::slice::from_raw_parts(fen_ptr, fen_len)) {
        Ok(s) => s,
        Err(_) => return set_result("!fen is not utf-8".into()),
    };
    let board: Board = match fen.parse() {
        Ok(b) => b,
        Err(e) => return set_result(format!("!bad fen: {e:?}")),
    };
    let mut searcher = Searcher::new(u64::from(nodes.max(1)));
    if net_len > 0 {
        match Network::from_bytes(std::slice::from_raw_parts(net_ptr, net_len)) {
            Ok(n) => searcher = searcher.with_net(Arc::new(n)),
            Err(e) => return set_result(format!("!{e}")),
        }
    }
    match searcher.search(&board, 64) {
        Some((mv, score)) => set_result(format!("{} {}", display_uci_move(&board, mv), score)),
        None => set_result("!no legal move".into()),
    }
}
