#!/usr/bin/env python3
"""Art picker (owner, 2026-10-22): a page on this PC that shows one hero or skin at a time, its base candidates
as full-screen cards side by side ("i want them as cards side by side taking up the whole screen"). "Use this" puts that one in the game (roster_qa.py finishes it: face pass + 2x, install, quick rig);
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
:root{--bg:#0f1013;--panel:#1a1c21;--line:#2b2e36;--text:#eceef2;--mute:#9aa0ab;--acc:#ff4d6d;--ok:#3ecf8e;--warn:#f5b84b;--info:#6aa8ff}
*{box-sizing:border-box}html,body{height:100%}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.4 system-ui,Segoe UI,sans-serif;display:grid;grid-template-rows:auto 1fr auto;overflow:hidden}
.bar{display:flex;align-items:center;gap:12px;padding:10px 16px;background:var(--panel);border-bottom:1px solid var(--line);flex-wrap:wrap}
.bot{border-top:1px solid var(--line);border-bottom:0;color:var(--mute);font-size:12px;padding:6px 16px}
.nav{background:#24272e;color:var(--text);border:1px solid var(--line);border-radius:8px;width:44px;height:40px;font-size:18px;cursor:pointer}
.nav:hover{border-color:var(--text)}
.title{display:flex;flex-direction:column;min-width:0}.name{font-size:20px;font-weight:800;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sub{color:var(--mute)}.chip{border-radius:999px;padding:3px 10px;font-size:12px;font-weight:700}
.in_game{background:rgba(62,207,142,.15);color:var(--ok)}.finishing{background:rgba(106,168,255,.15);color:var(--info)}
.rendering{background:rgba(154,160,171,.15);color:var(--mute)}.waiting{background:rgba(245,184,75,.15);color:var(--warn)}
.failed{background:rgba(255,77,109,.15);color:var(--acc)}
.sp{flex:1}select,.ctl{background:#24272e;color:var(--text);border:1px solid var(--line);border-radius:8px;padding:8px 10px;font:inherit}
.ctl{display:inline-flex;gap:6px;align-items:center;cursor:pointer}
.regen{background:none;border:1px solid var(--line);color:var(--text);border-radius:8px;padding:8px 14px;cursor:pointer;font:inherit;font-weight:600}
.regen:hover{border-color:var(--acc);color:var(--acc)}
#stage{display:flex;gap:14px;padding:14px;min-height:0}
.card{flex:1 1 0;min-width:0;display:flex;flex-direction:column;background:var(--panel);border:3px solid var(--line);border-radius:14px;overflow:hidden}
.card.picked{border-color:var(--ok);box-shadow:0 0 0 1px var(--ok),0 0 30px rgba(62,207,142,.25)}
.pic{flex:1;min-height:0;display:grid;place-items:center;background:#8f9196;cursor:zoom-in}
.pic img{width:100%;height:100%;object-fit:contain;display:block}
.foot{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 12px}
.seed{color:var(--mute);font-variant-numeric:tabular-nums}.key{color:var(--mute);border:1px solid var(--line);border-radius:5px;padding:0 6px;margin-right:6px;font-size:12px}
.use{background:var(--acc);color:#fff;border:0;border-radius:8px;padding:10px 22px;font-weight:800;font-size:15px;cursor:pointer}
.use[disabled]{background:rgba(62,207,142,.15);color:var(--ok);cursor:default}
.ph{flex:1 1 0;display:grid;place-items:center;color:var(--mute);border:3px dashed var(--line);border-radius:14px}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;place-items:center;z-index:9;cursor:zoom-out}
#lb img{max-width:98vw;max-height:98vh}
#empty{margin:auto;color:var(--mute);font-size:16px}
</style></head><body>
<div class="bar"><button class="nav" id="prev" title="Previous (←)">◀</button>
<div class="title"><span class="name" id="name">loading…</span><span class="sub" id="sub"></span></div>
<span class="chip" id="chip"></span><span class="sp"></span>
<button class="regen" id="regen" title="R">Regenerate (2 new)</button>
<select id="pack"></select><label class="ctl"><input type="checkbox" id="only"> waiting for me</label>
<button class="nav" id="next" title="Next (→)">▶</button></div>
<div id="stage"></div>
<div class="bar bot"><span id="stat"></span><span class="sp"></span><span>← → move · 1 2 3 4 pick · R regenerate · click a picture to enlarge</span></div>
<div id="lb"><img alt=""></div>
<script>
const LABEL={in_game:"In game",finishing:"Finishing…",rendering:"Rendering…",waiting:"Pick one",failed:"Failed: pick again"};
const $=s=>document.querySelector(s);let S=null,cur=null,sig="";
const pn=p=>p=="heroes"?"Heroes":p.replace(/_/g," ").replace(/\b\w/g,c=>c.toUpperCase());
const full=(k,s)=>`/full?key=${encodeURIComponent(k)}&seed=${s}`;
function list(){const p=$("#pack").value,o=$("#only").checked;
 return S.items.filter(i=>(p=="all"||i.pack==p)&&(!o||i.status=="waiting"||i.status=="failed"||i.key==cur))}
function item(){return S.items.find(i=>i.key==cur)}
function move(d){const L=list();if(!L.length)return;let i=L.findIndex(x=>x.key==cur);
 i=i<0?0:Math.min(L.length-1,Math.max(0,i+d));cur=L[i].key;draw(true);preload(L[i+1])}
function preload(it){if(it)for(const s of it.have){const im=new Image();im.src=full(it.key,s)}}
function draw(force){const it=item();if(!it){$("#stage").innerHTML='<div id="empty">Nothing here.</div>';return}
 const L=list(),pos=L.findIndex(x=>x.key==it.key)+1;
 $("#name").textContent=it.hero+(it.skin?" · "+it.skin:"");
 $("#sub").textContent=`${pn(it.pack)} · ${pos||"–"} of ${L.length}`;
 const c=$("#chip");c.className="chip "+it.status;
 c.textContent=LABEL[it.status]+(it.pick&&it.status!="waiting"?(it.by_owner?" · your pick":" · Claude's pick"):"");
 const s2=JSON.stringify([it.key,it.seeds,it.have,it.pick]);if(!force&&s2==sig)return;sig=s2;
 $("#stage").innerHTML=it.seeds.map((s,n)=>it.have.includes(s)?
  `<div class="card${it.pick===s?" picked":""}"><div class="pic" data-full="${full(it.key,s)}"><img src="${full(it.key,s)}" alt=""></div>
   <div class="foot"><span class="seed"><span class="key">${n+1}</span>${s}</span>
   <button class="use" data-s="${s}" ${it.pick===s?"disabled":""}>${it.pick===s?"✓ In the game":"Use this"}</button></div></div>`
  :`<div class="ph">rendering ${s}…</div>`).join("")}
function stat(){const c=k=>S.items.filter(i=>i.status==k).length;
 $("#stat").textContent=`${c("in_game")} in game · ${c("waiting")} waiting for a pick · ${c("finishing")} finishing · ${c("rendering")} rendering · worker ${S.worker?"running":"idle"}${S.eta_min?` · about ${S.eta_min} min of GPU work queued`:""}`}
async function load(){S=await (await fetch("/api/state")).json();
 if(!$("#pack").children.length){$("#pack").innerHTML=["all",...new Set(S.items.map(i=>i.pack))].map(p=>`<option value="${p}">${p=="all"?"All packs":pn(p)}</option>`).join("")}
 if(!cur){const L=list();cur=(L.find(i=>i.status=="waiting")||L[0]||{}).key}
 draw(false);stat()}
async function post(url,body){const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});
 const j=await r.json();if(j.error)alert(j.error);await load()}
async function pick(s){const it=item();if(!it||!it.have.includes(s)||it.pick===s)return;await post("/api/pick",{key:it.key,seed:s});draw(true);setTimeout(()=>move(1),350)}
async function regen(){const it=item();if(it&&confirm(`Render 2 new options for ${it.hero}${it.skin?" · "+it.skin:""}? About 6 minutes of GPU.`)){await post("/api/regen",{key:it.key});draw(true)}}
document.addEventListener("click",e=>{const t=e.target,p=t.closest(".pic");
 if(t.id=="prev")move(-1);else if(t.id=="next")move(1);else if(t.id=="regen")regen();
 else if(t.classList.contains("use")&&!t.disabled)pick(+t.dataset.s);
 else if(p){$("#lb img").src=p.dataset.full;$("#lb").style.display="grid"}
 else if(t.closest("#lb"))$("#lb").style.display="none"});
document.addEventListener("keydown",e=>{if(e.target.tagName=="SELECT")return;const it=item();
 if(e.key=="Escape")$("#lb").style.display="none";else if(e.key=="ArrowLeft")move(-1);else if(e.key=="ArrowRight")move(1);
 else if(/^[1-9]$/.test(e.key)&&it){const s=it.seeds[+e.key-1];if(s)pick(s)}else if(e.key=="r"||e.key=="R")regen()});
$("#pack").addEventListener("change",()=>{cur=null;load()});$("#only").addEventListener("change",()=>{const L=list();if(!L.some(i=>i.key==cur))cur=(L[0]||{}).key;draw(true)});
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
