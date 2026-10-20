#!/usr/bin/env python3
"""ComfyUI HTTP client for the Halo & Horn art pipeline (Python 3 standard library only).

Environment:
    COMFYUI_URL      base URL of the server, e.g. https://my-tunnel.example.com (no trailing /)
    COMFYUI_AUTH     optional Authorization header value: "Basic ...", "Bearer ...", or "user:pass"
                     (user:pass is turned into Basic auth). Never written to disk or printed.
    COMFYUI_HEADERS  optional JSON object of extra headers (e.g. Cloudflare Access service tokens)
    COMFYUI_CA_BUNDLE optional CA file for TLS (SSL_CERT_FILE / REQUESTS_CA_BUNDLE also work)
    HALO_ART_SRC     optional override of the art_src/ output root (tests use a temp dir)

CLI:
    python3 tools/comfy/comfy.py ping                     server version, GPU, VRAM
    python3 tools/comfy/comfy.py discover [--object-info FILE]
                     list checkpoints/LoRAs/upscalers/custom nodes, pick a checkpoint + family,
                     cache to art_src/_server/discovery.json (+ object_info.json)
    python3 tools/comfy/comfy.py pin CHECKPOINT [--family F]
                     pin the model for the whole roster (art_src/_server/pin.json; survives new shells).
                     Precedence everywhere: --ckpt > COMFYUI_CKPT > pin > discovery's recommendation.
    python3 tools/comfy/comfy.py queue GRAPH.json [--out DIR] [--dry-run]
                     re-send a saved API graph from a LIVE run (candidates/<id>_s<seed>.api.json) and
                     download its outputs. Dry-run JSON cannot be re-sent: it names a placeholder
                     checkpoint and images that were never uploaded (refused with a message).

Every request goes to the URL in COMFYUI_URL only. In --dry-run mode nothing is sent: queue() writes
the exact POST /prompt body to art_src/_dryrun/<label>.json and returns a fake prompt id.
Every graph -- composed by the pipeline or loaded from a file -- passes prompts.check_graph() (the
content rules in data/art_prompts.json) before it is written or sent.
"""
import base64
import json
import mimetypes
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import core_nodes  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def art_src():
    return os.path.abspath(os.environ.get("HALO_ART_SRC") or os.path.join(ROOT, "art_src"))


def dryrun_dir():
    return os.path.join(art_src(), "_dryrun")


def rel(p):
    """`p` relative to the repo root for messages; the absolute path when that is impossible (Windows:
    another drive, e.g. a temp folder on C: with the repo on D:)."""
    try:
        return os.path.relpath(p, ROOT)
    except ValueError:
        return os.path.abspath(p)


def server_dir():
    return os.path.join(art_src(), "_server")


class ComfyError(RuntimeError):
    pass


# ------------------------------------------------------------------ discovery (pure functions)
# Optional custom nodes we know how to use or report. Matching is by exact class name.
KNOWN_CUSTOM = {
    # RemoveBackground: ComfyUI's core BiRefNet node (0.39+, model in models/background_removal); it
    # needs no extra pip package and clears gaps between hair, weapon and body that flood fill misses.
    "background_removal": ["RemoveBackground", "InspyrenetRembg", "InspyrenetRembgAdvanced", "RMBG", "BiRefNetRMBG",
                           "BRIA_RMBG_Zho", "ImageRemoveBackground+", "easy imageRemBg",
                           "Image Rembg (Remove Background)", "LayerMask: RmBgUltra V2"],
    "ipadapter": ["IPAdapterUnifiedLoader", "IPAdapterAdvanced", "IPAdapter", "IPAdapterModelLoader",
                  "IPAdapterFaceID"],
    "face_detailer": ["FaceDetailer", "UltralyticsDetectorProvider", "SAMLoader", "BboxDetectorSEGS"],
    "controlnet_preprocessors": ["DWPreprocessor", "OpenposePreprocessor", "AnimeLineArtPreprocessor",
                                 "LineArtPreprocessor", "CannyEdgePreprocessor", "DepthAnythingV2Preprocessor"],
    "core_extras": ["ControlNetLoader", "ControlNetApplyAdvanced", "UpscaleModelLoader",
                    "ImageUpscaleWithModel", "ModelSamplingDiscrete", "RescaleCFG", "ImageCompositeMasked"],
}
# Preference order for background removal (first present one wins).
REMBG_PREFERENCE = KNOWN_CUSTOM["background_removal"]

