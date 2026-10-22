"""Hero paintings ship compressed (lossy WebP at 90% quality) instead of lossless.

The main art of every hero, skin and adult look (`<name>.png` beside its `<name>.warp.json`) and its
portrait (`<name>_portrait.png`) are the bulk of the IPA. Lossless they made it 471 MB on 2026-10-22;
at 90% quality they are about a third of the size and look the same at 2x zoom (the owner was sent
the comparison). Rig masks, overlays and every other image keep their import settings: masks are
data, and overlays sit pixel-exact on the face.

Godot writes a lossless .import file for a new image on its first import, so run this after
installing art and importing, then import again:
    python tools/art_lossy.py            # set lossy on every hero painting's .import
    python tools/art_lossy.py --check    # list the ones that aren't (exit 1); a unit test does too
    tools/gd --headless --path . --import
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "heroes")
WANT = {"compress/mode": "1", "compress/lossy_quality": "0.9"}


def paintings():
    """Every hero painting .import path (main art and portraits, any look)."""
    for d, _dirs, files in os.walk(ROOT):
        names = set(files)
        for f in files:
            if not f.endswith(".png.import"):
                continue
            stem = f[: -len(".png.import")]
            base = stem[: -len("_portrait")] if stem.endswith("_portrait") else stem
            if base + ".warp.json" in names:
                yield os.path.join(d, f)


def needs(path):
    text = open(path, encoding="utf-8").read()
    return any(not re.search(r"^%s=%s\s*$" % (re.escape(k), re.escape(v)), text, re.M) for k, v in WANT.items())


def fix(path):
    text = open(path, encoding="utf-8").read()
    for k, v in WANT.items():
        text, n = re.subn(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), text, flags=re.M)
        if n == 0:
            text = text.replace("[params]\n", "[params]\n\n%s=%s\n" % (k, v), 1)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def main():
    check = "--check" in sys.argv
    todo = [p for p in paintings() if needs(p)]
    if check:
        for p in todo:
            print(os.path.relpath(p, os.path.join(ROOT, "..", "..", "..")))
        print("%d hero paintings not lossy" % len(todo))
        return 1 if todo else 0
    for p in todo:
        fix(p)
    print("set lossy on %d hero paintings" % len(todo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
