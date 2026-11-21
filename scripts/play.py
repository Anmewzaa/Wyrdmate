"""Play against the Wyrdmate engine in a browser.

Usage (from the repo root):
    cargo build --release -p wyrdmate-engine
    python scripts/play.py [port] [net]        # default: 8001 nets/wyrd-1.bin
then open http://localhost:8001/

Serves scripts/play.html, lists nets at /nets and answers
/move?fen=<FEN>&nodes=<N>[&net=<name>] by asking the
UCI engine for its best move. One engine process per request (the net is small).
Binds to 127.0.0.1 only.
"""
import http.server
import json
import os
import subprocess
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8001
NET = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "nets", "wyrd-1.bin")
ENGINE = os.path.join(ROOT, "target", "release", "wyrdmate-engine.exe" if os.name == "nt" else "wyrdmate-engine")


NETS_DIR = os.path.join(ROOT, "nets")


def net_names():
    """Nets offered to the page: every nets/*.bin plus 'material' (no net)."""
    return sorted(f[:-4] for f in os.listdir(NETS_DIR) if f.endswith(".bin")) + ["material"]


def net_path(name):
    """Path of a net by name, or None for the material eval. Only names from net_names() are accepted."""
    if not name:
        return NET
    if name == "material":
        return None
    if name not in net_names():
        raise ValueError(f"unknown net {name!r}")
    return os.path.join(NETS_DIR, name + ".bin")


def best_move(fen, nodes, net=None):
    path = net_path(net)
    setopt = f"setoption name EvalFile value {path}\n" if path else ""
    script = f"uci\n{setopt}isready\nposition fen {fen}\ngo nodes {nodes}\nquit\n"
    out = subprocess.run([ENGINE], input=script, capture_output=True, text=True, timeout=60).stdout
    move, score = None, None
    for line in out.splitlines():
        if line.startswith("info score cp"):
            score = int(line.split()[3])
        if line.startswith("bestmove"):
            move = line.split()[1]
    return move, score


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path in ("/", "/play.html"):
            with open(os.path.join(ROOT, "scripts", "play.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if url.path == "/nets":
            default = os.path.splitext(os.path.basename(NET))[0]
            return self._send(200, json.dumps({"nets": net_names(), "default": default}).encode(), "application/json")
        if url.path == "/move":
            q = urllib.parse.parse_qs(url.query)
            try:
                nodes = max(1, min(int(q["nodes"][0]), 5_000_000))
                move, score = best_move(q["fen"][0], nodes, q.get("net", [None])[0])
                body = json.dumps({"move": move, "score": score}).encode()
                return self._send(200, body, "application/json")
            except Exception as e:  # report to the page instead of dying
                return self._send(500, json.dumps({"error": str(e)}).encode(), "application/json")
        self._send(404, b"not found", "text/plain")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if not os.path.exists(ENGINE):
        sys.exit(f"engine not built: {ENGINE}\nrun: cargo build --release -p wyrdmate-engine")
    print(f"Wyrdmate play server: http://localhost:{PORT}/  (net: {NET})")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