# Checkpoint name heuristics. Families themselves (tags, sampler settings) live in data/art_prompts.json.
CKPT_BAD = ["refiner", "inpaint", "turbo", "lightning", "lcm", "hyper", "sd15", "sd_15", "v1-5", "v1_5",
            "sd1.5", "svd", "sd3", "flux", "cascade", "realistic", "realvis", "photo", "juggernaut", "pixart"]
CKPT_GOOD = [("noob", 10), ("illustrious", 10), ("illu", 9), ("ilxl", 9), ("wai", 6), ("pony", 7),
             ("pdxl", 7), ("autismmix", 7), ("animagine", 6)]
CKPT_BONUS = [("anime", 3), ("xl", 1)]
DEFAULT_FAMILY_PATTERNS = [
    ("noobai_vpred", [r"v[-_ ]?pred"]),
    ("pony", [r"pony", r"pdxl", r"autismmix"]),
    ("illustrious", [r"illustrious", r"illu", r"noob", r"ilxl", r"wai", r"obsession"]),
    ("animagine", [r"animagine"]),
]


def combo_options(object_info, cls, name):
    info = (object_info or {}).get(cls) or {}
    inp = info.get("input", {}) or {}
    spec = (inp.get("required", {}) or {}).get(name) or (inp.get("optional", {}) or {}).get(name)
    return core_nodes._combo_options(spec) or []


def detect_family(ckpt_name, families=None):
    """Guess the model family from a checkpoint file name. families: the bible's "families" dict
    (each may carry "match": [regex, ...]); falls back to DEFAULT_FAMILY_PATTERNS.
    Returns (family, guessed: bool)."""
    name = (ckpt_name or "").lower()
    patterns = DEFAULT_FAMILY_PATTERNS
    if families:
        patterns = [(k, v.get("match", [])) for k, v in families.items() if v.get("match")]
    for fam, pats in patterns:
        if any(re.search(p, name) for p in pats):
            return fam, False
    return "illustrious", True


def checkpoint_arch(meta):
    """Architecture from a checkpoint's safetensors metadata (GET /view_metadata/checkpoints):
    "sdxl", "sd1", "sd2", "sd3", "flux", other modelspec strings, or None when unknown."""
    if not isinstance(meta, dict):
        return None
    arch = str(meta.get("modelspec.architecture") or "").lower()
    base = str(meta.get("ss_base_model_version") or "").lower()
    if "flux" in arch or base.startswith("flux"):
        return "flux"
    if "stable-diffusion-3" in arch or base.startswith("sd3"):
        return "sd3"
    if "xl" in arch or base.startswith("sdxl"):
        return "sdxl"
    if "stable-diffusion-v1" in arch or base.startswith("sd_v1"):
        return "sd1"
    if "stable-diffusion-v2" in arch or base.startswith("sd_v2"):
        return "sd2"
    return arch or None


def rank_checkpoints(names, arch=None):
    """Best-first list of (score, name) for picking an anime SDXL checkpoint. `arch` {name: arch}
    from checkpoint_arch() adds +5 for SDXL and -50 for anything else (SD1.5, Flux, SD3)."""
    out = []
    arch = arch or {}
    for n in names:
        low = n.lower()
        s = max([w for k, w in CKPT_GOOD if k in low] or [0]) + sum(w for k, w in CKPT_BONUS if k in low)
        if any(b in low for b in CKPT_BAD):
            s -= 50
        a = arch.get(n)
        if a == "sdxl":
            s += 5
        elif a:
            s -= 50
        out.append((s, n))
    out.sort(key=lambda t: (-t[0], t[1].lower()))
    return out


def upscaler_scale(name):
    m = re.search(r"(?:^|[^0-9])([1-8])x|x([1-8])(?:[^0-9]|$)", name.lower())
    if m:
        return int(m.group(1) or m.group(2))
    return 4


def rank_upscalers(names):
    pref = [("animesharp", 10), ("anime", 8), ("ultrasharp", 6), ("esrgan", 4), ("4x", 2), ("2x", 1)]
    out = sorted(((sum(w for k, w in pref if k in n.lower()), n) for n in names), key=lambda t: (-t[0], t[1].lower()))
    return out


def _outputs(info):
    return list(info.get("output", []) or [])


def provider_for(object_info, type_name):
    """A node class that outputs `type_name` and needs no links (only widgets), e.g. a model loader
    for a custom background-removal node. Returns (class, output_index) or None."""
    for cls, info in sorted(object_info.items()):
        outs = _outputs(info)
        if type_name not in outs:
            continue
        req = (info.get("input", {}) or {}).get("required", {}) or {}
        if all(core_nodes._combo_options(s) is not None or (s and s[0] in ("INT", "FLOAT", "STRING", "BOOLEAN"))
               for s in req.values()):
            return cls, outs.index(type_name)
    return None


