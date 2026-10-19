"""Crops the Cycles renders of tools/blender/ui_objects.py, adds a soft paper shadow and writes
8-bit PNGs to assets/art/ui/objects/ (style v4 collage objects).

    python tools/blender/finish_objects.py <render_dir>
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


def finish(src: str, name: str, spec: tuple) -> None:
    max_w, off, blur, alpha = spec
    im = Image.open(src).convert("RGBA")
    bbox = im.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox()
    im = im.crop(bbox)
    k = min(1.0, max_w / im.width)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    pad = blur * 2 + max(off)
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (16, 17, 19, 0))
    a = Image.new("L", canvas.size, 0)
    a.paste(im.getchannel("A").point(lambda v: int(v * alpha)), (pad + off[0], pad + off[1]))
    sh.putalpha(a.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(im, (pad, pad))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    canvas.save(path, optimize=True)
    print(name, canvas.size, "object at", (pad, pad), "size", im.size, "->", path)


if __name__ == "__main__":
    d = sys.argv[1]
    for n, spec in JOBS.items():
        p = os.path.join(d, n + ".png")
        if os.path.exists(p):
            finish(p, n, spec)
