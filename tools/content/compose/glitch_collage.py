#!/usr/bin/env python3
"""Compose dense flat-lay "hidden-object" collages from Glitch item art (Tiny Speck, CC0 1.0).

Every picture is our composition: themed Glitch items (food, tools, furniture, plants ...) packed edge to
edge on a textured, colourful ground, each item once per picture, larger items first and smaller ones on
top, with a soft drop shadow. Pack definitions live in tools/content/compose/glitch_packs/<pack-id>.json,
item tags and exclusions (faces, text, logos) in tools/content/compose/glitch_tags.json. The finished
pictures go OUTSIDE the repo (~/.local/share/card-jigsaw-world/local-packs/<pack-id>/) and are published
with tools/dev/local_pack.py from the manifest this script writes to tools/content/local-packs/<pack-id>.json.

Setup, once (all outside the repo, in $CJW_GLITCH, default ~/.local/share/card-jigsaw-world/glitch):
  png/   sparse clone of https://github.com/ThirdPartyNinjas/GlitchAssets (2x PNG exports of
         tinyspeck/glitch-items): Items/{food,drink,herbs,spice,seeds,beans,alchemy,tools,keys,
         harvestable_resources,artifacts,compounds,quest_items,furniture}, Locations/, Player Houses/wallpaper/
         (never the avatars, inhabitants, giants, shrines, trophies, rare_items or misc folders)
  svg/   OpenGameArt SVG conversions (https://opengameart.org/content/glitch-food-drink-items-svg,
         .../glitch-misc-assets-svg, .../glitch-furniture-svg, .../glitch-groddle-forestmeadow-terrain-svg),
         each 7z archive extracted into svg/<archive name>/ (they have no external references)
  venv/  python3 -m venv venv && venv/bin/pip install cairosvg pillow numpy scipy

Run (with that venv's python):
  PY=~/.local/share/card-jigsaw-world/glitch/venv/bin/python
  $PY tools/content/compose/glitch_collage.py library                  # scan, clean guide lines, test SVGs (~10 min)
  $PY tools/content/compose/glitch_collage.py sheet TAG [--out FILE]   # review sheet of the items behind a tag
  $PY tools/content/compose/glitch_collage.py render PACK [--only SLUG ...] [--jobs 4]
  $PY tools/content/compose/glitch_collage.py contact PACK            # contact sheet + 100% crops of the pack
  $PY tools/content/compose/glitch_collage.py measure PACK            # giant.measure numbers (flat, dark, alike)
  $PY tools/content/compose/glitch_collage.py manifest PACK           # tools/content/local-packs/PACK.json
Then: .venv/bin/python tools/dev/local_pack.py check tools/content/local-packs/PACK.json

Rendering is deterministic for a given seed. Items are never scaled above their 2x PNG export unless the
SVG conversion renders faithfully (the `library` step compares every SVG with its PNG and rejects the ones
that lost Flash blend modes, which show as black or white stripes); other items stay at most at PNG size.
"""
import argparse, io, json, math, os, random, re, sys, time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
GLITCH = Path(os.environ.get('CJW_GLITCH', '~/.local/share/card-jigsaw-world/glitch')).expanduser()
OUT_ROOT = Path(os.environ.get('CJW_LOCAL_PACKS', '~/.local/share/card-jigsaw-world/local-packs')).expanduser()
TAGS_FILE = HERE / 'glitch_tags.json'
PACK_DIR = HERE / 'glitch_packs'
MANIFEST_DIR = REPO / 'tools' / 'content' / 'local-packs'
LIB_FILE = GLITCH / 'library.json'
CLEAN_DIR = GLITCH / 'cache' / 'clean'
SVG_CACHE = GLITCH / 'cache' / 'svg'
ITEM_GROUPS = ['food', 'drink', 'herbs', 'spice', 'seeds', 'beans', 'alchemy', 'tools', 'keys', 'harvestable_resources', 'artifacts',
               'compounds', 'quest_items', 'furniture']
SVG_MAX = 6.0          # an SVG-faithful item may be drawn up to 6x its 2x PNG export
CREDIT = dict(author='Tiny Speck (Glitch), composed by Card Jigsaw World', licence='CC0', source='Tiny Speck (Glitch), CC0',
              page='https://github.com/tinyspeck/glitch-items')


def font(size):
    for f in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf'):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def safe(item_id):
    return item_id.replace('/', '__')


# ----------------------------------------------------------------------------------------------- library

def clean_png(img, furniture):
    """Furniture only: erase Flash export guide lines (thin pure red / green lines) and tiny loose specks
    (registration dots), and flag Flash placeholder boxes. Returns (RGBA image trimmed to content, placeholder)."""
    if not furniture:
        im = img.convert('RGBA')
        bb = im.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
        return (im.crop(bb) if bb else None), False
    a = np.asarray(img.convert('RGBA')).astype(np.int16)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    guide = (((r > 200) & (g < 70) & (b < 70)) | ((r < 70) & (g > 150) & (g < 240) & (b < 110) & (g - b > 90))) & (al > 60)
    placeholder = False
    out = a.copy()
    if guide.any():
        lab, n = ndimage.label(guide, structure=np.ones((3, 3)))
        for i, sl in enumerate(ndimage.find_objects(lab), 1):
            ys, xs = sl
            h, w = ys.stop - ys.start, xs.stop - xs.start
            comp = lab[sl] == i
            if min(h, w) <= 3 and max(h, w) >= 8:
                if w >= h:      # horizontal: average the rows just above and below
                    y0, y1 = ys.start - 1, ys.stop
                    for x in range(xs.start, xs.stop):
                        col = comp[:, x - xs.start]
                        if not col.any():
                            continue
                        above = a[y0, x] if y0 >= 0 else None
                        below = a[y1, x] if y1 < a.shape[0] else None
                        rep = (above + below) // 2 if above is not None and below is not None else (above if above is not None else below)
                        for yy in np.nonzero(col)[0]:
                            out[ys.start + yy, x] = rep
                else:
                    x0, x1 = xs.start - 1, xs.stop
                    for y in range(ys.start, ys.stop):
                        row = comp[y - ys.start, :]
                        if not row.any():
                            continue
                        left = a[y, x0] if x0 >= 0 else None
                        right = a[y, x1] if x1 < a.shape[1] else None
                        rep = (left + right) // 2 if left is not None and right is not None else (left if left is not None else right)
                        for xx in np.nonzero(row)[0]:
                            out[y, xs.start + xx] = rep
            elif comp.sum() > 60 and min(h, w) >= 6:
                placeholder = True
    if furniture:
        m = out[..., 3] > 40
        lab, n = ndimage.label(m, structure=np.ones((3, 3)))
        if n > 1:
            sizes = ndimage.sum(m, lab, range(1, n + 1))
            total = sizes.sum()
            for i, s in enumerate(sizes, 1):
                if s < 0.006 * total and s < 500:
                    out[lab == i] = 0
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA')
    bb = im.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
    return (im.crop(bb) if bb else None), placeholder