def rembg_recipe(object_info):
    """How to call the first usable background-removal node on this server, or None.
    {"class", "image_input", "providers": {input: [class, out_index]}, "mask_output", "image_output"}"""
    for cls in REMBG_PREFERENCE:
        info = (object_info or {}).get(cls)
        if not info:
            continue
        req = (info.get("input", {}) or {}).get("required", {}) or {}
        image_inputs = [k for k, s in req.items() if s and s[0] == "IMAGE"]
        if len(image_inputs) != 1:
            continue
        providers, ok = {}, True
        for k, s in req.items():
            if k in image_inputs or core_nodes._combo_options(s) is not None:
                continue
            t = s[0] if s else None
            if t in ("INT", "FLOAT", "STRING", "BOOLEAN"):
                continue
            prov = provider_for(object_info, t)
            if not prov:
                ok = False
                break
            providers[k] = list(prov)
        outs = _outputs(info)
        if not ok or not ("MASK" in outs or "IMAGE" in outs):
            continue
        return {"class": cls, "image_input": image_inputs[0], "providers": providers,
                "mask_output": outs.index("MASK") if "MASK" in outs else None,
                "image_output": outs.index("IMAGE") if "IMAGE" in outs else None}
    return None


def parse_object_info(object_info, families=None, arch=None):
    """Summarize a /object_info payload: model files, samplers, custom nodes, recommendations.
    arch: optional {checkpoint: architecture} from the server's safetensors metadata."""
    oi = object_info or {}
    d = {
        "node_count": len(oi),
        "checkpoints": combo_options(oi, "CheckpointLoaderSimple", "ckpt_name"),
        "loras": combo_options(oi, "LoraLoader", "lora_name"),
        "vaes": combo_options(oi, "VAELoader", "vae_name"),
        "upscale_models": combo_options(oi, "UpscaleModelLoader", "model_name"),
        "controlnets": combo_options(oi, "ControlNetLoader", "control_net_name"),
        "clip_vision": combo_options(oi, "CLIPVisionLoader", "clip_name"),
        "samplers": combo_options(oi, "KSampler", "sampler_name"),
        "schedulers": combo_options(oi, "KSampler", "scheduler"),
        "custom": {k: [c for c in v if c in oi] for k, v in KNOWN_CUSTOM.items()},
        "missing_core": [c for c in core_nodes.CORE if c not in oi],
    }
    ranked = rank_checkpoints(d["checkpoints"], arch)
    d["checkpoint_arch"] = dict(arch or {})
    ckpt = ranked[0][1] if ranked else None
    fam, guessed = detect_family(ckpt, families) if ckpt else (None, True)
    ups = rank_upscalers(d["upscale_models"])
    ipa = all(c in oi for c in ("IPAdapterUnifiedLoader", "IPAdapterAdvanced"))
    d["recommended"] = {
        "checkpoint": ckpt, "family": fam, "family_guessed": guessed,
        "checkpoint_score": ranked[0][0] if ranked else None,
        "checkpoint_ranking": [n for _, n in ranked[:10]],
        "checkpoint_scores": [[sc, n] for sc, n in ranked[:10]],
        "upscale_model": ups[0][1] if ups else None,
        "upscale_model_scale": upscaler_scale(ups[0][1]) if ups else None,
        "rembg": rembg_recipe(oi),
        "ipadapter": ipa,
        "face_detailer": "FaceDetailer" in oi,
    }
    return d


# ------------------------------------------------------------------ HTTP client
def _auth_header(value):
    if not value:
        return None
    v = value.strip()
    if re.match(r"^(basic|bearer|token|digest)\s", v, re.I):
        return v
    if ":" in v:
        return "Basic " + base64.b64encode(v.encode()).decode()
    return "Bearer " + v


