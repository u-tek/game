"""Crops the Cycles renders of tools/blender/ui_objects.py and gear_objects.py, adds a soft paper
shadow and writes 8-bit PNGs (style v4 collage objects).

    python tools/blender/finish_objects.py <render_dir>          # coil / disc -> assets/art/ui/objects/
    python tools/blender/finish_objects.py gear <render_dir>     # <noun>_<tier> -> assets/art/ui/gear/
    python tools/blender/finish_objects.py rival <render_dir>    # rival_objects.py renders -> assets/art/ui/objects/
"""
import os
import sys

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "objects")
# name: (max width, shadow offset, shadow blur, shadow alpha)
JOBS = {
    "coil_ink": (480, (10, 18), 14, 0.30),
    "coil_chrome": (480, (10, 18), 14, 0.26),
    "disc": (300, (5, 9), 7, 0.34),
}
# rival_objects.py renders already carry their contact shadow (a shadow catcher): crop and size only.
JOBS_RIVAL = {
    "thorns_corner": (720, (0, 0), 0, 0.0),
    "thorns_vine": (560, (0, 0), 0, 0.0),
    "dome": (220, (0, 0), 0, 0.0),
    "button": (240, (0, 0), 0, 0.0),
    "seal": (260, (0, 0), 0, 0.0),
}


def finish(src: str, name: str, spec: tuple, out_dir: str = OUT, fit_box: bool = False) -> None:
    max_w, off, blur, alpha = spec
    im = Image.open(src).convert("RGBA")
    bbox = im.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox()
    im = im.crop(bbox)
    k = min(1.0, max_w / max(im.width, im.height)) if fit_box else min(1.0, max_w / im.width)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    pad = blur * 2 + max(off)
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (16, 17, 19, 0))
    a = Image.new("L", canvas.size, 0)
    a.paste(im.getchannel("A").point(lambda v: int(v * alpha)), (pad + off[0], pad + off[1]))
    sh.putalpha(a.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(im, (pad, pad))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".png")
    canvas.save(path, optimize=True)
    print(name, canvas.size, "object at", (pad, pad), "size", im.size, "->", path)


if __name__ == "__main__":
    if sys.argv[1] == "gear":
        d = sys.argv[2]
        gear_out = os.path.join(ROOT, "assets", "art", "ui", "gear")
        for f in sorted(os.listdir(d)):
            if f.endswith(".png") and "_" in f and f[:-4].split("_")[-1].isdigit():
                finish(os.path.join(d, f), f[:-4], (300, (5, 9), 7, 0.3), gear_out, True)
        sys.exit(0)
    if sys.argv[1] == "rival":
        d = sys.argv[2]
        for n, spec in JOBS_RIVAL.items():
            p = os.path.join(d, n + ".png")
            if os.path.exists(p):
                finish(p, n, spec, OUT, True)
        sys.exit(0)
    d = sys.argv[1]
    for n, spec in JOBS.items():
        p = os.path.join(d, n + ".png")
        if os.path.exists(p):
            finish(p, n, spec)
