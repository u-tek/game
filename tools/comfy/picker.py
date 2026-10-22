#!/usr/bin/env python3
"""Art picker (owner, 2026-10-22): a page on this PC that shows each hero's and skin's base candidates side by
side. "Use this" puts that one in the game (roster_qa.py finishes it: face pass + 2x, install, quick rig);
"Regenerate" renders 2 new candidates for it. The worker starts by itself when there is work.
    python tools/comfy/picker.py [--port 8765] [--run DIR] [--no-worker]
or double-click tools/comfy/picker.bat. Listens on 127.0.0.1 only (--lan: the home network too). Picks change assets/ on this PC; Claude
commits them."""
import argparse
import io
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import roster_qa as Q  # noqa: E402

from PIL import Image  # noqa: E402

LOCK = threading.Lock()
RENDER_S, FINISH_S = 160, 180


def names():
    d = json.load(open(os.path.join(Q.ROOT, "data", "skins.json"), encoding="utf-8"))
    b = json.load(open(os.path.join(Q.ROOT, "data", "art_prompts.json"), encoding="utf-8"))
    skins = {(s["hero"], s["art"]): (s.get("name") or s["art"], s.get("line", "")) for s in d["skins"]}
    heroes = {h: v.get("name", h.title()) for h, v in b["heroes"].items()}
    return heroes, skins


class App:
    def __init__(self, run, spawn):
        self.run = run
        self.spawn = spawn
        self.heroes, self.skins = names()
        self.items = Q.items()
        self.thumbs = os.path.join(Q.qa_dir(run), "thumbs")
        os.makedirs(self.thumbs, exist_ok=True)
        self.started = 0.0

    def find(self, key):
        for i, (hero, sid, art, s0) in enumerate(self.items):
            if Q.key_of(hero, art) == key:
                return i, hero, sid, art, s0
        return None

    def ensure_worker(self, fin, ren):
        if not self.spawn or not (fin or ren) or Q.worker_pid(self.run):
            return
        if time.time() - self.started < 20:        # just started one; its pid file may not exist yet
            return
        self.started = time.time()
        log = open(os.path.join(Q.qa_dir(self.run), "worker_out.txt"), "a")
        subprocess.Popen([sys.executable, os.path.join(HERE, "roster_qa.py"), "--run", self.run], cwd=Q.ROOT,
                         stdout=log, stderr=subprocess.STDOUT, creationflags=0x08000000 if os.name == "nt" else 0)

    def state(self):
        picks, rerolls = Q.load(self.run, "picks.json"), Q.load(self.run, "rerolls.json")
        owner = Q.load(self.run, "owner_picks.json")
        fin, ren = Q.pending(self.run)
        self.ensure_worker(fin, ren)
        out = []
        for i, (hero, sid, art, s0) in enumerate(self.items):
            key = Q.key_of(hero, art)
            seeds = Q.wanted(s0, rerolls.get(key, 0))
            have = [s for s in seeds if Q.candidate(hero, art, s)]
            done = Q.done_info(self.run, key) or {}
            pick = picks.get(key)
            if pick is not None and done.get("seed") == int(pick):
                status = "in_game"
            elif pick is not None and "failed" in done:
                status = "failed"
            elif pick is not None:
                status = "finishing"
            elif len(have) < len(seeds):
                status = "rendering"
            else:
                status = "waiting"
            skin_name, line = self.skins.get((hero, art), (None, "")) if art else (None, "")
            out.append({"key": key, "n": i + 1, "hero": self.heroes.get(hero, hero.title()), "skin": skin_name,
                        "pack": line or "heroes", "seeds": seeds, "have": have,
                        "pick": int(pick) if pick is not None else None,
                        "by_owner": pick is not None and owner.get(key) == int(pick),
                        "in_game": done.get("seed"), "status": status})
        log = []
        try:
            with open(os.path.join(Q.qa_dir(self.run), "log.txt"), encoding="utf-8") as f:
                log = [x.strip() for x in f.readlines()[-6:]]
        except OSError:
            pass
        return {"items": out, "worker": bool(Q.worker_pid(self.run)), "to_finish": len(fin), "to_render": len(ren),
                "eta_min": round((len(fin) * FINISH_S + len(ren) * RENDER_S) / 60), "log": log}

    def pick(self, key, seed):
        f = self.find(key)
        if not f:
            return "unknown item"
        i, hero, sid, art, s0 = f
        if not Q.candidate(hero, art, seed):
            return "no such candidate"
        with LOCK:
            picks, owner = Q.load(self.run, "picks.json"), Q.load(self.run, "owner_picks.json")
            picks[key], owner[key] = seed, seed
            Q.save(self.run, "picks.json", picks)
            Q.save(self.run, "owner_picks.json", owner)
            done = Q.done_info(self.run, key)
            if done is not None and done.get("seed") != seed:
                os.remove(os.path.join(Q.qa_dir(self.run), "done", key + ".ok"))   # run-state marker: re-finish
        self.ensure_worker(*Q.pending(self.run))
        return None

    def regen(self, key):
        if not self.find(key):
            return "unknown item"
        with LOCK:
            picks, rerolls = Q.load(self.run, "picks.json"), Q.load(self.run, "rerolls.json")
            owner = Q.load(self.run, "owner_picks.json")
            rerolls[key] = int(rerolls.get(key, 0)) + 1
            picks.pop(key, None)
            owner.pop(key, None)
            Q.save(self.run, "rerolls.json", rerolls)
            Q.save(self.run, "picks.json", picks)
            Q.save(self.run, "owner_picks.json", owner)
        self.ensure_worker(*Q.pending(self.run))
        return None

    def image(self, key, seed, thumb):
        f = self.find(key)
        p = f and Q.candidate(f[1], f[3], seed)
        if not p:
            return None, None
        if not thumb:
            return open(p, "rb").read(), "image/png"
        t = os.path.join(self.thumbs, "%s_%d.jpg" % (key.replace("@", "_"), seed))
        if not os.path.exists(t):
            im = Image.open(p).convert("RGB")
            im.thumbnail((420, 540), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=86)
            with open(t, "wb") as fh:
                fh.write(buf.getvalue())
        return open(t, "rb").read(), "image/jpeg"