def _ssl_context():
    ctx = ssl.create_default_context()
    for var in ("COMFYUI_CA_BUNDLE", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE"):
        p = os.environ.get(var)
        if p and os.path.isfile(p):
            try:
                ctx.load_verify_locations(cafile=p)
            except (ssl.SSLError, OSError):
                pass
            break
    return ctx


def url_warnings(url):
    """This environment's egress proxy only passes HTTPS on port 443 (see /root/.ccr/README.md), so
    an http:// URL or a custom port fails with an opaque connection error. Warn up front."""
    if not url:
        return []
    out = []
    u = urllib.parse.urlsplit(url)
    if u.scheme == "http" and u.hostname not in ("localhost", "127.0.0.1", "::1"):
        out.append("COMFYUI_URL is http://; the cloud environment's proxy only allows https:// "
                   "(use the tunnel's https address)")
    try:
        port = u.port
    except ValueError:
        port = None
    if port not in (None, 443) and u.hostname not in ("localhost", "127.0.0.1", "::1"):
        out.append("COMFYUI_URL uses port %d; tunnels serve ComfyUI on 443 (drop ':%d' -- the tunnel "
                   "forwards to 8188 on your PC)" % (port, port))
    return out


def content_problems(graph, adult=False):
    """Content-rule violations of a graph's prompts (prompts.check_graph); fails closed.
    adult=True checks against content_rules_adult (the EroLabs nude set, --adult)."""
    if not any("TextEncode" in str(n.get("class_type", "")) for n in graph.values()):
        return []
    try:
        import prompts
        return prompts.check_graph(prompts.load_bible(), graph, adult=adult)
    except Exception as e:  # noqa: BLE001  -- no rules, no sending
        return ["cannot load the content rules from data/art_prompts.json (%s)" % e]


def encode_multipart(fields, files):
    """fields: {name: str}; files: {name: (filename, bytes, content_type)} -> (body, content_type)."""
    boundary = "----halohorn" + uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    for k, (fname, data, ctype) in files.items():
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
                      "Content-Type: %s\r\n\r\n" % (boundary, k, fname, ctype)).encode() + data + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode())
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def format_prompt_error(payload):
    """Readable text from a POST /prompt 400 body ({"error": {...}, "node_errors": {...}})."""
    if not isinstance(payload, dict):
        return str(payload)[:2000]
    lines = []
    e = payload.get("error")
    if isinstance(e, dict):
        lines.append(("%s: %s %s" % (e.get("type", "error"), e.get("message", ""), e.get("details", ""))).strip())
    elif e:
        lines.append(str(e))
    for nid, ne in (payload.get("node_errors") or {}).items():
        for err in ne.get("errors", []):
            lines.append("  node %s (%s): %s %s %s" % (nid, ne.get("class_type", "?"), err.get("message", ""),
                                                       err.get("details", ""),
                                                       json.dumps(err.get("extra_info", {}))[:300]))
    return "\n".join(lines) or json.dumps(payload)[:2000]


def history_error(entry):
    """Error text from a /history entry whose status is error, else None."""
    st = (entry or {}).get("status") or {}
    if st.get("status_str") != "error":
        return None
    msgs = []
    for m in st.get("messages", []):
        if isinstance(m, list) and len(m) == 2 and m[0] in ("execution_error", "execution_interrupted"):
            d = m[1] or {}
            msgs.append("%s at node %s (%s): %s: %s" % (m[0], d.get("node_id"), d.get("node_type"),
                                                       d.get("exception_type", ""), d.get("exception_message", "")))
    return "; ".join(msgs) or "execution failed (no message)"


def history_images(entry):
    """[{"filename", "subfolder", "type", "node_id"}] from a /history entry, in node order."""
    out = []
    outputs = (entry or {}).get("outputs") or {}
    for nid in sorted(outputs, key=lambda k: (len(k), k)):
        for im in outputs[nid].get("images", []) or []:
            if im.get("type", "output") in ("output", "temp"):
                out.append(dict(im, node_id=nid))
    return out