def svg_index():
    idx = {}
    for p in (GLITCH / 'svg').rglob('*.svg'):
        rel = p.relative_to(GLITCH / 'svg')
        parts = rel.parts
        stem = p.stem
        if 'glitch-groddle-svg' in parts[0]:
            region = parts[-2]
            idx.setdefault(f'{region}/{stem}', 'svg/' + str(rel))
        else:
            idx.setdefault(stem, 'svg/' + str(rel))
    return idx


def svg_render(rel, scale):
    """rel: path relative to $CJW_GLITCH (svg/... or cache/svgfix/...)."""
    import cairosvg
    data = cairosvg.svg2png(url=str(GLITCH / rel), scale=scale)
    return Image.open(io.BytesIO(data)).convert('RGBA')


_STOP = re.compile(r'<stop([^>]*)style="stop-color:#([0-9A-Fa-f]{6})(;stop-opacity:([0-9.]+))?"')


def svg_screen_fix(txt):
    """The SVG conversions lost Flash blend modes: highlight shapes that were drawn in 'screen' mode with
    grey gradients render as black and white stripes. Turn every all-grey gradient into a white gradient
    whose opacity follows the grey level (what 'screen' does); `svg_check` decides whether that matches."""
    def grad(m):
        body = m.group(0)
        cols = re.findall(r'stop-color:#([0-9A-Fa-f]{6})', body)
        if not cols or not all(c[0:2].lower() == c[2:4].lower() == c[4:6].lower() for c in cols):
            return body
        def stop(sm):
            op = float(sm.group(4)) if sm.group(4) else 1.0
            return f'<stop{sm.group(1)}style="stop-color:#FFFFFF;stop-opacity:{int(sm.group(2)[0:2], 16) / 255 * op:.3f}"'
        return _STOP.sub(stop, body)
    return re.sub(r'<(linear|radial)Gradient.*?</\1Gradient>', grad, txt, flags=re.S)


def svg_check(png, rel):
    """(ok, box) - box is the trimmed content box of the SVG at scale 1. ok when the SVG render matches the
    PNG export: no dark or light stripes (lost blend modes), same colours, same proportions."""
    try:
        big = svg_render(rel, 4)
    except Exception:
        return False, None
    bb = big.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
    if not bb:
        return False, None
    box = [v / 4 for v in bb]
    r = big.crop(bb).resize(png.size, Image.LANCZOS)
    A = np.asarray(png, np.float32); B = np.asarray(r, np.float32)
    m = (A[..., 3] > 128) & (B[..., 3] > 128)
    if m.sum() < 30:
        return False, box
    la, lb = A[..., :3].mean(2), B[..., :3].mean(2)
    dark = ((lb < la - 60) & m).sum() / m.sum()
    light = ((lb > la + 60) & m).sum() / m.sum()
    pa = A[..., :3] / 255 * A[..., 3:] / 255; pb = B[..., :3] / 255 * B[..., 3:] / 255
    mu = (A[..., 3] > 25) | (B[..., 3] > 25)
    diff = float(np.abs(pa - pb)[mu].mean())
    cd = float(np.sqrt(((A[..., :3][m].mean(0) - B[..., :3][m].mean(0)) ** 2).sum()))
    ar = ((bb[2] - bb[0]) / (bb[3] - bb[1])) / (png.size[0] / png.size[1])
    ok = dark <= 0.03 and light <= 0.05 and diff <= 0.09 and 0.95 < ar < 1.05 and cd <= 20
    return bool(ok), box


def cmd_library(args):
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    svgs = svg_index()
    lib = {}
    srcs = []
    for g in ITEM_GROUPS:
        for p in sorted((GLITCH / 'png' / 'Items' / g).rglob('*.png')):
            srcs.append((p.stem, g, p))
    for region in sorted((GLITCH / 'png' / 'Locations').iterdir()):
        if region.is_dir():
            for p in sorted(region.glob('*.png')):
                srcs.append((f'{region.name}/{p.stem}', 'loc_' + region.name, p))
    t0 = time.time()
    for k, (iid, group, p) in enumerate(srcs):
        if iid in lib:
            continue
        img = Image.open(p).convert('RGBA')
        im, placeholder = clean_png(img, furniture=(group == 'furniture'))
        if im is None or max(im.size) < 20:
            continue
        im.save(CLEAN_DIR / f'{safe(iid)}.png')
        rec = dict(group=group, png=str(p.relative_to(GLITCH)), w=im.size[0], h=im.size[1], placeholder=placeholder, svg=None, svg_ok=False)
        if iid in svgs and group != 'furniture':
            ok, box = svg_check(im, svgs[iid])
            rec.update(svg=svgs[iid], svg_ok=ok, svg_box=box)
            if not ok:
                txt = (GLITCH / svgs[iid]).read_text(encoding='iso-8859-1')
                fixed = svg_screen_fix(txt)
                if fixed != txt:
                    fp = GLITCH / 'cache' / 'svgfix' / f'{safe(iid)}.svg'
                    fp.parent.mkdir(parents=True, exist_ok=True)
                    fp.write_text(fixed, encoding='iso-8859-1')
                    ok2, box2 = svg_check(im, str(fp.relative_to(GLITCH)))
                    if ok2:
                        rec.update(svg=str(fp.relative_to(GLITCH)), svg_ok=True, svg_box=box2, svg_fixed=True)
        lib[iid] = rec
        if k % 200 == 0:
            print(f'  {k}/{len(srcs)}  {time.time() - t0:.0f}s', flush=True)
    LIB_FILE.write_text(json.dumps(lib, indent=0))
    n_ok = sum(1 for v in lib.values() if v['svg_ok'])
    print(f'library: {len(lib)} items, {n_ok} with a faithful SVG, {sum(v["placeholder"] for v in lib.values())} with placeholders -> {LIB_FILE}')


# --------------------------------------------------------------------------------------------- selection

