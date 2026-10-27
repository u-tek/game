"""The foil's surface: a tileable normal map of hot-stamped metallic foil (the rarity language's gold
and violet foil, src/ui/shaders/foil.gdshader reads it through the global `foil_n`).

    python tools/textures/foil_normal.py            # writes assets/art/ui/foil/foil_n.png

Real stamped foil is a thin metal film pressed onto paper: it is never flat, it breaks into small
facets (the film creasing as the die presses it) over the paper's own tooth. So the height field is
(1) Voronoi facets, each a slightly tilted plane (a crease between neighbours), at two scales, (2)
the paper's tooth under it (fine noise), (3) faint press lines. Everything wraps (the map tiles).
Encoding: RGB = normal * 0.5 + 0.5, x right, y up (OpenGL), z out of the sheet. 512 px.
"""
import os

import numpy as np
from PIL import Image

N = 512
RNG = np.random.default_rng(31)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "art", "ui", "foil")


def facets(cells: int, tilt: float) -> np.ndarray:
    """A wrapped Voronoi field where each cell is a tilted plane through its seed: a facet."""
    pts = RNG.random((cells, 2)) * N
    slopes = RNG.normal(0.0, tilt, (cells, 2))
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    best = np.full((N, N), 1e9, np.float32)
    second = np.full((N, N), 1e9, np.float32)
    h = np.zeros((N, N), np.float32)
    for i, (px, py) in enumerate(pts):
        dx = (xx - px + N / 2) % N - N / 2
        dy = (yy - py + N / 2) % N - N / 2
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < best
        second = np.where(closer, best, np.minimum(second, d))
        h = np.where(closer, dx * slopes[i, 0] + dy * slopes[i, 1], h)
        best = np.where(closer, d, best)
    # A soft crease where two facets meet (the film folds rather than tears).
    crease = np.clip((second - best) / 3.0, 0.0, 1.0)
    return h * (0.5 + 0.5 * crease) - (1.0 - crease) * 0.25


def wrapped_noise(scale: int, octaves: int) -> np.ndarray:
    """Tileable value noise from low-res random grids, upsampled with wrap."""
    out = np.zeros((N, N), np.float32)
    amp = 1.0
    for o in range(octaves):
        g = scale * (2 ** o)
        grid = RNG.random((g, g)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        # Bicubic from a wrapped grid: pad by tiling first so the seam matches.
        tiled = np.tile(grid, (3, 3))
        big = Image.fromarray((tiled * 255).astype(np.uint8)).resize((N * 3, N * 3), Image.BICUBIC)
        arr = np.asarray(big, np.float32)[N:2 * N, N:2 * N] / 255.0
        out += (arr - 0.5) * amp
        amp *= 0.5
        del img
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    h = facets(240, 0.13) * 1.0 + facets(1100, 0.1) * 0.35
    h += wrapped_noise(64, 3) * 1.2       # the paper's tooth under the film
    yy = np.mgrid[0:N, 0:N][0].astype(np.float32)
    h += np.sin(yy / N * 2 * np.pi * 96) * 0.06   # faint press lines (tile exactly: 96 per tile)
    # Normals from the wrapped gradient.
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    strength = 1.6
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], -1)
    img = np.clip(nrm * 0.5 + 0.5, 0, 1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, "foil_n.png"), optimize=True)
    print("foil_n.png", N, "tilt spread", float(np.std(nx / ln)), float(np.std(ny / ln)))


if __name__ == "__main__":
    main()