class Comfy:
    """Thin client. Methods raise ComfyError with a readable message on failure."""

    def __init__(self, url=None, auth=None, dry_run=False, timeout=60, verbose=True):
        self.url = (url or os.environ.get("COMFYUI_URL") or "").rstrip("/")
        self._auth = _auth_header(auth if auth is not None else os.environ.get("COMFYUI_AUTH"))
        self.dry_run = dry_run
        self.timeout = timeout
        self.verbose = verbose
        self.client_id = "halohorn-" + uuid.uuid4().hex[:12]
        self.object_info_cache = None
        self.schema = None
        self._extra = {}
        if os.environ.get("COMFYUI_HEADERS"):
            try:
                self._extra = dict(json.loads(os.environ["COMFYUI_HEADERS"]))
            except ValueError:
                raise ComfyError("COMFYUI_HEADERS must be a JSON object")
        if not self.dry_run and not self.url:
            raise ComfyError("COMFYUI_URL is not set (export COMFYUI_URL=https://your-tunnel...), "
                             "or use --dry-run")
        if self.url and not re.match(r"^https?://", self.url):
            raise ComfyError("COMFYUI_URL must start with http:// or https:// (got %r)" % self.url)
        for w in url_warnings(self.url):
            self.log("warning: " + w)
        self._ctx = _ssl_context()

    def log(self, *a):
        if self.verbose:
            print(*a, flush=True)

    # -------------------------------------------------------------- raw HTTP
    def _headers(self, extra=None):
        h = {"User-Agent": "halo-horn-art/1.0", "Accept": "application/json, */*",
             "ngrok-skip-browser-warning": "1"}
        h.update(self._extra)
        if self._auth:
            h["Authorization"] = self._auth
        h.update(extra or {})
        return h

    def request(self, method, path, body=None, headers=None, raw=False, retries=3, timeout=None):
        if self.dry_run:
            raise ComfyError("dry run: no network access (%s %s)" % (method, path))
        url = self.url + path
        last = None
        for attempt in range(retries):
            req = urllib.request.Request(url, data=body, method=method, headers=self._headers(headers))
            try:
                with urllib.request.urlopen(req, timeout=timeout or self.timeout, context=self._ctx) as r:
                    data = r.read()
                    ctype = r.headers.get("Content-Type", "")
                if raw:
                    return data
                if "html" in ctype and not data.strip().startswith(b"{"):
                    raise ComfyError("%s %s returned HTML, not JSON: the tunnel may be showing a login or "
                                     "warning page (check COMFYUI_AUTH / COMFYUI_HEADERS)" % (method, path))
                return json.loads(data.decode("utf-8")) if data else None
            except urllib.error.HTTPError as e:
                text = e.read().decode("utf-8", "replace")
                if e.code in (401, 403):
                    raise ComfyError("%s %s: HTTP %d unauthorized. Set COMFYUI_AUTH (e.g. 'Basic <b64>' or "
                                     "'user:pass') or COMFYUI_HEADERS for the tunnel. If the 403 comes from a "
                                     "local egress proxy, the tunnel host is not allowed from this machine."
                                     % (method, path, e.code))
                if e.code == 400 and path.startswith("/prompt"):
                    try:
                        payload = json.loads(text)
                    except ValueError:
                        payload = text
                    raise ComfyError("server rejected the workflow:\n" + format_prompt_error(payload))
                if e.code in (502, 503, 504) and attempt + 1 < retries:
                    last = "HTTP %d" % e.code
                    time.sleep(2 * (attempt + 1))
                    continue
                raise ComfyError("%s %s: HTTP %d: %s" % (method, path, e.code, text[:500]))
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
                last = getattr(e, "reason", e)
                if attempt + 1 < retries:
                    time.sleep(2 * (attempt + 1))
                    continue
        raise ComfyError("cannot reach ComfyUI at %s (%s). Is the server running and the tunnel up?"
                         % (self.url, last))

    def get_json(self, path, **kw):
        return self.request("GET", path, **kw)

    # -------------------------------------------------------------- server info
    def system_stats(self):
        return self.get_json("/system_stats")

    def object_info(self, refresh=False):
        if self.object_info_cache is None or refresh:
            self.object_info_cache = self.get_json("/object_info", timeout=max(self.timeout, 120))
            self.schema = core_nodes.schema_from_object_info(self.object_info_cache)
        return self.object_info_cache

    def discover(self, families=None, save=True):
        """Query the server and return the discovery summary (see parse_object_info). Also lists
        /models/<folder> when the server supports it, as a cross-check. Cached under art_src/_server/."""
        stats = {}
        try:
            stats = self.system_stats() or {}
        except ComfyError as e:
            self.log("warning: /system_stats failed: %s" % e)
        oi = self.object_info(refresh=True)
        arch = {}
        for _, name in rank_checkpoints(combo_options(oi, "CheckpointLoaderSimple", "ckpt_name"))[:6]:
            try:      # safetensors header: modelspec.architecture / ss_base_model_version (often absent)
                meta = self.get_json("/view_metadata/checkpoints?filename=" + urllib.parse.quote(name), retries=1)
                a = checkpoint_arch(meta)
                if a:
                    arch[name] = a
            except (ComfyError, ValueError):
                pass
        d = parse_object_info(oi, families, arch)
        try:
            folders = self.get_json("/models", retries=1)
            d["model_folders"] = folders
            for folder, key in (("checkpoints", "checkpoints"), ("loras", "loras"), ("upscale_models", "upscale_models")):
                if isinstance(folders, list) and folder in folders and not d[key]:
                    d[key] = self.get_json("/models/" + folder, retries=1) or []
        except ComfyError:
            d["model_folders"] = None
        d["system"] = {"comfyui_version": (stats.get("system") or {}).get("comfyui_version"),
                       "python": (stats.get("system") or {}).get("python_version"),
                       "devices": [{"name": dv.get("name"), "vram_total": dv.get("vram_total"),
                                    "vram_free": dv.get("vram_free")} for dv in stats.get("devices", [])]}
        d["server"] = self.url
        d["discovered_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        if save:
            os.makedirs(server_dir(), exist_ok=True)
            with open(os.path.join(server_dir(), "discovery.json"), "w") as f:
                json.dump(d, f, indent=1)
            with open(os.path.join(server_dir(), "object_info.json"), "w") as f:
                json.dump(oi, f)
        return d

    # -------------------------------------------------------------- jobs
    def upload_image(self, path, name=None, subfolder="halo_horn", overwrite=True):
        """Upload a local image to the server's input folder. Returns the value to put in
        LoadImage/LoadImageMask "image" ("subfolder/name")."""
        name = name or os.path.basename(path)
        ref = "%s/%s" % (subfolder, name) if subfolder else name
        if self.dry_run:
            self.log("[dry-run] would upload %s as %s" % (path, ref))
            return ref
        with open(path, "rb") as f:
            data = f.read()
        ctype = mimetypes.guess_type(name)[0] or "image/png"
        body, ct = encode_multipart({"type": "input", "subfolder": subfolder or "",
                                     "overwrite": "true" if overwrite else "false"},
                                    {"image": (name, data, ctype)})
        res = self.request("POST", "/upload/image", body=body, headers={"Content-Type": ct}, timeout=300)
        sub = (res or {}).get("subfolder") or ""
        return "%s/%s" % (sub, res["name"]) if sub else res["name"]

    def validate(self, graph):
        """Errors for this graph against the live server schema (if loaded) or the core schema."""
        if self.schema is not None:
            return core_nodes.validate_graph(graph, self.schema)
        return core_nodes.validate_graph(graph)

    def queue(self, graph, label="job"):
        """POST /prompt. Returns the prompt id. In dry-run, writes art_src/_dryrun/<label>.json.
        Refuses graphs whose prompts break the content rules, and (live) dry-run placeholders.
        self.adult (set by pipeline.make_client from --adult) checks against content_rules_adult."""
        problems = content_problems(graph, adult=getattr(self, "adult", False))
        if problems:
            raise ComfyError("refusing to queue %s: its prompts break the content rules "
                             "(docs/dev/art-generation.md section 1):\n  %s" % (label, "\n  ".join(problems)))
        if not self.dry_run and "DRYRUN_PLACEHOLDER" in json.dumps(graph):
            raise ComfyError("%s is a dry-run graph (placeholder checkpoint, images never uploaded); re-run the "
                             "pipeline step without --dry-run instead of re-queueing it" % label)
        errs = self.validate(graph)
        if errs:
            raise ComfyError("workflow failed validation (%s):\n  %s" % (label, "\n  ".join(errs)))
        body = {"prompt": graph, "client_id": self.client_id}
        if self.dry_run:
            path = os.path.join(dryrun_dir(), label + ".json")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                json.dump(body, f, indent=1)
            self.log("[dry-run] wrote %s" % rel(path))
            self.last_dryrun_path = path
            return "dryrun:" + label
        res = self.request("POST", "/prompt", body=json.dumps(body).encode(),
                           headers={"Content-Type": "application/json"}, retries=1)
        if not isinstance(res, dict):
            raise ComfyError("POST /prompt returned %r instead of a prompt id (is COMFYUI_URL a ComfyUI "
                             "server, not a proxy or login page?)" % (res if res is None else str(res)[:200]))
        if res.get("node_errors"):
            raise ComfyError("server reported node errors:\n" + format_prompt_error(res))
        if not res.get("prompt_id"):
            raise ComfyError("POST /prompt answered without a prompt_id: %s" % json.dumps(res)[:300])
        return res["prompt_id"]

    def _queue_state(self, prompt_id):
        q = self.get_json("/queue", retries=2) or {}
        for key, state in (("queue_running", "running"), ("queue_pending", "pending")):
            for item in q.get(key, []):
                if len(item) > 1 and item[1] == prompt_id:
                    return state
        return None

    def wait(self, prompt_id, timeout=900, pending_timeout=7200, poll=1.5):
        """Poll /history/<id> until the job finishes. `timeout` counts only while the job is running;
        `pending_timeout` limits time spent waiting in the queue. Returns the history entry."""
        if self.dry_run or str(prompt_id).startswith("dryrun:"):
            return {"status": {"status_str": "dry-run", "completed": True}, "outputs": {}}
        t0 = time.time()
        run_t0 = None
        last_note = 0
        missing = 0
        while True:
            h = self.get_json("/history/" + urllib.parse.quote(prompt_id), retries=3) or {}
            entry = h.get(prompt_id)
            if entry:
                err = history_error(entry)
                if err:
                    raise ComfyError("job %s failed: %s" % (prompt_id, err))
                st = entry.get("status") or {}
                if st.get("completed", True) or entry.get("outputs"):
                    return entry
            state = self._queue_state(prompt_id)
            now = time.time()
            if state == "running" and run_t0 is None:
                run_t0 = now
            if state is None and not entry:
                missing += 1
                if missing > 20:
                    raise ComfyError("job %s is neither queued nor in history (server restarted?)" % prompt_id)
            else:
                missing = 0
            if run_t0 is not None and now - run_t0 > timeout:
                raise ComfyError("job %s still running after %ds (timeout). It keeps running on the server; "
                                 "raise --timeout or check the ComfyUI console." % (prompt_id, timeout))
            if run_t0 is None and now - t0 > pending_timeout:
                raise ComfyError("job %s waited %ds in the queue without starting" % (prompt_id, pending_timeout))
            if now - last_note > 15:
                self.log("  ... %s %s (%ds)" % (prompt_id[:8], state or "finishing", int(now - t0)))
                last_note = now
            time.sleep(poll)

    def download(self, image, dest_path):
        """Fetch one output image (a dict from history_images) via /view to dest_path."""
        q = urllib.parse.urlencode({"filename": image["filename"], "subfolder": image.get("subfolder", ""),
                                    "type": image.get("type", "output")})
        data = self.request("GET", "/view?" + q, raw=True, timeout=300)
        os.makedirs(os.path.dirname(os.path.abspath(dest_path)), exist_ok=True)
        with open(dest_path, "wb") as f:
            f.write(data)
        return dest_path

    def run(self, graph, label, dest_dir, timeout=900, names=None):
        """queue + wait + download every saved image. Returns local paths ([] in dry-run)."""
        pid = self.queue(graph, label)
        entry = self.wait(pid, timeout=timeout)
        images = history_images(entry)
        if not images and not self.dry_run:
            raise ComfyError("job %s (%s) finished without saving an image" % (pid, label))
        paths = []
        for i, im in enumerate(images):
            name = names[i] if names and i < len(names) else "%s_%d.png" % (os.path.basename(label), i)
            paths.append(self.download(im, os.path.join(dest_dir, name)))
        return paths


# Module-level conveniences (use COMFYUI_URL / COMFYUI_AUTH).
def discover(dry_run=False):
    return Comfy(dry_run=dry_run).discover()


def upload_image(path, **kw):
    return Comfy().upload_image(path, **kw)


def queue(prompt_json, label="job", dry_run=False):
    return Comfy(dry_run=dry_run).queue(prompt_json, label)


def pin_path():
    return os.path.join(server_dir(), "pin.json")


def load_pin():
    """{"checkpoint", "family"} pinned with `comfy.py pin`, or None."""
    p = pin_path()
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def load_cached_discovery():
    """(discovery, object_info) from art_src/_server/, or (None, None)."""
    p = os.path.join(server_dir(), "discovery.json")
    if not os.path.exists(p):
        return None, None
    with open(p) as f:
        d = json.load(f)
    oi = None
    po = os.path.join(server_dir(), "object_info.json")
    if os.path.exists(po):
        with open(po) as f:
            oi = json.load(f)
    return d, oi


# ------------------------------------------------------------------ CLI
def _print_discovery(d):
    r = d["recommended"]
    print("ComfyUI %s at %s" % ((d.get("system") or {}).get("comfyui_version") or "?", d.get("server") or "(file)"))
    for dv in (d.get("system") or {}).get("devices", []):
        print("  device: %s  VRAM %.1f GB" % (dv["name"], (dv.get("vram_total") or 0) / 2 ** 30))
    print("nodes: %d   missing core nodes: %s" % (d["node_count"], ", ".join(d["missing_core"]) or "none"))
    for k in ("checkpoints", "loras", "upscale_models", "controlnets", "vaes"):
        v = d.get(k) or []
        print("%-15s %d  %s" % (k + ":", len(v), ", ".join(v[:8]) + (" ..." if len(v) > 8 else "")))
    for k, v in d["custom"].items():
        print("%-25s %s" % ("custom/" + k + ":", ", ".join(v) or "-"))
    print("recommended checkpoint: %s  (family %s%s, score %s)" % (
        r["checkpoint"], r["family"], ", guessed from name" if r["family_guessed"] else "", r.get("checkpoint_score")))
    if (r.get("checkpoint_score") or 0) < 5 and r.get("checkpoint"):
        print("  WARNING: not recognisably an anime SDXL checkpoint; the pipeline will stop until you pass "
              "--ckpt NAME (or export COMFYUI_CKPT). Architectures seen: %s" % (d.get("checkpoint_arch") or "none"))
    print("recommended upscaler:   %s" % r["upscale_model"])
    print("background removal:     %s" % ((r["rembg"] or {}).get("class") or "none (local flood fill)"))
    print("IPAdapter:              %s" % ("yes" if r["ipadapter"] else "no"))


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ping")
    dp = sub.add_parser("discover")
    dp.add_argument("--object-info", help="parse a saved /object_info JSON file instead of the server")
    dp.add_argument("--json", action="store_true", help="print the full discovery JSON")
    pp = sub.add_parser("pin", help="pin the checkpoint (and family) for every later command")
    pp.add_argument("checkpoint", help="file name as listed by discover; 'none' removes the pin")
    pp.add_argument("--family", help="family from data/art_prompts.json (default: detected from the name)")
    pp.add_argument("--fallback", help="a second checkpoint the tools use with --fallback (or --family of its "
                                       "family), e.g. amanatsuIllustrious_v2.safetensors behind MOSS")
    pp.add_argument("--fallback-family", help="the fallback's family (default: detected from its name)")
    qp = sub.add_parser("queue")
    qp.add_argument("graph", help="API graph JSON (either the graph itself or a {prompt: ...} body)")
    qp.add_argument("--out", default=None, help="download folder (default art_src/_downloads)")
    qp.add_argument("--dry-run", action="store_true")
    qp.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args(argv)
    try:
        families = None
        bp = os.path.join(ROOT, "data", "art_prompts.json")
        if os.path.exists(bp):
            families = json.load(open(bp)).get("families")
        if a.cmd == "ping":
            c = Comfy()
            s = c.system_stats()
            print(json.dumps(s, indent=1)[:3000])
        elif a.cmd == "discover":
            if a.object_info:
                d = parse_object_info(json.load(open(a.object_info)), families)
                d["server"] = None
            else:
                d = Comfy().discover(families=families)
            print(json.dumps(d, indent=1) if a.json else "", end="")
            _print_discovery(d)
            if not a.object_info:
                print("cached: %s" % rel(os.path.join(server_dir(), "discovery.json")))
        elif a.cmd == "pin":
            if a.checkpoint.lower() == "none":
                if os.path.exists(pin_path()):
                    os.remove(pin_path())
                print("pin removed")
                return 0
            disc, _ = load_cached_discovery()
            for name, fam_arg in ((a.checkpoint, a.family), (a.fallback, a.fallback_family)):
                if not name:
                    continue
                if fam_arg and families and fam_arg not in families:
                    raise ComfyError("unknown family %r (known: %s)" % (fam_arg, ", ".join(families)))
                fam_x = fam_arg or detect_family(name, families)[0]
                if (families or {}).get(fam_x, {}).get("arch") == "moss":
                    continue                # a diffusion_models file, checked by the tools against its loader
                if disc and disc.get("checkpoints") and name not in disc["checkpoints"]:
                    raise ComfyError("%r is not in the last discovery. Checkpoints: %s" % (name, ", ".join(disc["checkpoints"])))
            fam, guessed = (a.family, False) if a.family else detect_family(a.checkpoint, families)
            pin = {"checkpoint": a.checkpoint, "family": fam, "pinned": time.strftime("%Y-%m-%dT%H:%M:%S")}
            if a.fallback:
                pin["fallback"] = {"checkpoint": a.fallback,
                                   "family": a.fallback_family or detect_family(a.fallback, families)[0]}
            os.makedirs(server_dir(), exist_ok=True)
            with open(pin_path(), "w") as f:
                json.dump(pin, f, indent=1)
            print("pinned %s (family %s%s)%s in %s" % (
                a.checkpoint, fam, ", guessed from the name: pass --family if wrong" if guessed else "",
                "; fallback %s (%s)" % (a.fallback, pin["fallback"]["family"]) if a.fallback else "", rel(pin_path())))
        elif a.cmd == "queue":
            body = json.load(open(a.graph))
            graph = body.get("prompt", body)
            c = Comfy(dry_run=a.dry_run)
            if not a.dry_run:
                c.object_info()
            label = os.path.splitext(os.path.basename(a.graph))[0]
            if label.endswith(".api"):
                label = label[:-4]
            paths = c.run(graph, label, a.out or os.path.join(art_src(), "_downloads"), timeout=a.timeout)
            for p in paths:
                print(p)
    except ComfyError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
