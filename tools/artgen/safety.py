#!/usr/bin/env python3
"""Exposure filter for the art farm. Every image passes here BEFORE it may be uploaded (Actions
artifact) or committed (art-gen-output branch). The repo is public, so this FAILS CLOSED:

- two detectors, both required: NudeNet 3.4.2 (photo-trained, MIT, bundled 320n model) and the
  deepghs anime censor-point detector (YOLOv8 trained on anime art: nipple_f, penis, pussy);
- each detector looks at the whole image plus overlapping tiles at two scales (small details in
  a 768x1344 full-body render are a few pixels at the detectors' input size otherwise);
- the score per class is the RAW maximum over every anchor of every view (no NMS, no argmax),
  so a box that is "covered 0.6 / exposed 0.3" still counts as exposed 0.3;
- an image is dropped if any watched class reaches its threshold (config.FILTER), if a detector
  raises, or if the image cannot be read; a detector that cannot load stops the job before any
  rendering (FilterUnavailable);
- dropped images are deleted on the spot and never moved to the upload dir; only their name,
  scores and reason are logged (drop counts in the manifest and the job log);
- verify() runs again right before the upload: any image in the upload dir without a matching
  pass record (path + sha256) is deleted, and so is any file that is not .png/.webp/.json;
- localisation for the cover repair (gen.publish_screened): flag_boxes() returns, in image pixels, the
  boxes of the classes to cover from every view (same views as the check, anchors at >= half the class
  threshold, NMS per class); a scorer that cannot localise makes the repair impossible (the image is
  dropped as before). The repaired image goes through the full check again; thresholds never change;
- the self-test also runs a sensitivity canary (positive control, config.FILTER["canary"]): an
  already-public, filter-passed borderline candidate on the art-gen-output branch (loaded at run
  time: env ARTGEN_CANARY_FILE, else `git show origin/art-gen-output:<path>`, else the raw URL;
  never committed to the code branch) must still PASS and score inside fixed bands (nudenet
  FEMALE_BREAST_EXPOSED 0.10-0.25, anime detector max 0.02-0.25), so a detector that silently returns
  near-zero scores fails closed. If the canary cannot be fetched (or its sha256 differs) the canary
  alone is skipped with a warning line; the rest of the self-test still has to pass.

    safety.py selftest                 load both detectors, prove a clean image passes, a detector error drops
                                       and the canary scores inside its bands
    safety.py check IMG [IMG ...]      print scores and the verdict (no files are moved)
    safety.py verify DIR               enforce the manifest on an upload dir (deletes anything unverified)
"""
import hashlib
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import config as C  # noqa: E402

MANIFEST = "filter_manifest.json"


class FilterUnavailable(RuntimeError):
    """A detector could not be loaded: nothing may be published."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def flatten(img, grey=128):
    """RGB view of any image; transparent areas become flat grey (what a viewer would see)."""
    if img.mode in ("RGBA", "LA", "PA") or (img.mode == "P" and "transparency" in img.info):
        rgba = img.convert("RGBA")
        bg = Image.new("RGB", rgba.size, (grey, grey, grey))
        bg.paste(rgba, (0, 0), rgba)
        return bg
    return img.convert("RGB")


def views(img):
    """[(name, RGB image)]: the whole image + square tiles (side = short edge, then half of it),
    overlapping by half a tile, covering the whole image."""
    return [(n, v) for n, v, _xy in views_xy(img)]


def views_xy(img):
    """views() with each view's offset: [(name, RGB image, (x, y))]."""
    out = [("full", img, (0, 0))]
    w, h = img.size
    short = min(w, h)
    for frac in (1.0, 0.5):
        side = max(64, int(short * frac))
        if side >= max(w, h) and frac == 1.0:
            continue
        step = max(32, side // 2)
        xs = list(range(0, max(1, w - side + 1), step))
        ys = list(range(0, max(1, h - side + 1), step))
        if xs[-1] + side < w:
            xs.append(w - side)
        if ys[-1] + side < h:
            ys.append(h - side)
        for y in ys:
            for x in xs:
                out.append(("t%d_%d_%d" % (side, x, y), img.crop((x, y, x + side, y + side)), (x, y)))
    return out


def nms(boxes, scores, iou=0.5):
    """Indices kept by greedy non-maximum suppression (boxes: [n, 4] x0, y0, x1, y1)."""
    b = np.asarray(boxes, dtype=np.float64).reshape(-1, 4)
    order = np.asarray(scores, dtype=np.float64).argsort()[::-1]
    area = (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1])
    keep = []
    while order.size:
        i = order[0]
        keep.append(int(i))
        xx0 = np.maximum(b[i, 0], b[order[1:], 0])
        yy0 = np.maximum(b[i, 1], b[order[1:], 1])
        xx1 = np.minimum(b[i, 2], b[order[1:], 2])
        yy1 = np.minimum(b[i, 3], b[order[1:], 3])
        inter = np.clip(xx1 - xx0, 0, None) * np.clip(yy1 - yy0, 0, None)
        ov = inter / (area[i] + area[order[1:]] - inter + 1e-6)
        order = order[1:][ov <= iou]
    return keep


