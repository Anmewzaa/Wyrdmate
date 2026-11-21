"""Local progress page for datagen, training and A/B matches (read-only, stdlib only).

    python scripts/monitor.py            # then open http://localhost:8765
    python scripts/monitor.py --port 9000 --superbatches 200

It reads the log files the tools already write:
  data/<round>part<seed>.log   datagen, lines like "490/2500 games, 49455 positions"
  checkpoints/*/log.txt        trainer loss, lines "superbatch,batch,loss" (written when a checkpoint is saved)
  logs/ab-*.txt                fastchess output (latest one)
It only reads files and never touches a running job.
"""
import argparse
import glob
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNNING_SECS = 20  # a log written to in the last N seconds counts as running


def read_text(path, tail_bytes=None):
    try:
        with open(path, "rb") as f:
            if tail_bytes:
                f.seek(0, os.SEEK_END)
                f.seek(max(0, f.tell() - tail_bytes))
            raw = f.read()
    except OSError:
        return ""
    return raw.replace(b"\x00", b"").decode("utf-8", "ignore")  # fastchess logs may be UTF-16


def age(path):
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return 1e9


def datagen_status():
    groups = {}
    for p in glob.glob(os.path.join(ROOT, "data", "*part*.log")):
        m = re.match(r"(.*?part)(\d+)\.log$", os.path.basename(p))
        if m:
            groups.setdefault(m.group(1), []).append((m.group(2), p))
    if not groups:
        return None
    name = max(groups, key=lambda g: max(os.path.getmtime(p) for _, p in groups[g]))
    jobs = []
    for seed, p in sorted(groups[name]):
        last = [l for l in read_text(p, 4000).splitlines() if l.strip()][-1:] or [""]
        m = re.match(r"(\d+)/(\d+) games, (\d+) positions", last[0])
        done = last[0].startswith("done")
        if m:
            g, tot, pos = int(m.group(1)), int(m.group(2)), int(m.group(3))
        else:
            md = re.match(r"done: (\d+) games, (\d+) positions", last[0])
            g = tot = int(md.group(1)) if md else 0
            pos = int(md.group(2)) if md else 0
        jobs.append({"seed": seed, "games": g, "total": tot, "positions": pos,
                     "done": done, "running": (not done) and age(p) < RUNNING_SECS})
    return {"name": name.rstrip("part") or name, "jobs": jobs}


