"""Review renders for a hero, composited on the game background (#120e24).

    python3 tools/art_review.py seraphiel r1        # after tools/art_warp (or tools/art_build)

Writes screenshots/rig/<hero>_<label>_{detail,face,hair,sizes}.png:
  detail  figure ~1100 px tall (hero detail screen size)
  face    1:1 crop of the head (canvas scale 1.0)
  hair    crop of the hair at 0.6 scale
  sizes   battle size (~280 px figure), card portrait (152 px) and small portrait (96 px)
Uses Godot's own SVG renderer (tools/art_svg2png.gd) for the 1:1 render.
"""
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw

BG = (18, 14, 36, 255)
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def on_bg(im):
    bg = Image.new("RGBA", im.size, BG)
    bg.alpha_composite(im.convert("RGBA"))
    return bg


def main():
    hero = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else "review"
    hdir = os.path.join(ROOT, "assets", "art", "heroes", hero)
    out_dir = os.path.join(ROOT, "screenshots", "rig")
    os.makedirs(out_dir, exist_ok=True)
    warp = os.path.exists(os.path.join(hdir, hero + ".warp.json"))
    rig = json.load(open(os.path.join(hdir, hero + (".warp.json" if warp else ".rig.json"))))
    full = os.path.join(out_dir, "_%s_full.png" % hero)
    if warp:      # painted hero: the still IS the source image
        Image.open(os.path.join(hdir, rig["still"])).save(full)
    else:         # cutout hero: render the SVG source 1:1 with Godot's renderer
        subprocess.run([os.path.join(ROOT, "tools", "gd"), "--headless", "--path", ROOT, "-s", "tools/art_svg2png.gd", "--",
                        os.path.join(hdir, hero + ".svg"), full, "1.0"], cwd=ROOT, capture_output=True)
    im = on_bg(Image.open(full))
    ox, oy = rig["origin"]
    bx, by, bw, bh = rig["bounds"]
    top = int(oy + by)
    # detail: figure (head top to feet) at ~1100 px
    fig = im.crop((0, max(0, top - 10), im.width, int(oy) + 20))
    k = 1100.0 / fig.height
    det = fig.resize((int(fig.width * k), 1100), Image.LANCZOS)
    det.save(os.path.join(out_dir, "%s_%s_detail.png" % (hero, label)))
    # face 1:1 and hair crop
    px, py, pw, ph = rig["portrait_rect"]
    cx, cy = px + pw / 2, py + ph / 2
    im.crop((int(cx - 210), int(cy - 250), int(cx + 210), int(cy + 210))).save(os.path.join(out_dir, "%s_%s_face.png" % (hero, label)))
    hair = im.crop((150, 60, 720, 1720))
    hair.resize((int(hair.width * 0.6), int(hair.height * 0.6)), Image.LANCZOS).save(os.path.join(out_dir, "%s_%s_hair.png" % (hero, label)))
    # sizes: battle ~280 px figure, portraits 152 and 96
    kb = 280.0 / fig.height
    battle = fig.resize((int(fig.width * kb), 280), Image.LANCZOS)
    por = on_bg(Image.open(os.path.join(hdir, rig["portrait"])))
    p152 = por.resize((152, 152), Image.LANCZOS)
    p96 = por.resize((96, 96), Image.LANCZOS)
    sheet = Image.new("RGBA", (battle.width + 152 + 96 + 60, 300), BG)
    sheet.paste(battle, (10, 10))
    sheet.paste(p152, (battle.width + 30, 10))
    sheet.paste(p96, (battle.width + 192, 10))
    ImageDraw.Draw(sheet).text((battle.width + 30, 170), "card 152 / portrait 96", fill=(220, 210, 190, 255))
    sheet.save(os.path.join(out_dir, "%s_%s_sizes.png" % (hero, label)))
    os.remove(full)
    for n in ("detail", "face", "hair", "sizes"):
        print(os.path.join(out_dir, "%s_%s_%s.png" % (hero, label, n)))


if __name__ == "__main__":
    main()