def _class_boxes(cxcywh, scores, labels, classes, conf, fx, fy, w, h):
    """[(x0, y0, x1, y1, class, score)] per class from raw anchors (centre boxes in model input px)."""
    out = []
    cx, cy, bw, bh = cxcywh
    for c in classes:
        sc = scores[labels.index(c)]
        keep = np.nonzero(sc >= conf)[0]
        if not keep.size:
            continue
        b = np.stack([(cx[keep] - bw[keep] / 2) * fx, (cy[keep] - bh[keep] / 2) * fy,
                      (cx[keep] + bw[keep] / 2) * fx, (cy[keep] + bh[keep] / 2) * fy], 1)
        b[:, [0, 2]] = np.clip(b[:, [0, 2]], 0, w)
        b[:, [1, 3]] = np.clip(b[:, [1, 3]], 0, h)
        for i in nms(b, sc[keep]):
            out.append((float(b[i, 0]), float(b[i, 1]), float(b[i, 2]), float(b[i, 3]), c, float(sc[keep][i])))
    return out


# ------------------------------------------------------------------ detectors
class NudeNetScorer:
    """NudeNet 3.4.2 (pip nudenet, MIT). Uses the package's own preprocessing and ONNX session,
    but reads the raw per-class scores instead of its argmax+NMS output."""
    name = "nudenet"

    def __init__(self, threshold):
        import nudenet.nudenet as nn      # noqa: WPS433 (import here: fail closed when missing)
        self._nn = nn
        self._det = nn.NudeDetector()
        self.labels = list(getattr(nn, "__labels"))
        self.classes = list(C.FILTER["nudenet_classes"])
        self.threshold = float(threshold)
        missing = [c for c in self.classes if c not in self.labels]
        if missing:
            raise FilterUnavailable("NudeNet labels changed (missing %s)" % missing)

    def class_max(self, img):
        bgr = np.ascontiguousarray(np.asarray(img.convert("RGB"))[..., ::-1])   # what cv2.imread would give
        blob = self._nn._read_image(bgr, self._det.input_width)[0]
        out = self._det.onnx_session.run(None, {self._det.input_name: blob})
        rows = np.transpose(np.squeeze(out[0]))          # [anchors, 4 + classes]
        scores = rows[:, 4:].max(axis=0)
        return {lab: float(scores[i]) for i, lab in enumerate(self.labels)}

    def class_boxes(self, img, classes, conf):
        """Boxes in `img` pixels. NudeNet pads the image to a square at the bottom/right and resizes it to
        its input size, so model px x (long side / input size) = image px (as nudenet._postprocess)."""
        rgb = img.convert("RGB")
        bgr = np.ascontiguousarray(np.asarray(rgb)[..., ::-1])
        blob = self._nn._read_image(bgr, self._det.input_width)[0]
        out = self._det.onnx_session.run(None, {self._det.input_name: blob})
        rows = np.squeeze(out[0])                         # [4 + classes, anchors]
        f = max(rgb.size) / float(self._det.input_width)
        return _class_boxes(rows[:4], rows[4:], self.labels, classes, conf, f, f, rgb.width, rgb.height)