def handler(app):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def send(self, code, body, ctype, cache=False):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "max-age=86400" if cache else "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            if u.path == "/":
                return self.send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
            if u.path == "/api/state":
                return self.send(200, json.dumps(app.state()).encode(), "application/json")
            if u.path in ("/thumb", "/full"):
                try:
                    body, ctype = app.image(q["key"][0], int(q["seed"][0]), u.path == "/thumb")
                except (KeyError, ValueError):
                    body = None
                if body is None:
                    return self.send(404, b"not found", "text/plain")
                return self.send(200, body, ctype, cache=True)
            return self.send(404, b"not found", "text/plain")

        def do_POST(self):
            u = urlparse(self.path)
            try:
                data = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
                if u.path == "/api/pick":
                    err = app.pick(str(data["key"]), int(data["seed"]))
                elif u.path == "/api/regen":
                    err = app.regen(str(data["key"]))
                else:
                    return self.send(404, b"not found", "text/plain")
            except (KeyError, ValueError) as e:
                err = "bad request: %s" % e
            self.send(400 if err else 200, json.dumps({"error": err}).encode(), "application/json")
    return H


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Art Picker</title>
<style>
:root{--bg:#121316;--panel:#1b1d22;--line:#2b2e36;--text:#eceef2;--mute:#9aa0ab;--acc:#ff4d6d;--ok:#3ecf8e;--warn:#f5b84b;--info:#6aa8ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.4 system-ui,Segoe UI,sans-serif}
header{position:sticky;top:0;z-index:5;background:rgba(18,19,22,.96);border-bottom:1px solid var(--line);padding:12px 20px}
.top{display:flex;gap:16px;align-items:center;flex-wrap:wrap}h1{font-size:18px;margin:0;letter-spacing:.02em}
.stat{color:var(--mute)}.stat b{color:var(--text)}
.tabs{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}
.tabs button,.only{background:var(--panel);color:var(--text);border:1px solid var(--line);border-radius:999px;padding:6px 12px;cursor:pointer;font:inherit}
.tabs button.on{background:var(--text);color:#111;border-color:var(--text)}
.only{display:inline-flex;gap:6px;align-items:center}
main{padding:16px 20px 60px;display:grid;gap:14px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px 14px}
.head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:10px}
.name{font-weight:700;font-size:15px}.pack{color:var(--mute)}.n{color:var(--mute);font-variant-numeric:tabular-nums}
.chip{border-radius:999px;padding:2px 10px;font-size:12px;font-weight:600}
.in_game{background:rgba(62,207,142,.15);color:var(--ok)}.finishing{background:rgba(106,168,255,.15);color:var(--info)}
.rendering{background:rgba(154,160,171,.15);color:var(--mute)}.waiting{background:rgba(245,184,75,.15);color:var(--warn)}
.failed{background:rgba(255,77,109,.15);color:var(--acc)}
.regen{margin-left:auto;background:none;border:1px solid var(--line);color:var(--text);border-radius:8px;padding:6px 12px;cursor:pointer;font:inherit}
.regen:hover{border-color:var(--acc);color:var(--acc)}
.row{display:flex;gap:12px;overflow-x:auto;padding-bottom:4px}
.cand{flex:0 0 auto;width:260px;border:2px solid transparent;border-radius:10px;overflow:hidden;background:#0d0e10}
.cand.picked{border-color:var(--ok)}.cand img{display:block;width:260px;height:334px;object-fit:cover;cursor:zoom-in;background:#222}
.cand .bar{display:flex;align-items:center;justify-content:space-between;padding:6px 8px;gap:6px}
.seed{color:var(--mute);font-size:12px;font-variant-numeric:tabular-nums}
.use{background:var(--acc);color:#fff;border:0;border-radius:6px;padding:6px 12px;font-weight:700;cursor:pointer;font:inherit}
.use[disabled]{background:#2b2e36;color:var(--ok);cursor:default}
.ph{width:260px;height:334px;display:grid;place-items:center;color:var(--mute);border:1px dashed var(--line);border-radius:10px;flex:0 0 auto}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;place-items:center;z-index:9;cursor:zoom-out}
#lb img{max-width:96vw;max-height:96vh}
.log{color:var(--mute);font:12px ui-monospace,Consolas,monospace;white-space:pre-wrap;margin-top:8px;max-height:3.2em;overflow:hidden}
@media (max-width:600px){header,main{padding-left:12px;padding-right:12px}.cand,.cand img,.ph{width:200px}.cand img,.ph{height:257px}}
</style></head><body>
<header><div class="top"><h1>Art Picker</h1><span class="stat" id="stat">loading…</span>
<label class="only"><input type="checkbox" id="only"> only ones waiting for me</label></div>
<div class="tabs" id="tabs"></div><div class="log" id="log"></div></header>
<main id="list"></main><div id="lb"><img alt=""></div>
<script>
const PACKS={heroes:"Heroes"};let tab="all",S=null;const cards={},sigs={};
const $=s=>document.querySelector(s);
function packName(p){return PACKS[p]||p.replace(/_/g," ").replace(/\b\w/g,c=>c.toUpperCase())}
const LABEL={in_game:"In game",finishing:"Finishing…",rendering:"Rendering…",waiting:"Pick one",failed:"Failed: pick again"};
async function post(url,body){const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
 const j=await r.json();if(j.error)alert(j.error);load()}
function card(it){
 let h=`<div class="head"><span class="n">#${it.n}</span><span class="name">${it.hero}${it.skin?" · "+it.skin:""}</span>
 <span class="pack">${packName(it.pack)}</span><span class="chip ${it.status}">${LABEL[it.status]}${it.pick&&it.status!="waiting"?(it.by_owner?" · your pick":" · Claude's pick"):""}</span>
 <button class="regen" data-k="${it.key}">Regenerate (2 new)</button></div><div class="row">`;
 for(const s of it.seeds){
  if(it.have.includes(s)){const on=it.pick===s;
   h+=`<div class="cand${on?" picked":""}"><img loading="lazy" src="/thumb?key=${encodeURIComponent(it.key)}&seed=${s}" data-full="/full?key=${encodeURIComponent(it.key)}&seed=${s}" alt="">
   <div class="bar"><span class="seed">${s}</span><button class="use" data-k="${it.key}" data-s="${s}" ${on?"disabled":""}>${on?"✓ Chosen":"Use this"}</button></div></div>`}
  else h+=`<div class="ph">rendering ${s}…</div>`}
 return h+"</div>"}
function render(){
 const list=$("#list"),only=$("#only").checked;
 for(const it of S.items){
  const show=(tab=="all"||it.pack==tab)&&(!only||it.status=="waiting"||it.status=="failed");
  let el=cards[it.key];if(!el){el=document.createElement("section");el.className="card";cards[it.key]=el;list.appendChild(el)}
  el.style.display=show?"":"none";const sig=JSON.stringify(it);if(sigs[it.key]!==sig){el.innerHTML=card(it);sigs[it.key]=sig}}
 const c=k=>S.items.filter(i=>i.status==k).length;
 $("#stat").innerHTML=`<b>${c("in_game")}</b> in game · <b>${c("waiting")}</b> waiting for a pick · <b>${c("finishing")}</b> finishing · <b>${c("rendering")}</b> rendering · worker ${S.worker?"<b>running</b>":"idle"}${S.eta_min?` · about <b>${S.eta_min} min</b> of GPU work queued`:""}`;
 $("#log").textContent=S.log.slice(-2).join("\n")}
function tabs(){const packs=["all",...new Set(S.items.map(i=>i.pack))];
 $("#tabs").innerHTML=packs.map(p=>`<button data-t="${p}" class="${p==tab?"on":""}">${p=="all"?"All":packName(p)}</button>`).join("")}
async function load(){S=await (await fetch("/api/state")).json();if(!$("#tabs").children.length)tabs();render()}
document.addEventListener("click",e=>{const t=e.target;
 if(t.dataset.t){tab=t.dataset.t;tabs();render()}
 else if(t.classList.contains("use")&&!t.disabled){t.disabled=true;t.textContent="…";post("/api/pick",{key:t.dataset.k,seed:+t.dataset.s})}
 else if(t.classList.contains("regen")){if(confirm("Render 2 new options for this one? About 6 minutes of GPU."))post("/api/regen",{key:t.dataset.k})}
 else if(t.dataset.full){$("#lb img").src=t.dataset.full;$("#lb").style.display="grid"}
 else if(t.closest("#lb"))$("#lb").style.display="none"});
$("#only").addEventListener("change",render);document.addEventListener("keydown",e=>{if(e.key=="Escape")$("#lb").style.display="none"});
load();setInterval(load,10000);
</script></body></html>"""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--run", default=Q.DEFAULT_RUN)
    ap.add_argument("--no-worker", action="store_true", help="never start roster_qa.py (tests)")
    ap.add_argument("--lan", action="store_true", help="also reachable from a phone on the same Wi-Fi (no password)")
    a = ap.parse_args(argv)
    app = App(os.path.abspath(a.run), not a.no_worker)
    srv = ThreadingHTTPServer(("0.0.0.0" if a.lan else "127.0.0.1", a.port), handler(app))
    print("Art picker on http://127.0.0.1:%d  (close this window to stop)" % a.port, flush=True)
    if a.lan:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("10.255.255.255", 1))
            print("On a phone on the same Wi-Fi: http://%s:%d" % (s.getsockname()[0], a.port), flush=True)
        except OSError:
            pass
        finally:
            s.close()
    srv.serve_forever()


if __name__ == "__main__":
    main()