def train_status(total_sb):
    logs = glob.glob(os.path.join(ROOT, "checkpoints", "*", "log.txt"))
    if not logs:
        return None
    p = max(logs, key=os.path.getmtime)
    pts, last_by_sb = [], {}
    for line in read_text(p).splitlines():
        parts = line.strip().split(",")
        if len(parts) == 3:
            try:
                last_by_sb[int(parts[0])] = float(parts[2])
            except ValueError:
                pass
    for sb in sorted(last_by_sb):
        pts.append([sb, last_by_sb[sb]])
    step = max(1, len(pts) // 200)
    sb_now = pts[-1][0] if pts else 0
    return {"run": os.path.basename(os.path.dirname(p)), "superbatch": sb_now, "total": total_sb,
            "loss": pts[-1][1] if pts else None, "points": pts[::step],
            "running": age(p) < RUNNING_SECS}


def match_status():
    logs = glob.glob(os.path.join(ROOT, "logs", "ab-*.txt"))
    if not logs:
        return None
    p = max(logs, key=os.path.getmtime)
    text = read_text(p, 20000)
    games = re.findall(r"Games: (\d+), Wins: (\d+), Losses: (\d+), Draws: (\d+)", text)
    elo = re.findall(r"(?<![A-Za-z])Elo: (-?[\d.]+) \+/- ([\d.]+)", text)
    finished = "Finished match" in text
    out = {"name": os.path.basename(p)[3:-4], "finished": finished,
           "running": (not finished) and age(p) < 60}
    if games:
        g, w, l, d = map(int, games[-1])
        out.update(games=g, wins=w, losses=l, draws=d)
    if elo:
        out.update(elo=float(elo[-1][0]), err=float(elo[-1][1]))
    return out


PAGE = """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wyrdmate monitor</title>
<style>
:root{--bg:#fff;--ink:#1f1f1e;--mute:#6b6a66;--line:#e1e0d9;--card:#f6f5f0;--blue:#2a78d6;--green:#1baf7a;--red:#e34948}
@media (prefers-color-scheme:dark){:root{--bg:#171716;--ink:#ecebe6;--mute:#a09f98;--line:#33332f;--card:#222220;--blue:#5a9be8;--green:#35c593;--red:#ef6b6a}}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 "Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:860px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:22px;margin:0 0 2px}.sub{color:var(--mute);font-size:13px;margin:0 0 18px}
section{background:var(--card);border-radius:10px;padding:14px 16px;margin:0 0 16px}
h2{font-size:15px;margin:0 0 10px;display:flex;gap:8px;align-items:center}
.pill{font-size:11px;padding:1px 8px;border-radius:10px;border:1px solid var(--line);color:var(--mute)}
.pill.on{color:var(--green);border-color:var(--green)}
.row{display:grid;grid-template-columns:80px 1fr 150px;gap:10px;align-items:center;margin:6px 0;font-size:13px}
.bar{height:12px;background:var(--line);border-radius:6px;overflow:hidden}.bar>i{display:block;height:100%;background:var(--blue);transition:width .6s}
.bar.done>i{background:var(--green)}.num{color:var(--mute);text-align:right;font-variant-numeric:tabular-nums}
.big{font-size:28px;font-weight:700;font-variant-numeric:tabular-nums}.mute{color:var(--mute);font-size:13px}
svg{width:100%;height:auto;display:block}.empty{color:var(--mute);font-size:13px}
</style>
<main>
<h1>Wyrdmate monitor</h1><p class="sub" id="upd">connecting...</p>
<section id="dg"></section><section id="tr"></section><section id="mt"></section>
</main>
<script>
const $=s=>document.querySelector(s), fmt=n=>n.toLocaleString("en-US");
const pill=(on,t)=>`<span class="pill ${on?'on':''}">${t}</span>`;
function chart(pts){
  if(pts.length<2)return"";
  const W=800,H=180,L=54,B=22,xs=pts.map(p=>p[0]),ys=pts.map(p=>Math.log10(p[1]));
  const x0=Math.min(...xs),x1=Math.max(...xs),y0=Math.min(...ys),y1=Math.max(...ys),pad=(y1-y0)*.08||.1;
  const X=v=>L+(v-x0)/((x1-x0)||1)*(W-L-8),Y=v=>8+(1-(v-y0+pad)/((y1-y0)+2*pad))*(H-B-8);
  const d=pts.map((p,i)=>(i?"L":"M")+X(p[0]).toFixed(1)+" "+Y(Math.log10(p[1])).toFixed(1)).join("");
  const last=pts[pts.length-1];
  return `<svg viewBox="0 0 ${W} ${H}"><path d="${d}" fill="none" stroke="var(--blue)" stroke-width="2.5"/>
  <circle cx="${X(last[0])}" cy="${Y(Math.log10(last[1]))}" r="4" fill="var(--blue)"/>
  <text x="${L}" y="${H-4}" font-size="11" fill="var(--mute)">superbatch ${x0}</text>
  <text x="${W-8}" y="${H-4}" font-size="11" fill="var(--mute)" text-anchor="end">${x1}</text>
  <text x="4" y="14" font-size="11" fill="var(--mute)">loss (log)</text></svg>`;
}
function render(s){
  const dg=s.datagen;
  if(!dg)$("#dg").innerHTML='<h2>Datagen</h2><div class="empty">no datagen logs yet</div>';
  else{
    const g=dg.jobs.reduce((a,j)=>a+j.games,0),t=dg.jobs.reduce((a,j)=>a+j.total,0),p=dg.jobs.reduce((a,j)=>a+j.positions,0);
    const on=dg.jobs.some(j=>j.running),pc=t?100*g/t:0;
    $("#dg").innerHTML=`<h2>Datagen ${pill(on,on?"running":(pc>=100?"done":"idle"))}<span class="mute">${dg.name||""}</span></h2>
    <div class="big">${pc.toFixed(1)}%</div><div class="mute">${fmt(g)} / ${fmt(t)} games · ${fmt(p)} positions</div>`+
    dg.jobs.map(j=>{const q=j.total?100*j.games/j.total:0;
      return `<div class="row"><span>seed ${j.seed}</span><div class="bar ${j.done?'done':''}"><i style="width:${q}%"></i></div><span class="num">${fmt(j.games)}/${fmt(j.total)} · ${q.toFixed(0)}%</span></div>`}).join("");
  }
  const tr=s.train;
  if(!tr)$("#tr").innerHTML='<h2>Training</h2><div class="empty">no training logs yet</div>';
  else{
    const pc=tr.total?100*tr.superbatch/tr.total:0;
    $("#tr").innerHTML=`<h2>Training ${pill(tr.running,tr.running?"running":"idle")}<span class="mute">${tr.run}</span></h2>
    <div class="big">${pc.toFixed(0)}%</div><div class="mute">superbatch ${tr.superbatch} / ${tr.total} · loss ${tr.loss==null?"-":tr.loss.toFixed(6)}</div>
    ${chart(tr.points)}<div class="mute">the trainer writes its log when it saves a checkpoint, so this updates in steps</div>`;
  }
  const m=s.match;
  if(!m)$("#mt").innerHTML='<h2>A/B match</h2><div class="empty">no match logs yet</div>';
  else{
    const gm=m.games||0;
    $("#mt").innerHTML=`<h2>A/B match ${pill(m.running,m.running?"running":(m.finished?"finished":"idle"))}<span class="mute">${m.name}</span></h2>
    <div class="big">${m.elo==null?"-":(m.elo>0?"+":"")+m.elo.toFixed(1)+" ± "+m.err.toFixed(1)} Elo</div>
    <div class="mute">${gm} games · W ${m.wins||0} / D ${m.draws||0} / L ${m.losses||0}</div>`;
  }
  $("#upd").textContent="updated "+new Date().toLocaleTimeString()+" · refreshes every 3 s · read-only";
}
async function tick(){try{render(await (await fetch("/api/status",{cache:"no-store"})).json())}catch(e){$("#upd").textContent="server not reachable"}}
tick();setInterval(tick,3000);
</script></html>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--superbatches", type=int, default=200, help="total superbatches of the training run (for the percentage)")
    args = ap.parse_args()

    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith("/api/status"):
                body = json.dumps({"datagen": datagen_status(), "train": train_status(args.superbatches),
                                   "match": match_status()}).encode()
                ctype = "application/json"
            else:
                body, ctype = PAGE.encode(), "text/html; charset=utf-8"
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *a):
            pass

    srv = ThreadingHTTPServer(("127.0.0.1", args.port), H)
    print(f"Wyrdmate monitor: http://localhost:{args.port}  (Ctrl+C to stop)")
    srv.serve_forever()


if __name__ == "__main__":
    main()