class YoloOnnx:
    """Minimal runner for deepghs YOLOv8 ONNX exports (same preprocessing as dghs-imgutils:
    stretch to the model's imgsz, RGB float CHW / 255). Returns raw per-class maxima, or boxes."""

    def __init__(self, repo, model, cache_dir=None):
        import ast
        import onnxruntime as ort
        from huggingface_hub import hf_hub_download
        path = hf_hub_download(repo_id=repo, filename="%s/model.onnx" % model, cache_dir=cache_dir)
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = max(1, (os.cpu_count() or 2))
        self.session = ort.InferenceSession(path, sess_options=opts, providers=["CPUExecutionProvider"])
        meta = self.session.get_modelmeta().custom_metadata_map
        imgsz = json.loads(meta["imgsz"]) if "imgsz" in meta else [640, 640]
        self.size = (int(imgsz[1]), int(imgsz[0])) if len(imgsz) == 2 else (640, 640)   # (w, h)
        names = ast.literal_eval(meta["names"])
        self.labels = [names[i] for i in range(len(names))]
        self.input_name = self.session.get_inputs()[0].name
        self.repo, self.model = repo, model

    def raw(self, img):
        im = img.convert("RGB").resize(self.size, Image.BILINEAR)
        x = (np.asarray(im).astype(np.float32) / 255.0).transpose(2, 0, 1)[None]
        out = self.session.run(None, {self.input_name: x})[0][0]
        if out.shape[0] != 4 + len(self.labels):
            raise RuntimeError("unexpected YOLO output shape %s" % (out.shape,))
        return out                                          # [4 + classes, anchors]

    def class_max(self, img):
        scores = self.raw(img)[4:].max(axis=1)
        return {lab: float(scores[i]) for i, lab in enumerate(self.labels)}

    def class_boxes(self, img, classes, conf):
        """Boxes of the given classes in `img` pixels (input is stretched, so x and y scale separately)."""
        out = self.raw(img)
        return _class_boxes(out[:4], out[4:], self.labels, classes, conf, img.width / self.size[0],
                            img.height / self.size[1], img.width, img.height)

    def boxes(self, img, conf=0.3, iou=0.5):
        """[(x0, y0, x1, y1, label, score)] in image pixels, after NMS."""
        out = self.raw(img)
        sc = out[4:]
        best = sc.max(axis=0)
        keep = best >= conf
        if not keep.any():
            return []
        cx, cy, bw, bh = out[0][keep], out[1][keep], out[2][keep], out[3][keep]
        cls = sc[:, keep].argmax(axis=0)
        s = best[keep]
        fx, fy = img.width / self.size[0], img.height / self.size[1]
        b = np.stack([(cx - bw / 2) * fx, (cy - bh / 2) * fy, (cx + bw / 2) * fx, (cy + bh / 2) * fy], 1)
        return [(float(b[i, 0]), float(b[i, 1]), float(b[i, 2]), float(b[i, 3]), self.labels[cls[i]], float(s[i]))
                for i in nms(b, s, iou)]


class AnimeCensorScorer:
    name = "anime_censor"

    def __init__(self, threshold, cache_dir=None):
        a = C.AUX["anime_censor"]
        self._yolo = YoloOnnx(a["repo"], a["model"], cache_dir)
        self.labels = self._yolo.labels
        self.classes = list(C.FILTER["anime_classes"])
        self.threshold = float(threshold)
        missing = [c for c in self.classes if c not in self.labels]
        if missing:
            raise FilterUnavailable("anime censor detector labels changed (missing %s; has %s)" % (missing, self.labels))

    def class_max(self, img):
        return self._yolo.class_max(img)

    def class_boxes(self, img, classes, conf):
        return self._yolo.class_boxes(img, classes, conf)