class Library:
    def __init__(self):
        self.items = json.loads(LIB_FILE.read_text())
        t = json.loads(TAGS_FILE.read_text())
        self.excl_names = {e for e in t['exclude'] if not e.startswith('re:')}
        self.excl_re = [re.compile(e[3:]) for e in t['exclude'] if e.startswith('re:')]
        self.tags = t['tags']
        self._cache = {}
        for iid in t.get('svg_force', []):
            r = self.items.get(iid)
            if r and r.get('svg') and r.get('svg_box') and not r['svg_ok']:
                fp = GLITCH / 'cache' / 'svgfix' / f'{safe(iid)}.svg'
                r['svg_ok'] = True
                if fp.exists():
                    r['svg'] = str(fp.relative_to(GLITCH))

    def excluded(self, iid):
        rec = self.items[iid]
        if rec.get('placeholder'):
            return True
        if iid in self.excl_names:
            return True
        return any(r.search(iid) for r in self.excl_re)

    def _match(self, entry):
        if entry.startswith('re:'):
            rx = re.compile(entry[3:])
            return [i for i in self.items if rx.search(i)]
        return [entry] if entry in self.items else []

    def select(self, selectors):
        """Selectors: 'tag:x', 'group:x', 're:...', a plain id; a leading '-' removes."""
        out, drop = [], set()
        for s in selectors:
            neg = s.startswith('-')
            s = s[1:] if neg else s
            if s.startswith('tag:'):
                ids = []
                for e in self.tags[s[4:]]:
                    ids += self._match(e)
            elif s.startswith('group:'):
                ids = [i for i, v in self.items.items() if v['group'] == s[6:]]
            else:
                ids = self._match(s)
            if neg:
                drop.update(ids)
            else:
                out += ids
        seen, res = set(), []
        for i in out:
            if i not in seen and i not in drop and not self.excluded(i):
                seen.add(i); res.append(i)
        return res

    def max_long(self, iid):
        r = self.items[iid]
        native = max(r['w'], r['h'])
        return native * SVG_MAX if r['svg_ok'] else native

    def native_long(self, iid):
        r = self.items[iid]
        return max(r['w'], r['h'])

    def image(self, iid, long_px):
        """RGBA image of the item with its long side about long_px (never above max_long)."""
        r = self.items[iid]
        native = max(r['w'], r['h'])
        long_px = int(max(8, min(long_px, self.max_long(iid))))
        key = (iid, long_px)
        if key in self._cache:
            return self._cache[key]
        if long_px <= native or not r['svg_ok']:
            im = Image.open(CLEAN_DIR / f'{safe(iid)}.png').convert('RGBA')
            if long_px < native:
                f = long_px / native
                im = im.resize((max(1, round(im.size[0] * f)), max(1, round(im.size[1] * f))), Image.LANCZOS)
        else:
            q = int(math.ceil(long_px / 16) * 16)
            cp = SVG_CACHE / f'{safe(iid)}_{q}.png'
            if cp.exists():
                im = Image.open(cp).convert('RGBA')
            else:
                x0, y0, x1, y1 = r['svg_box']
                scale = q / max(x1 - x0, y1 - y0)
                big = svg_render(r['svg'], scale)
                bb = big.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
                im = big.crop(bb) if bb else big
                SVG_CACHE.mkdir(parents=True, exist_ok=True)
                im.save(cp)
            if max(im.size) != long_px:
                f = long_px / max(im.size)
                im = im.resize((max(1, round(im.size[0] * f)), max(1, round(im.size[1] * f))), Image.LANCZOS)
        if len(self._cache) > 600:
            self._cache.clear()
        self._cache[key] = im
        return im


# ------------------------------------------------------------------------------------------------ grounds

def hexrgb(c):
    c = c.lstrip('#')
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def vnoise(h, w, cell, rng):
    gh, gw = h // cell + 3, w // cell + 3
    small = (rng.random((gh, gw)) * 255).astype(np.uint8)
    im = Image.fromarray(small).resize((gw * cell, gh * cell), Image.BICUBIC)
    return np.asarray(im, np.float32)[:h, :w] / 255.0


def fbm(h, w, rng, cells=(160, 60, 22, 8), weights=(0.45, 0.3, 0.17, 0.08)):
    out = np.zeros((h, w), np.float32)
    for c, wt in zip(cells, weights):
        out += wt * vnoise(h, w, max(2, c), rng)
    return out


def shade(base, amount):
    """base: HxWx3 float, amount: HxW in [-1, 1] -> lighten / darken."""
    a = amount[..., None]
    return np.where(a >= 0, base + (255 - base) * a, base * (1 + a))


def g_planks(h, w, rng, colors, width=150, vertical=False, seam=0.45, grain=0.18, **_):
    if vertical:
        return np.transpose(g_planks(w, h, rng, colors, width, False, seam, grain), (1, 0, 2))
    out = np.zeros((h, w, 3), np.float32)
    y = 0
    cols = [hexrgb(c) for c in colors]
    noise = fbm(h, w, rng, cells=(300, 90, 30, 6))
    yy = np.arange(h)[:, None].astype(np.float32)
    while y < h:
        pw = int(width * rng.uniform(0.85, 1.15))
        x = -int(rng.uniform(0, 900))
        while x < w:
            L = int(rng.uniform(500, 1400))
            base = cols[rng.integers(len(cols))] * rng.uniform(0.9, 1.08)
            x0, x1, y0, y1 = max(0, x), min(w, x + L), y, min(h, y + pw)
            if x1 > x0 and y1 > y0:
                n = noise[y0:y1, x0:x1]
                ph = rng.uniform(0, 6.28); per = rng.uniform(5, 11)
                g = np.sin((yy[y0:y1] + n * 40) / per + ph) * 0.5 + 0.5
                amt = (g - 0.5) * grain + (n - 0.5) * grain * 1.2
                out[y0:y1, x0:x1] = shade(np.broadcast_to(base, (y1 - y0, x1 - x0, 3)).copy(), amt)
                out[y0:y1, x0:min(w, x0 + 3)] *= seam + 0.25
            x += L
        out[y:min(h, y + 4)] *= seam
        out[min(h - 1, y + 4):min(h, y + 6)] = np.minimum(255, out[min(h - 1, y + 4):min(h, y + 6)] * 1.12)
        y += pw
    return out


