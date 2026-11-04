"""Coordinate grid over a canvas image (for reading joint positions).
Usage: grid.py <img> <out.png> [x0 y0 x1 y1] [scale]"""
import sys
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
bg = Image.new("RGBA", im.size, (90, 90, 96, 255))
bg.alpha_composite(im)
x0, y0, x1, y1 = (map(int, sys.argv[3:7]) if len(sys.argv) >= 7 else (0, 0, im.width, im.height))
sc = float(sys.argv[7]) if len(sys.argv) >= 8 else 1.0
c = bg.crop((x0, y0, x1, y1))
c = c.resize((int(c.width * sc), int(c.height * sc)), Image.LANCZOS)
d = ImageDraw.Draw(c)
try:
    f = ImageFont.truetype("arial.ttf", 14)
except Exception:
    f = ImageFont.load_default()
step = 50 if (x1 - x0) > 300 else 20
for x in range((x0 // step) * step, x1 + 1, step):
    if x < x0:
        continue
    X = (x - x0) * sc
    major = x % (step * 2) == 0
    d.line([(X, 0), (X, c.height)], fill=(255, 40, 40, 200) if major else (255, 255, 0, 110), width=1)
    if major:
        d.text((X + 2, 2), str(x), fill=(255, 60, 60, 255), font=f)
for y in range((y0 // step) * step, y1 + 1, step):
    if y < y0:
        continue
    Y = (y - y0) * sc
    major = y % (step * 2) == 0
    d.line([(0, Y), (c.width, Y)], fill=(255, 40, 40, 200) if major else (255, 255, 0, 110), width=1)
    if major:
        d.text((2, Y + 2), str(y), fill=(255, 60, 60, 255), font=f)
c.convert("RGB").save(out)
print(out, c.size)
