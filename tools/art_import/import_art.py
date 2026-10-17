"""Copy the picked farm finals into assets/art/heroes/<id>/ (canvas + delivery variants)."""
import json, os, shutil, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
# The farm output branch checked out somewhere: git worktree add <dir> origin/art-gen-output
ARTGEN_OUT = os.environ.get("ARTGEN_OUT", os.path.join(REPO, "artgen-out"))


def load_picks():
    """tools/art_import/finals_picks.json with each canvas path resolved under ARTGEN_OUT."""
    picks = json.load(open(os.path.join(HERE, "finals_picks.json")))
    for p in picks.values():
        p["canvas"] = os.path.join(ARTGEN_OUT, p["canvas"])
    return picks


PICKS = load_picks()
DST = os.environ.get("HALO_ASSETS_HEROES", os.path.join(REPO, "assets", "art", "heroes"))
DELIVERY = ('eyes_open', 'eyes_closed', 'mouth_open', 'smile', 'hurt')
out = {}
only = sys.argv[1:]
for hid, p in PICKS.items():
    if only and hid not in only:
        continue
    src = os.path.dirname(p['canvas'])
    base = Image.open(p['canvas'])
    assert base.mode == 'RGBA' and base.size == (1024, 2048), (hid, base.mode, base.size)
    b = np.array(base)
    ys = np.nonzero(b[..., 3].max(axis=1) > 24)[0]
    vj = json.load(open(os.path.join(src, 'variants', 'variants.json')))
    d = os.path.join(DST, hid)
    os.makedirs(os.path.join(d, 'variants'), exist_ok=True)
    open(os.path.join(d, 'variants', '.gdignore'), 'a').close()
    shutil.copyfile(p['canvas'], os.path.join(d, hid + '.png'))
    got = []
    for v in DELIVERY:
        vp = os.path.join(src, 'variants', v + '.png')
        if not os.path.exists(vp):
            continue
        a = np.array(Image.open(vp).convert('RGBA'))
        assert (a[..., 3] == b[..., 3]).all(), (hid, v, 'alpha differs')
        diff = np.abs(a.astype(int) - b.astype(int)).max(axis=2)
        yy, xx = np.nonzero(diff > 8)
        reg = vj['variants'][v]['region']
        bbox = [int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())] if len(xx) else None
        shutil.copyfile(vp, os.path.join(d, 'variants', v + '.png'))
        got.append((v, bbox, reg))
    out[hid] = {'run': p['run'], 'seed': p['label'].split()[0], 'rows': [int(ys.min()), int(ys.max())], 'variants': got}
    print(hid, p['run'], out[hid]['rows'], got)
json.dump(out, open(os.path.join(HERE, 'import_log.json'), 'w'), indent=1)