def load_default_scorers(nudenet_threshold=None, anime_threshold=None, cache_dir=None):
    nt = C.FILTER["nudenet_threshold"] if nudenet_threshold is None else float(nudenet_threshold)
    at = C.FILTER["anime_threshold"] if anime_threshold is None else float(anime_threshold)
    try:
        return [NudeNetScorer(nt), AnimeCensorScorer(at, cache_dir)]
    except FilterUnavailable:
        raise
    except Exception as e:      # missing package, model download failure, bad model file...
        raise FilterUnavailable("exposure detector unavailable: %s: %s" % (type(e).__name__, e))


# ------------------------------------------------------------------ canary
def fetch_canary(spec=None, log=print, repo=None, timeout=30):
    """(local path, None) of the canary image, verified against its sha256, or (None, reason).
    Sources in order: env ARTGEN_CANARY_FILE; `git show <ref>:<path>` in this checkout (ref
    origin/art-gen-output, present after `git fetch origin art-gen-output`); the raw URL of the public
    branch. The image is cached in the temp dir under its sha256."""
    import subprocess
    import tempfile
    spec = spec or C.FILTER["canary"]
    want = spec["sha256"]
    cache = os.path.join(tempfile.gettempdir(), "artgen_canary_%s.webp" % want[:16])
    if os.path.isfile(cache) and sha256_file(cache) == want:
        return cache, None
    tried = []

    def keep(data, src):
        if hashlib.sha256(data).hexdigest() != want:
            tried.append("%s: sha256 mismatch" % src)
            return None
        tmp = cache + ".%d.tmp" % os.getpid()
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, cache)
        log("filter canary loaded from %s" % src)
        return cache

    env = os.environ.get("ARTGEN_CANARY_FILE")
    if env:
        try:
            with open(env, "rb") as f:
                got = keep(f.read(), env)
            if got:
                return got, None
        except OSError as e:
            tried.append("%s: %s" % (env, e))
    try:
        r = subprocess.run(["git", "show", "%s:%s" % (spec["ref"], spec["path"])], cwd=C.ROOT, capture_output=True,
                           timeout=timeout)
        if r.returncode == 0 and r.stdout:
            got = keep(r.stdout, "git %s" % spec["ref"])
            if got:
                return got, None
        else:
            tried.append("git %s: not available" % spec["ref"])
    except (OSError, subprocess.SubprocessError) as e:
        tried.append("git: %s" % e)
    repo = repo or os.environ.get("GITHUB_REPOSITORY") or spec["repo"]
    url = "https://raw.githubusercontent.com/%s/%s/%s" % (repo, spec["branch"], spec["path"])
    try:
        import urllib.request
        for i in range(2):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "art-farm"})
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    got = keep(resp.read(8 << 20), url)
                if got:
                    return got, None
                break
            except OSError as e:
                if i:
                    raise
                time.sleep(3)
    except Exception as e:      # noqa: BLE001
        tried.append("%s: %s" % (url, e))
    return None, "; ".join(tried) or "no source"


