"""Assemble preview frames (transparent PNGs from tools/art_preview.gd) into a GIF and a
contact sheet, composited on the game background.

    python3 tools/art_gif.py <frames_dir> <out.gif> [--fps 30] [--sheet out_sheet.png] [--cols 8]
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw

BG = (18, 14, 36, 255)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("out")
    ap.add_argument("--fps", type=float, default=30)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--sheet_n", type=int, default=16)
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.frames, "*.png")))
    raw = [Image.open(fn).convert("RGBA") for fn in files]
    # crop every frame to the union of their content (+ margin) to keep the GIF small
    box = None
    for im in raw:
        b = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box:
        m = 12
        box = (max(0, box[0] - m), max(0, box[1] - m), min(raw[0].width, box[2] + m), min(raw[0].height, box[3] + m))
    frames = []
    for im in raw:
        if box:
            im = im.crop(box)
        bg = Image.new("RGBA", im.size, BG)
        bg.alpha_composite(im)
        frames.append(bg.convert("RGB"))
    # one shared adaptive palette keeps colours stable and the file small
    pal_src = Image.new("RGB", (frames[0].width, frames[0].height * min(4, len(frames))))
    for i in range(min(4, len(frames))):
        pal_src.paste(frames[i * len(frames) // min(4, len(frames))], (0, i * frames[0].height))
    pal = pal_src.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(a.out, save_all=True, append_images=q[1:], duration=int(round(1000.0 / a.fps)), loop=0, optimize=True, disposal=1)
    print("%s: %d frames, %.2f MB" % (a.out, len(q), os.path.getsize(a.out) / 1e6))
    if a.sheet:
        n = min(a.sheet_n, len(frames))
        pick = [frames[int(i * (len(frames) - 1) / max(n - 1, 1))] for i in range(n)]
        w, h = pick[0].size
        rows = (n + a.cols - 1) // a.cols
        S = Image.new("RGB", (a.cols * w, rows * (h + 18)), BG[:3])
        dr = ImageDraw.Draw(S)
        for i, f in enumerate(pick):
            x, y = (i % a.cols) * w, (i // a.cols) * (h + 18)
            S.paste(f, (x, y + 18))
            idx = int(i * (len(frames) - 1) / max(n - 1, 1))
            dr.text((x + 4, y + 3), "f%d  t=%.2fs" % (idx, idx / a.fps), fill=(230, 220, 200))
        S.save(a.sheet)
        print(a.sheet)


if __name__ == "__main__":
    main()