def g_check(h, w, rng, colors, size=60, weave=0.08, **_):
    c1, c2 = hexrgb(colors[0]), hexrgb(colors[1] if len(colors) > 1 else '#ffffff')
    yy, xx = np.mgrid[0:h, 0:w]
    sy = ((yy // size) % 2).astype(np.float32); sx = ((xx // size) % 2).astype(np.float32)
    t = (sy + sx) / 2.0
    out = c2[None, None] * (1 - t[..., None]) + c1[None, None] * t[..., None]
    wv = ((np.sin(xx * 1.9) + np.sin(yy * 1.9)) * 0.25 + (rng.random((h, w)) - 0.5) * 0.5) * weave
    return shade(out, wv.astype(np.float32))


def g_plaid(h, w, rng, colors, size=90, **_):
    cols = [hexrgb(c) for c in colors]
    n = len(cols)
    yy, xx = np.mgrid[0:h, 0:w]
    widths = [int(size * rng.uniform(0.3, 1.0)) for _ in range(n)]
    period = sum(widths)
    edges = np.cumsum(widths)
    def band(v):
        m = v % period
        return np.searchsorted(edges, m, side='right')
    by, bx = band(yy), band(xx)
    pal = np.stack(cols)
    out = (pal[by] + pal[bx]) / 2
    wv = (np.sin((xx + yy) * 1.4) * 0.5) * 0.07
    return shade(out, wv.astype(np.float32))


def g_stripes(h, w, rng, colors, size=50, angle=0, **_):
    cols = np.stack([hexrgb(c) for c in colors])
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle)
    v = xx * math.cos(a) + yy * math.sin(a)
    idx = (v // size).astype(int) % len(cols)
    out = cols[idx]
    return shade(out, (fbm(h, w, rng, cells=(40, 8), weights=(0.6, 0.4)) - 0.5) * 0.12)


def g_dots(h, w, rng, colors, size=70, radius=0.22, **_):
    bg = hexrgb(colors[0]); dots = [hexrgb(c) for c in colors[1:]] or [hexrgb('#ffffff')]
    out = np.broadcast_to(bg, (h, w, 3)).copy()
    im = Image.fromarray(out.astype(np.uint8)); d = ImageDraw.Draw(im)
    r = size * radius
    for j, y in enumerate(range(0, h + size, size)):
        off = size / 2 if j % 2 else 0
        for x in np.arange(-size, w + size, size) + off:
            c = dots[rng.integers(len(dots))]
            d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(v) for v in c))
    out = np.asarray(im, np.float32)
    return shade(out, (fbm(h, w, rng, cells=(60, 10), weights=(0.6, 0.4)) - 0.5) * 0.1)


def g_tiles(h, w, rng, colors, size=110, grout='#e8e2d6', gw=6, pattern='random', **_):
    cols = [hexrgb(c) for c in colors]
    out = np.zeros((h, w, 3), np.float32)
    noise = fbm(h, w, rng, cells=(80, 20, 6))
    for ty in range(0, h, size):
        for tx in range(0, w, size):
            i, j = ty // size, tx // size
            if pattern == 'checker':
                c = cols[(i + j) % len(cols)]
            elif pattern == 'rows':
                c = cols[i % len(cols)]
            else:
                c = cols[rng.integers(len(cols))]
            c = c * rng.uniform(0.92, 1.06)
            y1, x1 = min(h, ty + size), min(w, tx + size)
            n = noise[ty:y1, tx:x1]
            blk = np.broadcast_to(c, (y1 - ty, x1 - tx, 3)).copy()
            # bevel: lighter top-left, darker bottom-right
            yy, xx = np.mgrid[0:y1 - ty, 0:x1 - tx].astype(np.float32)
            bev = np.where((yy < 6) | (xx < 6), 0.12, np.where((yy > size - 9) | (xx > size - 9), -0.12, 0.0))
            out[ty:y1, tx:x1] = shade(blk, (n - 0.5) * 0.18 + bev)
    g = hexrgb(grout)
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((yy % size) < gw) | ((xx % size) < gw)
    out[m] = g * 0.95
    return out