# ------------------------------------------------------------------ filter
class ExposureFilter:
    def __init__(self, scorers=None, log=print, cache_dir=None):
        self.log = log
        self.default = scorers is None          # the real detectors: the self-test includes the canary
        self.scorers = scorers if scorers is not None else load_default_scorers(cache_dir=cache_dir)
        if not self.scorers:
            raise FilterUnavailable("no detectors")
        for s in self.scorers:
            if not (0.0 < s.threshold <= C.FILTER["max_threshold"]):
                raise FilterUnavailable("%s threshold %.2f outside (0, %.2f]" % (s.name, s.threshold,
                                                                                C.FILTER["max_threshold"]))
        self.stats = {"checked": 0, "passed": 0, "dropped": 0, "errors": 0, "repaired": 0}

    def describe(self):
        return {s.name: {"threshold": s.threshold, "classes": s.classes} for s in self.scorers}

    def check_image(self, img):
        """(ok, report). Raises on detector errors (callers turn that into a drop)."""
        rgb = flatten(img)
        vs = views(rgb)
        report = {"views": len(vs), "scores": {}, "flagged": []}
        for s in self.scorers:
            best = {c: 0.0 for c in s.classes}
            where = {}
            for vname, v in vs:
                cm = s.class_max(v)
                for c in s.classes:
                    val = float(cm[c])
                    if not np.isfinite(val):
                        raise RuntimeError("%s returned a non-finite score" % s.name)
                    if val > best[c]:
                        best[c], where[c] = val, vname
            report["scores"][s.name] = {c: round(v, 4) for c, v in best.items()}
            for c, v in best.items():
                if v >= s.threshold:
                    report["flagged"].append({"detector": s.name, "class": c, "score": round(v, 4), "view": where[c]})
        return (not report["flagged"]), report

    def cover_classes(self, report, near_frac):
        """{detector: [classes]} to cover after a flagged check: every flagged class plus the classes
        scoring >= near_frac x their threshold (they would flag after a small change)."""
        want = {}
        for f in report.get("flagged") or []:
            want.setdefault(f["detector"], []).append(f["class"])
        for s in self.scorers:
            for c, v in ((report.get("scores") or {}).get(s.name) or {}).items():
                if v >= near_frac * s.threshold and c not in want.get(s.name, []):
                    want.setdefault(s.name, []).append(c)
        return want

    def flag_boxes(self, img, classes, frac):
        """[{detector, class, score, view, box: [x0, y0, x1, y1]}] in `img` pixels for the given
        {detector: [classes]}: anchors scoring >= frac x the class threshold in every view of the check.
        Raises when a needed detector cannot localise (no class_boxes)."""
        rgb = flatten(img)
        found = []
        for s in self.scorers:
            want = [c for c in classes.get(s.name, []) if c in s.classes]
            if not want:
                continue
            if not hasattr(s, "class_boxes"):
                raise RuntimeError("%s cannot localise its detections" % s.name)
            conf = max(0.05, frac * s.threshold)
            for vname, v, (ox, oy) in views_xy(rgb):
                for x0, y0, x1, y1, c, sc in s.class_boxes(v, want, conf):
                    if not all(np.isfinite([x0, y0, x1, y1, sc])):
                        raise RuntimeError("%s returned a non-finite box" % s.name)
                    found.append({"detector": s.name, "class": c, "score": round(float(sc), 4), "view": vname,
                                  "box": [round(x0 + ox, 1), round(y0 + oy, 1), round(x1 + ox, 1), round(y1 + oy, 1)]})
        return found

    def check_file(self, path):
        """(ok, report); never raises: any error is a drop (fail closed)."""
        self.stats["checked"] += 1
        try:
            with Image.open(path) as im:
                im.load()
                ok, rep = self.check_image(im)
        except Exception as e:     # noqa: BLE001 - fail closed on anything
            self.stats["errors"] += 1
            self.stats["dropped"] += 1
            return False, {"error": "%s: %s" % (type(e).__name__, e)}
        self.stats["passed" if ok else "dropped"] += 1
        return ok, rep

    def canary(self, spec=None, path=None):
        """Positive control: the canary image must pass and score inside its bands (FilterUnavailable
        otherwise). Returns the report, or None when the canary could not be loaded (logged, skipped)."""
        spec = spec or C.FILTER["canary"]
        if path is None:
            path, why = fetch_canary(spec, log=self.log)
        else:
            why = None if sha256_file(path) == spec["sha256"] else "sha256 mismatch"
        if path is None or why:
            self.log("::warning::exposure filter canary SKIPPED (%s): the self-test ran without its positive "
                     "control" % (why or "not available"))
            return None
        saved = dict(self.stats)
        try:
            ok, rep = self.check_file(path)
        finally:
            self.stats = saved
        if not ok:
            raise FilterUnavailable("canary did not pass: %s" % json.dumps(rep.get("flagged") or rep.get("error")))
        for det, bands in spec["bands"].items():
            sc = rep["scores"].get(det)
            if not sc:
                raise FilterUnavailable("canary: no scores from detector %s" % det)
            for cls, (lo, hi) in bands.items():
                v = max(sc.values()) if cls == "_max" else sc.get(cls)
                if v is None or not lo <= v <= hi:
                    raise FilterUnavailable("canary: %s %s = %s outside [%.2f, %.2f] (detector sensitivity changed)"
                                            % (det, cls, v, lo, hi))
        return rep

    def selftest(self, canary=None):
        """Prove the detectors run, that a detector error drops the image and (real detectors, or
        canary=True) that the canary scores inside its bands. Raises FilterUnavailable."""
        import tempfile

        class _Broken:
            name, classes, threshold = "broken", ["x"], 0.25

            def class_max(self, img):
                raise RuntimeError("forced detector error (self-test)")

        d = tempfile.mkdtemp(prefix="artgen_selftest_")
        try:
            p = os.path.join(d, "grey.png")
            Image.new("RGB", (512, 896), (128, 128, 128)).save(p)
            saved = dict(self.stats)
            ok, rep = self.check_file(p)
            if not ok:
                raise FilterUnavailable("self-test: a flat grey image did not pass: %s" % rep)
            broken = ExposureFilter([_Broken()], log=self.log)
            ok2, rep2 = broken.check_file(p)
            if ok2 or "error" not in rep2:
                raise FilterUnavailable("self-test: a detector error did not drop the image")
            self.stats = saved
            run_canary = self.default if canary is None else canary
            crep = self.canary() if run_canary else None
            self.log("filter self-test ok: %s; forced detector error -> dropped (%s); canary %s"
                     % (json.dumps(rep["scores"]), rep2["error"],
                        json.dumps(crep["scores"]) if crep else "skipped" if run_canary else "not run (test detectors)"))
            rep["canary"] = crep["scores"] if crep else ("skipped" if run_canary else None)
            return rep
        finally:
            shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------------ publishing
