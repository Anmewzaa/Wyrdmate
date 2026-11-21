"""Local progress pages for datagen, training and A/B matches (read-only, stdlib only).

    python scripts/monitor.py            # then open http://localhost:8765 (pages: /, /datagen, /train, /match)
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
        running = (not done) and age(p) < RUNNING_SECS
        start = os.path.getctime(p)  # log creation time = job start (Windows creation time)
        end = time.time() if running else os.path.getmtime(p)
        elapsed = max(1.0, end - start)
        rate = g / elapsed * 60  # games per minute over the whole run so far
        eta = (tot - g) / rate * 60 if running and rate > 0 else None
        jobs.append({"seed": seed, "games": g, "total": tot, "positions": pos, "done": done,
                     "running": running, "elapsed": elapsed, "rate": rate, "eta": eta})
    return {"name": name[:-4] if name.endswith("part") else name, "jobs": jobs}


def reference_loss():
    try:
        with open(os.path.join(ROOT, "docs", "progress", "data.json"), encoding="utf-8") as f:
            return [{"name": s["name"], "points": s["points"]} for s in json.load(f)["loss"]][-2:]
    except (OSError, ValueError, KeyError):
        return []


def train_status(total_sb):
    logs = glob.glob(os.path.join(ROOT, "checkpoints", "*", "log.txt"))
    if not logs:
        return None
    p = max(logs, key=os.path.getmtime)
    last_by_sb = {}
    for line in read_text(p).splitlines():
        parts = line.strip().split(",")
        if len(parts) == 3:
            try:
                last_by_sb[int(parts[0])] = float(parts[2])
            except ValueError:
                pass
    pts = [[sb, last_by_sb[sb]] for sb in sorted(last_by_sb)]
    step = max(1, len(pts) // 200)
    gain10 = None
    if len(pts) > 10 and pts[-11][1] > 0:
        gain10 = 100.0 * (pts[-11][1] - pts[-1][1]) / pts[-11][1]  # % loss drop over the last 10 superbatches
    return {"run": os.path.basename(os.path.dirname(p)), "superbatch": pts[-1][0] if pts else 0,
            "total": total_sb, "loss": pts[-1][1] if pts else None, "best": min((q[1] for q in pts), default=None),
            "gain10": gain10, "points": pts[::step], "rows": pts[-15:][::-1],
            "reference": reference_loss(), "running": age(p) < RUNNING_SECS}


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


PAGE = r"""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wyrdmate monitor</title>
<style>
:root{--bg:#fff;--ink:#1f1f1e;--mute:#6b6a66;--line:#e1e0d9;--card:#f6f5f0;--blue:#2a78d6;--green:#1baf7a;--red:#e34948;--orange:#eb6834}
@media (prefers-color-scheme:dark){:root{--bg:#171716;--ink:#ecebe6;--mute:#a09f98;--line:#33332f;--card:#222220;--blue:#5a9be8;--green:#35c593;--red:#ef6b6a;--orange:#f08a5d}}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 "Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:860px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:22px;margin:0 0 2px}.sub{color:var(--mute);font-size:13px;margin:0 0 14px}
nav{display:flex;gap:6px;margin:0 0 16px;flex-wrap:wrap}
nav a{padding:5px 14px;border-radius:16px;color:var(--mute);text-decoration:none;border:1px solid var(--line);font-size:14px}
nav a.on{background:var(--ink);color:var(--bg);border-color:var(--ink)}
section,.card{background:var(--card);border-radius:10px;padding:14px 16px;margin:0 0 16px}
h2{font-size:15px;margin:0 0 10px;display:flex;gap:8px;align-items:center}
.pill{font-size:11px;padding:1px 8px;border-radius:10px;border:1px solid var(--line);color:var(--mute)}
.pill.on{color:var(--green);border-color:var(--green)}
.row{display:grid;grid-template-columns:70px 1fr 190px;gap:10px;align-items:center;margin:6px 0;font-size:13px}
.bar{height:12px;background:var(--line);border-radius:6px;overflow:hidden;display:flex}.bar>i{display:block;height:100%;background:var(--blue);transition:width .6s}
.bar.done>i{background:var(--green)}.num{color:var(--mute);text-align:right;font-variant-numeric:tabular-nums}
.big{font-size:28px;font-weight:700;font-variant-numeric:tabular-nums}.mute{color:var(--mute);font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:10px 0 4px}
.stat b{display:block;font-size:19px;font-variant-numeric:tabular-nums}.stat span{color:var(--mute);font-size:12px}
table{border-collapse:collapse;width:100%;font-size:13px;font-variant-numeric:tabular-nums}th,td{text-align:right;padding:3px 6px;border-bottom:1px solid var(--line)}th:first-child,td:first-child{text-align:left}
svg{width:100%;height:auto;display:block}.empty{color:var(--mute);font-size:13px}.ok{color:var(--green)}.bad{color:var(--red)}
.leg{display:flex;gap:14px;font-size:12px;color:var(--mute);margin-top:4px;flex-wrap:wrap}.leg i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px}
a.card{display:block;color:inherit;text-decoration:none}
</style>
<main>
<h1>Wyrdmate monitor</h1><p class="sub" id="upd">connecting...</p>
<nav id="nav"></nav><div id="view"></div>
</main>
<script>
const $=s=>document.querySelector(s), fmt=n=>n.toLocaleString("en-US");
const PAGES=[["/","Overview"],["/datagen","Datagen"],["/train","Training"],["/match","A/B match"]];
const page=location.pathname.replace(/\/$/,"")||"/";
$("#nav").innerHTML=PAGES.map(([h,n])=>`<a href="${h}" class="${h===page?'on':''}">${n}</a>`).join("");
const pill=(on,t)=>`<span class="pill ${on?'on':''}">${t}</span>`;
const dur=s=>{if(s==null||!isFinite(s))return"-";s=Math.round(s);const h=Math.floor(s/3600),m=Math.floor(s%3600/60);return h?`${h}h ${m}m`:m?`${m}m ${s%60}s`:`${s}s`};
const stat=(v,l)=>`<div class="stat"><b>${v}</b><span>${l}</span></div>`;
const COLS=["var(--blue)","var(--orange)","var(--green)"];
function chart(series){
  const all=series.flatMap(s=>s.points);if(all.length<2)return"";
  const W=800,H=220,L=58,B=24,xs=all.map(p=>p[0]),ys=all.map(p=>Math.log10(p[1]));
  const x0=Math.min(...xs),x1=Math.max(...xs),y0=Math.min(...ys),y1=Math.max(...ys),pad=(y1-y0)*.08||.1;
  const X=v=>L+(v-x0)/((x1-x0)||1)*(W-L-8),Y=v=>8+(1-(v-y0+pad)/((y1-y0)+2*pad))*(H-B-8);
  let g="";for(let k=0;k<4;k++){const v=y0+(y1-y0)*k/3,yy=Y(v);g+=`<line x1="${L}" x2="${W-8}" y1="${yy}" y2="${yy}" stroke="var(--line)"/><text x="${L-6}" y="${yy+4}" font-size="10" fill="var(--mute)" text-anchor="end">${Math.pow(10,v).toFixed(5)}</text>`}
  const lines=series.map((s,i)=>s.points.length<2?"":`<path d="${s.points.map((p,j)=>(j?"L":"M")+X(p[0]).toFixed(1)+" "+Y(Math.log10(p[1])).toFixed(1)).join("")}" fill="none" stroke="${COLS[i%3]}" stroke-width="${i===series.length-1?3:1.8}" ${i===series.length-1?"":'stroke-dasharray="5 3"'}/>`).join("");
  return `<svg viewBox="0 0 ${W} ${H}">${g}${lines}<text x="${L}" y="${H-4}" font-size="11" fill="var(--mute)">superbatch ${x0}</text><text x="${W-8}" y="${H-4}" font-size="11" fill="var(--mute)" text-anchor="end">${x1}</text></svg>
  <div class="leg">${series.map((s,i)=>`<span><i style="background:${COLS[i%3]}"></i>${s.name}</span>`).join("")}</div>`;
}
function dgView(dg,full){
  if(!dg)return'<h2>Datagen</h2><div class="empty">no datagen logs yet</div>';
  const J=dg.jobs,g=J.reduce((a,j)=>a+j.games,0),t=J.reduce((a,j)=>a+j.total,0),p=J.reduce((a,j)=>a+j.positions,0);
  const on=J.some(j=>j.running),pc=t?100*g/t:0,rate=J.reduce((a,j)=>a+(j.running?j.rate:0),0),etas=J.filter(j=>j.eta!=null).map(j=>j.eta);
  let h=`<h2>Datagen ${pill(on,on?"running":(pc>=100?"done":"idle"))}<span class="mute">${dg.name}</span></h2><div class="big">${pc.toFixed(1)}%</div>
  <div class="mute">${fmt(g)} / ${fmt(t)} games · ${fmt(p)} positions</div>`;
  if(full){
    const el=Math.max(...J.map(j=>j.elapsed));
    h+=`<div class="grid">${stat(on?rate.toFixed(0):"-","games / min (all jobs)")}${stat(on&&etas.length?dur(Math.max(...etas)):"-","time left (estimate)")}${stat(dur(el),"elapsed")}${stat(g?(p/g).toFixed(1):"-","positions / game")}</div>`;
    h+=J.map(j=>{const q=j.total?100*j.games/j.total:0;return `<div class="row"><span>seed ${j.seed}</span><div class="bar ${j.done?'done':''}"><i style="width:${q}%"></i></div><span class="num">${fmt(j.games)}/${fmt(j.total)} · ${q.toFixed(0)}% · ${j.running?j.rate.toFixed(0)+"/min":(j.done?"done":"idle")}</span></div>`}).join("");
    h+=`<p class="mute">Speed is the average since each job started; the time left assumes it stays that speed.</p>`;
  }
  return h;
}
function trView(tr,full){
  if(!tr)return'<h2>Training</h2><div class="empty">no training logs yet</div>';
  const pc=tr.total?100*tr.superbatch/tr.total:0;
  let h=`<h2>Training ${pill(tr.running,tr.running?"running":"idle")}<span class="mute">${tr.run}</span></h2><div class="big">${pc.toFixed(0)}%</div>
  <div class="mute">superbatch ${tr.superbatch} / ${tr.total} · loss ${tr.loss==null?"-":tr.loss.toFixed(6)}</div>`;
  if(full){
    h+=`<div class="grid">${stat(tr.loss==null?"-":tr.loss.toFixed(6),"current loss")}${stat(tr.best==null?"-":tr.best.toFixed(6),"best loss")}${stat(tr.gain10==null?"-":tr.gain10.toFixed(2)+"%","loss drop, last 10 superbatches")}</div>`;
    h+=chart([...tr.reference.map(r=>({name:r.name+" (reference)",points:r.points})),{name:tr.run+" (this run)",points:tr.points}]);
    h+=`<p class="mute">Loss is not comparable across different datasets; the reference curves only show the shape. The trainer writes its log when it saves a checkpoint, so this updates in steps.</p>`;
    h+=`<table><tr><th>superbatch</th><th>loss</th><th>change</th></tr>${tr.rows.map((r,i)=>{const n=tr.rows[i+1];const d=n?100*(r[1]-n[1])/n[1]:null;return `<tr><td>${r[0]}</td><td>${r[1].toFixed(6)}</td><td>${d==null?"-":(d>0?"+":"")+d.toFixed(2)+"%"}</td></tr>`}).join("")}</table>`;
  }
  return h;
}
function mtView(m,full){
  if(!m)return'<h2>A/B match</h2><div class="empty">no match logs yet</div>';
  const gm=m.games||0,pass=m.elo!=null&&m.elo-m.err>0;
  let h=`<h2>A/B match ${pill(m.running,m.running?"running":(m.finished?"finished":"idle"))}<span class="mute">${m.name}</span></h2>
  <div class="big">${m.elo==null?"-":(m.elo>0?"+":"")+m.elo.toFixed(1)+" ± "+m.err.toFixed(1)} Elo</div><div class="mute">${gm} games · W ${m.wins||0} / D ${m.draws||0} / L ${m.losses||0}</div>`;
  if(full&&gm){
    const sc=(m.wins+m.draws/2)/gm*100;
    h+=`<div class="grid">${stat(sc.toFixed(1)+"%","score")}${stat(m.elo==null?"-":(m.elo-m.err).toFixed(1),"lower bound (Elo)")}${stat(m.elo==null?"-":`<span class="${pass?'ok':'bad'}">${pass?"passes":"does not pass"}</span>`,"rule 2: lower bound above 0")}</div>
    <div class="bar" style="margin-top:8px"><i style="width:${100*m.wins/gm}%;background:var(--green)"></i><i style="width:${100*m.draws/gm}%;background:var(--mute)"></i><i style="width:${100*m.losses/gm}%;background:var(--red)"></i></div>
    <div class="leg"><span><i style="background:var(--green)"></i>wins</span><span><i style="background:var(--mute)"></i>draws</span><span><i style="background:var(--red)"></i>losses</span></div>`;
  }
  return h;
}
function render(s){
  let h="";
  if(page==="/datagen")h=`<section>${dgView(s.datagen,true)}</section>`;
  else if(page==="/train")h=`<section>${trView(s.train,true)}</section>`;
  else if(page==="/match")h=`<section>${mtView(s.match,true)}</section>`;
  else h=`<a class="card" href="/datagen">${dgView(s.datagen,false)}</a><a class="card" href="/train">${trView(s.train,false)}</a><a class="card" href="/match">${mtView(s.match,false)}</a>`;
  $("#view").innerHTML=h;
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