def g_grass(h, w, rng, colors=('#5d9a3a', '#78b445', '#4a8530', '#8cc152'), flowers=('#ffffff', '#ffd84a', '#f48fb1', '#b39ddb'), density=1.0, **_):
    cols = [hexrgb(c) for c in colors]
    base = np.zeros((h, w, 3), np.float32)
    n = fbm(h, w, rng)
    t = np.clip(n * 1.6 - 0.3, 0, 0.999)
    k = t * (len(cols) - 1)
    i0 = k.astype(int); f = (k - i0)[..., None]
    pal = np.stack(cols)
    base = pal[i0] * (1 - f) + pal[np.minimum(i0 + 1, len(cols) - 1)] * f
    im = Image.fromarray(base.clip(0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    nb = int(h * w / 260 * density)
    xs = rng.integers(0, w, nb); ys = rng.integers(0, h, nb)
    for x, y in zip(xs, ys):
        c = pal[rng.integers(len(pal))] * rng.uniform(0.7, 1.25)
        L = rng.uniform(10, 26); a = rng.uniform(-0.5, 0.5) - math.pi / 2
        d.line([x, y, x + L * math.cos(a), y + L * math.sin(a)], fill=tuple(int(v) for v in c.clip(0, 255)), width=2)
    fl = [hexrgb(c) for c in flowers]
    for _ in range(int(h * w / 9000 * density)):
        x, y = rng.integers(0, w), rng.integers(0, h)
        c = fl[rng.integers(len(fl))]; r = rng.uniform(3, 6)
        for k2 in range(5):
            a = k2 * 1.2566
            d.ellipse([x + r * math.cos(a) - r * .7, y + r * math.sin(a) - r * .7, x + r * math.cos(a) + r * .7, y + r * math.sin(a) + r * .7],
                      fill=tuple(int(v) for v in c))
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(250, 200, 40))
    return np.asarray(im, np.float32)


def g_scatter(h, w, rng, colors, bg=None, count=1.0, rmin=4, rmax=14, kind='pebble', **_):
    """Soil, gravel, sand, terrazzo: a noisy base with scattered pebbles or chips."""
    cols = [hexrgb(c) for c in colors]
    b = hexrgb(bg) if bg else cols[0]
    n = fbm(h, w, rng)
    base = shade(np.broadcast_to(b, (h, w, 3)).copy(), (n - 0.5) * 0.35)
    im = Image.fromarray(base.clip(0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    k = int(h * w / (rmax * rmax * 6) * count)
    for _ in range(k):
        x, y = rng.integers(0, w), rng.integers(0, h)
        rx, ry = rng.uniform(rmin, rmax), rng.uniform(rmin, rmax) * rng.uniform(0.6, 1)
        c = cols[rng.integers(len(cols))] * rng.uniform(0.8, 1.15)
        if kind == 'chip':
            pts = [(x + rx * math.cos(a) * rng.uniform(0.5, 1), y + ry * math.sin(a) * rng.uniform(0.5, 1)) for a in np.linspace(0, 6.28, 6)[:-1]]
            d.polygon(pts, fill=tuple(int(v) for v in c.clip(0, 255)))
        else:
            d.ellipse([x - rx + 1.5, y - ry + 2, x + rx + 1.5, y + ry + 2], fill=tuple(int(v) for v in (c * 0.55).clip(0, 255)))
            d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=tuple(int(v) for v in c.clip(0, 255)))
            d.ellipse([x - rx * .5, y - ry * .7, x, y - ry * .2], fill=tuple(int(v) for v in (c * 1.15).clip(0, 255)))
    return np.asarray(im, np.float32)


def g_cobble(h, w, rng, colors, size=90, mortar='#6b6358', **_):
    cols = [hexrgb(c) for c in colors]
    gy, gx = np.mgrid[0:h + size:size, 0:w + size:size]
    pts = np.stack([gy.ravel() + rng.uniform(-size * .35, size * .35, gy.size), gx.ravel() + rng.uniform(-size * .35, size * .35, gx.size)], 1)
    s = 4
    hh, ww = h // s + 1, w // s + 1
    yy, xx = np.mgrid[0:hh, 0:ww] * s
    from scipy.spatial import cKDTree
    tree = cKDTree(pts)
    dist, idx = tree.query(np.stack([yy.ravel(), xx.ravel()], 1), k=2)
    edge = (dist[:, 1] - dist[:, 0]).reshape(hh, ww)
    lab = idx[:, 0].reshape(hh, ww)
    pal = np.stack([cols[i % len(cols)] * rng.uniform(0.85, 1.1) for i in rng.permutation(len(pts))])
    small = pal[lab]
    big = np.asarray(Image.fromarray(small.clip(0, 255).astype(np.uint8)).resize((ww * s, hh * s), Image.NEAREST), np.float32)[:h, :w]
    e = np.asarray(Image.fromarray((np.clip(edge / size * 6, 0, 1) * 255).astype(np.uint8)).resize((ww * s, hh * s), Image.BILINEAR), np.float32)[:h, :w] / 255
    n = fbm(h, w, rng, cells=(50, 15, 5))
    out = shade(big, (n - 0.5) * 0.3 + (e - 0.6) * 0.25)
    m = hexrgb(mortar)
    t = np.clip((0.18 - e) / 0.18, 0, 1)[..., None]
    return out * (1 - t) + m * t


def g_quilt(h, w, rng, colors, size=180, **_):
    """Patchwork: every patch its own small pattern (dots, stripes, check, plain linen)."""
    cols = [hexrgb(c) for c in colors]
    out = np.zeros((h, w, 3), np.float32)
    for ty in range(0, h, size):
        for tx in range(0, w, size):
            y1, x1 = min(h, ty + size), min(w, tx + size)
            ph, pw = y1 - ty, x1 - tx
            c1 = cols[rng.integers(len(cols))]; c2 = cols[rng.integers(len(cols))]
            if np.allclose(c1, c2):
                c2 = np.clip(c1 * 0.75 + 60, 0, 255)
            kind = rng.integers(4)
            hx = lambda c: '#%02x%02x%02x' % tuple(int(v) for v in c)
            sub = np.random.default_rng(int(rng.integers(1 << 30)))
            if kind == 0:
                patch = g_dots(ph, pw, sub, [hx(c1), hx(c2)], size=int(size / rng.integers(4, 7)), radius=0.2)
            elif kind == 1:
                patch = g_stripes(ph, pw, sub, [hx(c1), hx(c2)], size=int(size / rng.integers(6, 12)), angle=int(rng.choice([0, 45, 90, 135])))
            elif kind == 2:
                patch = g_check(ph, pw, sub, [hx(c1), hx(c2)], size=int(size / rng.integers(5, 9)))
            else:
                patch = shade(np.broadcast_to(c1, (ph, pw, 3)).copy(), (fbm(ph, pw, sub, cells=(30, 6), weights=(.5, .5)) - .5) * .2)
            out[ty:y1, tx:x1] = patch
            out[ty:y1, tx:min(w, tx + 3)] *= 0.6
            out[ty:min(h, ty + 3), tx:x1] *= 0.6
    return out


def g_linen(h, w, rng, colors, **_):
    c = hexrgb(colors[0])
    yy, xx = np.mgrid[0:h, 0:w]
    weave = (np.sin(xx * 2.2) * np.sin(yy * 2.2)) * 0.05
    n = (rng.random((h, w)) - 0.5) * 0.08 + (fbm(h, w, rng, cells=(120, 30), weights=(.6, .4)) - .5) * .15
    return shade(np.broadcast_to(c, (h, w, 3)).copy(), (weave + n).astype(np.float32))


def g_wallpaper(h, w, rng, name, scale=2.0, **_):
    p = GLITCH / 'png' / 'Player Houses' / 'wallpaper' / f'{name}.png'
    t = Image.open(p).convert('RGB')
    t = t.resize((int(t.size[0] * scale), int(t.size[1] * scale)), Image.LANCZOS)
    out = Image.new('RGB', (w, h))
    for y in range(0, h, t.size[1]):
        for x in range(0, w, t.size[0]):
            out.paste(t, (x, y))
    return np.asarray(out, np.float32)


GROUNDS = dict(planks=g_planks, check=g_check, plaid=g_plaid, stripes=g_stripes, dots=g_dots, tiles=g_tiles, grass=g_grass,
               scatter=g_scatter, cobble=g_cobble, quilt=g_quilt, linen=g_linen, wallpaper=g_wallpaper)


def make_ground(spec, h, w, rng):
    spec = dict(spec)
    kind = spec.pop('type')
    return GROUNDS[kind](h, w, rng, **spec)


# ------------------------------------------------------------------------------------------------ layouts

def layout_labels(lay, hh, ww, rng):
    """Zone label map at mask resolution."""
    t = lay.get('type', 'single')
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    wob = (fbm(hh, ww, rng, cells=(60, 20), weights=(.7, .3)) - .5) * lay.get('wobble', 0.0) * min(hh, ww)
    if t == 'single':
        return np.zeros((hh, ww), np.int32)
    if t in ('hbands', 'vbands'):
        n = lay['n']
        sizes = np.array(lay.get('sizes', [1] * n), np.float32); cuts = np.cumsum(sizes)[:-1] / sizes.sum()
        v = (yy if t == 'hbands' else xx) + wob
        L = (hh if t == 'hbands' else ww)
        lab = np.zeros((hh, ww), np.int32)
        for c in cuts:
            lab += (v > c * L).astype(np.int32)
        return lab
    if t == 'grid':
        cols, rows = lay['cols'], lay['rows']
        cx = np.clip(((xx + wob) / ww * cols).astype(int), 0, cols - 1)
        cy = np.clip(((yy + wob) / hh * rows).astype(int), 0, rows - 1)
        return (cy * cols + cx).astype(np.int32)
    if t == 'voronoi':
        n = lay['n']
        pts = []
        while len(pts) < n:
            p = (rng.uniform(0.1, 0.9) * hh, rng.uniform(0.1, 0.9) * ww)
            if all(math.hypot(p[0] - q[0], p[1] - q[1]) > 0.8 * math.sqrt(hh * ww / n) for q in pts) or rng.random() < 0.02:
                pts.append(p)
        d = np.stack([np.hypot(yy + wob - py, xx + wob - px) for py, px in pts])
        return d.argmin(0).astype(np.int32)
    if t == 'ring':
        m = lay.get('margin', 0.22)
        ey, ex = (yy + wob - hh / 2) / (hh * (0.5 - m)), (xx + wob - ww / 2) / (ww * (0.5 - m))
        inner = (np.abs(ey) ** 4 + np.abs(ex) ** 4) < 1 if lay.get('square') else (ey ** 2 + ex ** 2) < 1
        return np.where(inner, 0, 1).astype(np.int32)
    if t == 'diag':
        n = lay.get('n', 2)
        v = (xx / ww + yy / hh) / 2 + wob / max(hh, ww)
        return np.clip((v * n).astype(int), 0, n - 1).astype(np.int32)
    raise ValueError(t)


# ---------------------------------------------------------------------------------------------- placement

S = 4  # mask resolution: 1 mask pixel = S x S picture pixels


class Composer:
    """Greedy packer on a coarse occupancy grid (1 cell = S x S px). Each item goes where it overlaps least,
    prefers spots that touch other items or the frame (tight packing), and keeps to its zone."""
    contact_w = 0.12

    def __init__(self, lib, W, H, rng):
        self.lib, self.W, self.H, self.rng = lib, W, H, rng
        self.hh, self.ww = H // S, W // S
        self.cov = np.zeros((self.hh, self.ww), np.float32)
        self.placed = []          # (iid, img, x, y)
        self.used = set()

    def item_mask(self, img):
        a = img.getchannel('A')
        w, h = max(1, round(img.size[0] / S)), max(1, round(img.size[1] / S))
        m = np.asarray(a.resize((w, h), Image.BILINEAR), np.float32) / 255.0
        m = (m > 0.35).astype(np.float32)
        pad = np.pad(m, 2)
        ring = ndimage.binary_dilation(pad, iterations=2).astype(np.float32) - pad
        return m, ring

    def score(self, m, ring, cy, cx, zone_mask):
        h, w = m.shape
        y0, x0 = int(round(cy - h / 2)), int(round(cx - w / 2))
        ya, xa = max(0, y0), max(0, x0)
        yb, xb = min(self.hh, y0 + h), min(self.ww, x0 + w)
        if yb <= ya or xb <= xa:
            return 9, 1, 1, (y0, x0)
        sub = m[ya - y0:yb - y0, xa - x0:xb - x0]
        tot = m.sum() + 1e-6
        inside = sub.sum() / tot
        ov = float((sub * self.cov[ya:yb, xa:xb]).sum() / tot)
        zf = float((sub * zone_mask[ya:yb, xa:xb]).sum() / tot) if zone_mask is not None else 1.0
        out = 1 - inside
        # contact: share of the ring around the item that is occupied or outside the frame
        ry0, rx0 = y0 - 2, x0 - 2
        rh, rw = ring.shape
        rya, rxa, ryb, rxb = max(0, ry0), max(0, rx0), min(self.hh, ry0 + rh), min(self.ww, rx0 + rw)
        rtot = ring.sum() + 1e-6
        rin = ring[rya - ry0:ryb - ry0, rxa - rx0:rxb - rx0]
        contact = float((rin * (self.cov[rya:ryb, rxa:rxb] > 0.5)).sum() / rtot)
        s = ov + 0.8 * max(0.0, out - 0.15) + 0.6 * max(0.0, 0.75 - zf) - self.contact_w * contact
        return s, ov, out, (y0, x0)

    def candidates(self, zone_mask, k=30):
        free = self.cov < 0.5
        zone = free if zone_mask is None else (free & (zone_mask > 0.5))
        if not zone.any():
            return []
        edt = ndimage.distance_transform_edt(free) * zone
        flat = edt.ravel()
        idx = [int(flat.argmax())]
        p = flat ** 2
        p /= p.sum()
        n = int((p > 0).sum())
        idx += list(self.rng.choice(flat.size, size=min(k, n), replace=False, p=p))
        fz = np.flatnonzero(zone)
        idx += list(self.rng.choice(fz, size=min(k // 2, fz.size), replace=False))
        # free cells next to occupied ones: snug spots
        edge = np.flatnonzero(zone & ndimage.binary_dilation(~free, iterations=1))
        if edge.size:
            idx += list(self.rng.choice(edge, size=min(k // 2, edge.size), replace=False))
        idx = np.unique(np.asarray(idx))
        return [(i // self.ww, i % self.ww) for i in idx]

    def try_place(self, iid, long_px, zone_mask, max_ov, min_px, tries=3, at=None):
        for t in range(tries + 1):
            img = self.lib.image(iid, long_px)
            m, ring = self.item_mask(img)
            cands = self.candidates(zone_mask)
            if at is not None:
                cands = [at] + cands
            if not cands:
                return False
            best = None
            for cy, cx in cands:
                for jy, jx in ((0, 0), (m.shape[0] * .3, 0), (-m.shape[0] * .3, 0), (0, m.shape[1] * .3), (0, -m.shape[1] * .3)):
                    sc = self.score(m, ring, cy + jy, cx + jx, zone_mask)
                    if best is None or sc[0] < best[0]:
                        best = sc
            s, ov, out, (y0, x0) = best
            if ov <= max_ov and out <= 0.35:
                h, w = m.shape
                ya, xa, yb, xb = max(0, y0), max(0, x0), min(self.hh, y0 + h), min(self.ww, x0 + w)
                self.cov[ya:yb, xa:xb] = np.maximum(self.cov[ya:yb, xa:xb], m[ya - y0:yb - y0, xa - x0:xb - x0])
                px, py = x0 * S + (w * S - img.size[0]) // 2, y0 * S + (h * S - img.size[1]) // 2
                self.placed.append((iid, img, px, py))
                self.used.add(iid)
                return True
            long_px = long_px * 0.82
            if long_px < min_px:
                return False
        return False

    def largest_hole(self, zone_mask):
        free = self.cov < 0.5
        edt = ndimage.distance_transform_edt(free)
        if zone_mask is not None:
            edt = edt * (zone_mask > 0.5)
        i = int(edt.argmax())
        return float(edt.ravel()[i]), (i // self.ww, i % self.ww)

    def coverage(self, zone_mask=None):
        c = self.cov > 0.5
        if zone_mask is None:
            return float(c.mean())
        z = zone_mask > 0.5
        return float(c[z].mean()) if z.any() else 1.0


def size_for(lib, iid, sz, W, rng):
    mode = sz.get('mode', 'frac')
    u = rng.random() ** sz.get('power', 1.6)
    if mode == 'native':
        f = sz.get('min', 0.6) + (sz.get('max', 1.0) - sz.get('min', 0.6)) * (1 - u)
        L = lib.native_long(iid) * f * sz.get('mult', 1.0)
    else:
        L = W * (sz.get('min', 0.05) + (sz.get('max', 0.2) - sz.get('min', 0.05)) * u)
    L = min(L, lib.max_long(iid), W * sz.get('cap', 0.45))
    return max(L, 8)


def compose(lib, pack, pic, W, H, seed):
    rng = np.random.default_rng(seed)
    comp = Composer(lib, W, H, rng)
    lay = pic.get('layout', {'type': 'single'})
    zones = pic['zones']
    labels = layout_labels(lay, comp.hh, comp.ww, rng)
    nz = int(labels.max()) + 1
    zone_specs = [zones[i % len(zones)] for i in range(nz)]
    defaults = pack.get('defaults', {})
    # ground
    ground = np.zeros((H, W, 3), np.float32)
    lab_full = np.asarray(Image.fromarray(labels.astype(np.uint8)).resize((W, H), Image.NEAREST))
    for z in range(nz):
        g = make_ground(zone_specs[z]['ground'], H, W, np.random.default_rng(seed * 31 + z))
        m = lab_full == z
        ground[m] = g[m]
    if nz > 1:   # seams between zones: a dark line with a light edge, like the rim of a board or cloth
        e = np.zeros((H, W), bool)
        e[:-1] |= lab_full[:-1] != lab_full[1:]
        e[:, :-1] |= lab_full[:, :-1] != lab_full[:, 1:]
        e = ndimage.binary_dilation(e, iterations=4)
        ground[e] *= 0.55
    # items per zone
    pools = []
    for z in range(nz):
        zs = zone_specs[z]
        ids = [i for i in lib.select(zs['items'])]
        rng.shuffle(ids)
        pools.append(ids)
    fill_ids = lib.select(pic.get('fill', [])) if pic.get('fill') else []
    rng.shuffle(fill_ids)
    zone_masks = [(labels == z).astype(np.float32) for z in range(nz)] if nz > 1 else [None]
    # hero items first (zone 'hero' selectors drawn big)
    for z in range(nz):
        zs = zone_specs[z]
        sz = {**defaults.get('size', {}), **zs.get('size', {})}
        min_px = sz.get('min_px', W * 0.03)
        target = zs.get('cover', defaults.get('cover', 0.8))
        heroes = lib.select(zs.get('hero', [])) if zs.get('hero') else []
        hsz = {**sz, **zs.get('hero_size', {'min': sz.get('max', 0.2) * 0.9, 'max': sz.get('max', 0.2) * 1.4, 'power': 1.0})}
        plan = [(i, size_for(lib, i, hsz, W, rng)) for i in heroes if i not in comp.used]
        plan += [(i, size_for(lib, i, sz, W, rng)) for i in pools[z] if i not in comp.used and i not in heroes]
        plan.sort(key=lambda t: -t[1])
        for iid, L in plan:
            if comp.coverage(zone_masks[z]) >= target:
                break
            if iid in comp.used:
                continue
            comp.try_place(iid, L, zone_masks[z], zs.get('max_ov', defaults.get('max_ov', 0.16)), min_px)
    # fill: always the largest hole of the whole picture; an unused item of that zone (its pool, its fill, the
    # picture's fill, then the pack's fill_all) that can be drawn at the hole's size (fill_size caps it), so big
    # holes get SVG items and small ones the small PNG items
    fill_cover = pic.get('fill_cover', defaults.get('fill_cover', 0.97))
    fill_all = lib.select(pack.get('fill_all', [])) if pack.get('fill_all') else []
    rng.shuffle(fill_all)
    zone_cands = []
    for z in range(nz):
        zs = zone_specs[z]
        extra = lib.select(zs['fill']) if zs.get('fill') else []
        rng.shuffle(extra)
        zone_cands.append(list(dict.fromkeys(pools[z] + extra + fill_ids + fill_all)))
    misses = 0
    while misses < 60 and comp.coverage() < fill_cover:
        r, at = comp.largest_hole(None)
        z = int(labels[at]) if nz > 1 else 0
        zs = zone_specs[z]
        sz = {**defaults.get('size', {}), **zs.get('size', {})}
        fsz = {**sz, **defaults.get('fill_size', {}), **pic.get('fill_size', {}), **zs.get('fill_size', {})}
        min_fill = fsz.get('min_px', W * 0.035)
        if r * S * 2 < min_fill * 0.6:
            break
        cand = [i for i in zone_cands[z] if i not in comp.used]
        zone_cands[z] = cand
        if not cand:
            break
        want = min(max(r * S * 2.3, fsz.get('min', 0.05) * W), fsz.get('max', 0.14) * W)
        able = [i for i in cand[:120] if lib.max_long(i) >= want * 0.85]
        pick = able[0] if able else max(cand[:120], key=lib.max_long)
        L = min(want * rng.uniform(0.9, 1.1), lib.max_long(pick))
        ok = comp.try_place(pick, L, zone_masks[z] if nz > 1 else None, zs.get('fill_ov', defaults.get('fill_ov', 0.3)), min_fill * 0.6, tries=3, at=at)
        if not ok:
            misses += 1
            cand.remove(pick)
            if L > min_fill:
                cand.append(pick)
    # render
    canvas = Image.fromarray(ground.clip(0, 255).astype(np.uint8)).convert('RGBA')
    sh_op = pic.get('shadow', defaults.get('shadow', 0.34))
    for iid, img, x, y in comp.placed:
        L = max(img.size)
        blur = max(2, L * 0.018)
        off = max(2, int(L * 0.022))
        pad = int(blur * 3) + off
        a = img.getchannel('A')
        shadow = Image.new('L', (img.size[0] + 2 * pad, img.size[1] + 2 * pad), 0)
        shadow.paste(a, (pad, pad))
        shadow = shadow.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * sh_op))
        dark = Image.new('RGBA', shadow.size, (30, 22, 14, 0)); dark.putalpha(shadow)
        _paste(canvas, dark, x - pad + off, y - pad + int(off * 1.3))
        _paste(canvas, img, x, y)
    return canvas.convert('RGB'), [p[0] for p in comp.placed], comp.coverage()


def _paste(canvas, img, x, y):
    """alpha_composite that tolerates negative offsets and overhang."""
    W, H = canvas.size
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + img.size[0]), min(H, y + img.size[1])
    if x1 <= x0 or y1 <= y0:
        return
    canvas.alpha_composite(img.crop((x0 - x, y0 - y, x1 - x, y1 - y)), (x0, y0))


# --------------------------------------------------------------------------------------------- commands

def load_pack(name):
    p = Path(name)
    if not p.exists():
        p = PACK_DIR / (name if name.endswith('.json') else f'{name}.json')
    return json.loads(p.read_text()), p


def out_dir(pack):
    d = OUT_ROOT / pack['pack']['id']
    d.mkdir(parents=True, exist_ok=True)
    return d


def pic_path(pack, i, pic):
    return out_dir(pack) / f'{i + 1:02d}-{pic["slug"]}.png'


def _render_one(args):
    pack_file, i = args
    pack, _ = load_pack(pack_file)
    lib = Library()
    pic = pack['pictures'][i]
    W, H = pic.get('canvas', pack['canvas'])
    t0 = time.time()
    img, ids, cov = compose(lib, pack, pic, W, H, pic.get('seed', 1000 + i))
    p = pic_path(pack, i, pic)
    img.save(p, optimize=False, compress_level=6)
    meta = dict(slug=pic['slug'], title=pic['title'], items=ids, count=len(ids), coverage=round(cov, 3), size=[W, H])
    p.with_suffix('.json').write_text(json.dumps(meta, indent=0))
    return f'{p.name}: {len(ids)} items, coverage {cov:.2f}, {time.time() - t0:.0f}s'


def cmd_render(args):
    pack, pf = load_pack(args.pack)
    idx = [i for i, p in enumerate(pack['pictures']) if not args.only or p['slug'] in args.only or str(i + 1) in args.only]
    jobs = [(str(pf), i) for i in idx]
    if args.jobs > 1 and len(jobs) > 1:
        with ProcessPoolExecutor(args.jobs) as ex:
            for line in ex.map(_render_one, jobs):
                print(' ', line, flush=True)
    else:
        for j in jobs:
            print(' ', _render_one(j), flush=True)


def cmd_contact(args):
    pack, _ = load_pack(args.pack)
    d = out_dir(pack)
    files = [(i, p, pic_path(pack, i, p)) for i, p in enumerate(pack['pictures'])]
    files = [f for f in files if f[2].exists()]
    cols = 6
    tw, th = 300, 400
    rows = (len(files) + cols - 1) // cols
    sh = Image.new('RGB', (cols * (tw + 10) + 10, rows * (th + 36) + 10), (245, 245, 245))
    dr = ImageDraw.Draw(sh)
    for k, (i, pic, f) in enumerate(files):
        im = Image.open(f).convert('RGB'); im.thumbnail((tw, th), Image.LANCZOS)
        x, y = 10 + (k % cols) * (tw + 10), 10 + (k // cols) * (th + 36)
        sh.paste(im, (x, y))
        dr.text((x, y + th + 4), f'{i + 1}. {pic["title"]}'[:40], fill=(0, 0, 0), font=font(16))
    cp = d / f'contact-{pack["pack"]["id"]}.png'
    sh.save(cp)
    print(cp)
    if args.crops:
        for i, pic, f in files:
            im = Image.open(f).convert('RGB')
            W, H = im.size
            c = min(W, H) // 3
            spots = [(0.5, 0.5), (0.2, 0.2), (0.8, 0.75)]
            out = Image.new('RGB', (c * 3 + 20, c), (255, 255, 255))
            for k, (fx, fy) in enumerate(spots):
                x, y = int(fx * W - c / 2), int(fy * H - c / 2)
                x, y = max(0, min(W - c, x)), max(0, min(H - c, y))
                out.paste(im.crop((x, y, x + c, y + c)), (k * (c + 10), 0))
            out.save(d / f'crop-{i + 1:02d}.jpg', quality=88)


def cmd_measure(args):
    sys.path.insert(0, str(REPO / 'tools' / 'content'))
    from cjw import giant
    pack, _ = load_pack(args.pack)
    for i, pic in enumerate(pack['pictures']):
        p = pic_path(pack, i, pic)
        if not p.exists():
            continue
        st = giant.measure(Image.open(p))
        mp = p.with_suffix('.json')
        meta = json.loads(mp.read_text()) if mp.exists() else {}
        meta['giant'] = st
        mp.write_text(json.dumps(meta, indent=0))
        flag = '' if st['flat'] <= 0.08 and st['alike'] <= 0.15 and st['dark'] <= 0.15 and st['sharp'] >= 1.8 else '  <-- check'
        print(f"{i + 1:2d} {pic['slug']:28s} {st['w']}x{st['h']} sharp {st['sharp']:5.2f} flat {st['flat']:.3f} dark {st['dark']:.3f} alike {st['alike']:.3f}{flag}")


def cmd_manifest(args):
    pack, _ = load_pack(args.pack)
    pics = []
    for i, pic in enumerate(pack['pictures']):
        p = pic_path(pack, i, pic)
        meta = json.loads(p.with_suffix('.json').read_text())
        pics.append(dict(file=str(p), title=pic['title'], author=CREDIT['author'], licence=CREDIT['licence'], source=CREDIT['source'],
                         page=CREDIT['page'], changes=f"composed from {meta['count']} items"))
    m = dict(pack=pack['pack'], pictures=pics)
    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    out = MANIFEST_DIR / f"{pack['pack']['id']}.json"
    out.write_text(json.dumps(m, indent=1, ensure_ascii=False) + '\n')
    print(out)


def cmd_sheet(args):
    lib = Library()
    ids = lib.select(args.selectors)
    cell, cols = 170, 8
    rows = (len(ids) + cols - 1) // cols
    sh = Image.new('RGB', (cols * cell, max(1, rows) * (cell + 18)), (205, 205, 210))
    d = ImageDraw.Draw(sh)
    for k, iid in enumerate(ids):
        im = lib.image(iid, min(cell - 10, lib.max_long(iid)))
        x, y = (k % cols) * cell, (k // cols) * (cell + 18)
        sh.paste(im, (x + (cell - im.size[0]) // 2, y + (cell - im.size[1]) // 2), im)
        r = lib.items[iid]
        d.text((x + 2, y + cell), f"{'*' if r['svg_ok'] else ' '}{iid.split('/')[-1][:24]}", fill=(0, 0, 0), font=font(11))
    out = args.out or str(GLITCH / 'cache' / f'sheet-{re.sub(r"[^a-z0-9]+", "_", "_".join(args.selectors))[:60]}.png')
    sh.save(out)
    print(out, len(ids), 'items')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('library')
    s = sub.add_parser('sheet'); s.add_argument('selectors', nargs='+'); s.add_argument('--out')
    s = sub.add_parser('render'); s.add_argument('pack'); s.add_argument('--only', nargs='*'); s.add_argument('--jobs', type=int, default=4)
    s = sub.add_parser('contact'); s.add_argument('pack'); s.add_argument('--crops', action='store_true')
    s = sub.add_parser('measure'); s.add_argument('pack')
    s = sub.add_parser('manifest'); s.add_argument('pack')
    a = ap.parse_args()
    dict(library=cmd_library, sheet=cmd_sheet, render=cmd_render, contact=cmd_contact, measure=cmd_measure, manifest=cmd_manifest)[a.cmd](a)


if __name__ == '__main__':
    main()