def _is_image_name(name):
    return name.lower().endswith(C.IMAGE_EXTS)


class Publisher:
    """Moves files that pass the filter into the upload dir and records them in the manifest.
    Only .png/.webp images (filtered) and .json text are ever written there."""

    def __init__(self, filt, out_dir, log=print, job=None):
        self.filt, self.out, self.log = filt, out_dir, log
        os.makedirs(out_dir, exist_ok=True)
        self.manifest = {"job": job or {}, "filter": filt.describe(), "files": {}, "dropped": [],
                         "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        self.last_report = None
        self._save()

    def _dest(self, rel):
        rel = rel.replace("\\", "/").lstrip("/")
        if ".." in rel.split("/"):
            raise ValueError("bad relative path %r" % rel)
        return rel, os.path.join(self.out, rel)

    def _save(self):
        self.manifest["stats"] = dict(self.filt.stats)
        tmp = os.path.join(self.out, MANIFEST + ".tmp")
        with open(tmp, "w") as f:
            json.dump(self.manifest, f, indent=1)
        os.replace(tmp, os.path.join(self.out, MANIFEST))

    def publish(self, src, rel, defer_drop=False, extra=None):
        """Check `src` (a finished file in a work dir); on pass move it to out/rel, else delete it.
        Returns the destination path or None; the check's report is in self.last_report. defer_drop: a
        failed check is not recorded yet (the caller repairs the image, then publishes the repaired file
        or calls record_drop). `extra` is merged into the pass record (e.g. the repair summary)."""
        rel, dest = self._dest(rel)
        if not rel.lower().endswith(C.UPLOAD_IMAGE_EXTS):
            os.remove(src)
            raise ValueError("only %s images are published, not %r" % (C.UPLOAD_IMAGE_EXTS, rel))
        ok, rep = self.filt.check_file(src)
        self.last_report = rep
        if not ok:
            try:
                os.remove(src)
            finally:
                if not defer_drop:
                    self.manifest["dropped"].append({"rel": rel, "report": rep})
                self._save()
            self.log("FILTER %s %s: %s" % ("FLAGGED" if defer_drop else "DROPPED", rel,
                                           json.dumps(rep.get("flagged") or rep.get("error"))))
            return None
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(src, dest)
        rec = {"sha256": sha256_file(dest), "passed": True, "scores": rep["scores"], "views": rep["views"]}
        if extra:
            rec.update({k: v for k, v in extra.items() if k not in rec})
        self.manifest["files"][rel] = rec
        self._save()
        return dest

    def count_repaired(self):
        self.filt.stats["repaired"] = self.filt.stats.get("repaired", 0) + 1
        self._save()

    def record_drop(self, rel, report):
        """Record a drop decided by the caller (after a deferred check and a failed repair)."""
        rel, _dest = self._dest(rel)
        self.manifest["dropped"].append({"rel": rel, "report": report})
        self._save()
        self.log("FILTER DROPPED %s: %s" % (rel, json.dumps(report.get("flagged") or report.get("error"))))

    def write_json(self, rel, obj):
        rel, dest = self._dest(rel)
        if not rel.endswith(".json"):
            raise ValueError("text outputs must be .json")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w") as f:
            json.dump(obj, f, indent=1)
        return dest

    def summary(self):
        st = self.filt.stats
        return "filter: %d checked, %d passed, %d dropped (%d detector errors)" % (
            st["checked"], st["passed"], st["dropped"], st["errors"])


def verify(out_dir, log=print):
    """Last gate before an upload or commit: keep only .png/.webp files whose path and sha256 have a
    pass record in the manifest, and .json files that parse. Everything else is deleted.
    Returns {"kept", "deleted", "reasons"}."""
    res = {"kept": 0, "deleted": 0, "reasons": []}
    mpath = os.path.join(out_dir, MANIFEST)
    try:
        with open(mpath) as f:
            files = json.load(f).get("files", {})
    except (OSError, ValueError):
        files = {}
        res["reasons"].append("no readable manifest: every image is deleted")

    def drop(p, why):
        os.remove(p)
        res["deleted"] += 1
        res["reasons"].append("%s: %s" % (os.path.relpath(p, out_dir), why))

    for dirpath, dirnames, filenames in os.walk(out_dir):
        for d in list(dirnames):
            if os.path.islink(os.path.join(dirpath, d)):
                os.remove(os.path.join(dirpath, d))
                dirnames.remove(d)
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, out_dir).replace(os.sep, "/")
            low = fn.lower()
            if os.path.islink(p):
                drop(p, "symlink")
            elif low.endswith(C.UPLOAD_IMAGE_EXTS):
                rec = files.get(rel)
                if not rec or not rec.get("passed"):
                    drop(p, "image without a filter pass record")
                elif rec.get("sha256") != sha256_file(p):
                    drop(p, "image changed after the filter")
                else:
                    try:
                        with Image.open(p) as im:
                            fmt = im.format
                        if fmt not in ("PNG", "WEBP"):
                            drop(p, "format %s" % fmt)
                            continue
                    except Exception as e:      # noqa: BLE001
                        drop(p, "unreadable: %s" % e)
                        continue
                    res["kept"] += 1
            elif low.endswith(".json"):
                try:
                    with open(p) as f:
                        json.load(f)
                    res["kept"] += 1
                except (OSError, ValueError):
                    drop(p, "not valid JSON")
            else:
                drop(p, "file type not allowed in uploads")
    for r in res["reasons"]:
        log("verify: " + r)
    log("verify %s: kept %d files, deleted %d" % (out_dir, res["kept"], res["deleted"]))
    return res


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selftest")
    c = sub.add_parser("check")
    c.add_argument("images", nargs="+")
    v = sub.add_parser("verify")
    v.add_argument("dir")
    a = ap.parse_args(argv)
    if a.cmd == "verify":
        verify(a.dir)
        return 0
    try:
        f = ExposureFilter()
    except FilterUnavailable as e:
        print("FILTER UNAVAILABLE: %s" % e, file=sys.stderr)
        return 3
    if a.cmd == "selftest":
        try:
            f.selftest()
        except FilterUnavailable as e:
            print("FILTER SELF-TEST FAILED: %s" % e, file=sys.stderr)
            return 3
        return 0
    bad = 0
    for p in a.images:
        ok, rep = f.check_file(p)
        bad += not ok
        print("%s %s %s" % ("PASS" if ok else "DROP", p, json.dumps(rep)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
