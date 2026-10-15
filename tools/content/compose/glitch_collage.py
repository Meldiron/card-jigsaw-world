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
  $PY tools/content/compose/glitch_collage.py render PACK [--only SLUG|N ...]  # in order, item use capped per pack
  $PY tools/content/compose/glitch_collage.py similar PACK           # near-repeat check (phash, colour) between pictures
  $PY tools/content/compose/glitch_collage.py contact PACK            # contact sheet + 100% crops of the pack
  $PY tools/content/compose/glitch_collage.py measure PACK            # giant.measure numbers (flat, dark, alike)
  $PY tools/content/compose/glitch_collage.py manifest PACK           # tools/content/local-packs/PACK.json
Then: .venv/bin/python tools/dev/local_pack.py check tools/content/local-packs/PACK.json

Pack definition (glitch_packs/<pack-id>.json; pack-treasure-trove.json is written by _make_treasure_trove.py):
  pack        the manifest's pack block (id, name, category, description, sortOrder, price)
  canvas      [W, H]; grid (mask cell px, 6 for 3072 x 4096); max_uses (default a third of the pictures);
              max_items (per picture); defaults (size, fill_size, cover, fill_cover, palette_max, row); fill_all
  pictures    slug, title, seed, priority (rendered first), palette (filler colours), layout, zones, fill
  layout      single | hbands | vbands | grid | voronoi | ring | diag | cloth | cubbies (row_cols) | crates | trays | table
  zones       items (tag:x, re:..., ids), ground (planks, tiles, check, plaid, stripes, dots, grass, scatter,
              cobble, quilt, linen, marble, paint, pegboard, wallpaper), hero, size, fill, floor (cubbies)
Rendering is deterministic for a given seed and order. Pictures render in priority order; an item, and a
"kind" of recoloured variants (glitch_tags.json), appears in at most max_uses pictures of a pack, and filler
never takes an item that a later picture names in its own zones. Items are never scaled above their 2x PNG
export unless the SVG conversion renders faithfully (the `library` step compares every SVG with its PNG and
rejects the ones that lost Flash blend modes, which show as black or white stripes). `library` also erases
Flash export marks from furniture (red and green guide lines, white registration dots).
"""
import argparse, io, json, math, os, random, re, sys, time
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
CREDIT = dict(author='Tiny Speck (Glitch), composed by Carden', licence='CC0', source='Tiny Speck (Glitch), CC0',
              page='https://github.com/tinyspeck/glitch-items')


def font(size):
    for f in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf'):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def safe(item_id):
    return item_id.replace('/', '__')


# ----------------------------------------------------------------------------------------------- library

def _fill_from_ring(out, region, inner_iter=1, outer_iter=4):
    """Replace region pixels by what surrounds them: transparent when the surroundings are mostly empty,
    else the median colour of the opaque, not-dark surrounding pixels."""
    near = ndimage.binary_dilation(region, iterations=inner_iter)
    ring = ndimage.binary_dilation(near, iterations=outer_iter) & ~near
    al = out[..., 3]
    if not ring.any() or (al[ring] > 60).mean() < 0.5:
        out[near] = 0
        return
    lum = out[..., :3].mean(2)
    ok = ring & (al > 60) & (lum > 60)
    src = out[ok] if ok.any() else out[ring & (al > 60)]
    out[near] = np.median(src, axis=0).astype(out.dtype)


def _trim_overhang(out, gap=3, min_len=6):
    """Guide lines run past the drawing: clear 1-2 px thin rows that stick out beyond the drawing's extent
    in the rows `gap` above and below (works on a view, so a transposed array trims columns)."""
    m = out[..., 3] > 16
    h, w = m.shape
    any_ = m.any(1)
    left = np.where(any_, m.argmax(1), w)
    right = np.where(any_, w - 1 - m[:, ::-1].argmax(1), -1)
    for y in range(h):
        if not any_[y]:
            continue
        nb = [k for k in (y - gap, y - gap - 1, y + gap, y + gap + 1) if 0 <= k < h]
        lo = min([left[k] for k in nb] + [w]); hi = max([right[k] for k in nb] + [-1])
        if hi < 0:
            lo, hi = w, -1
        if left[y] < lo - min_len:
            out[y, :lo][m[y, :lo]] = 0
        if right[y] > hi + min_len:
            out[y, hi + 1:][m[y, hi + 1:]] = 0


def clean_png(img, furniture, dots=False):
    """Furniture only: erase Flash export marks (thin single-colour red / green guide lines, white
    registration dots with a black ring at the base or the top-left origin) and loose specks, and flag
    Flash placeholder boxes. Returns (RGBA image trimmed to content, placeholder)."""
    if not furniture and not dots:
        im = img.convert('RGBA')
        bb = im.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
        return (im.crop(bb) if bb else None), False
    a = np.asarray(img.convert('RGBA')).astype(np.int16)
    out = a.copy()
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    placeholder = False
    pure = (((r > 170) & (g < 35) & (b < 35)) | ((g > 140) & (r < 30) & (b < g * 0.45)) | ((g > 190) & (r < 95) & (b < 115))) & (al > 0)
    guideish = (((g > 110) & (g - r > 45) & (g - b > 35)) | ((r > 150) & (r - g > 90) & (r - b > 80))) & (al > 0)
    guide = guideish & ndimage.binary_dilation(pure, iterations=2)
    if not furniture:           # location parts: registration dots only (their grass and leaves are pure greens)
        guide[:] = False
    if guide.any():
        lab, n = ndimage.label(guide, structure=np.ones((3, 3)))
        for i, sl in enumerate(ndimage.find_objects(lab), 1):
            ys, xs = sl
            h, w = ys.stop - ys.start, xs.stop - xs.start
            comp = lab[sl] == i
            cols = a[sl][comp][:, :3]
            uniform = (cols.max(0) - cols.min(0)).max() < 40
            if min(h, w) <= 3 and max(h, w) >= 5 and pure[sl][comp].mean() >= 0.25:
                reg = np.zeros(guide.shape, bool); reg[sl] = comp
                if w >= h:      # horizontal line: average the rows just above and below
                    for x in range(xs.start, xs.stop):
                        col = comp[:, x - xs.start]
                        if not col.any():
                            continue
                        y0, y1 = ys.start - 1, ys.stop
                        above = a[y0, x] if y0 >= 0 else None
                        below = a[y1, x] if y1 < a.shape[0] else None
                        rep = (above + below) // 2 if above is not None and below is not None else (above if above is not None else below)
                        out[ys.start:ys.stop, x][col] = rep
                else:
                    for y in range(ys.start, ys.stop):
                        row = comp[y - ys.start, :]
                        if not row.any():
                            continue
                        x0, x1 = xs.start - 1, xs.stop
                        left = a[y, x0] if x0 >= 0 else None
                        right = a[y, x1] if x1 < a.shape[1] else None
                        rep = (left + right) // 2 if left is not None and right is not None else (left if left is not None else right)
                        out[y, xs.start:xs.stop][row] = rep
            elif comp.sum() > 60 and min(h, w) >= 6 and uniform:
                placeholder = True
    # registration dots: small white discs ringed in black, at the base or at the top-left origin
    bb = Image.fromarray(np.clip(al, 0, 255).astype(np.uint8)).getbbox()
    if bb:
        lum = a[..., :3].mean(2)
        white = (a[..., :3].min(2) > 230) & (al > 100)
        lab, n = ndimage.label(white)
        for i, sl in enumerate(ndimage.find_objects(lab) if n else [], 1):
            ys, xs = sl
            comp = lab[sl] == i
            c = int(comp.sum()); h, w = ys.stop - ys.start, xs.stop - xs.start
            if not (8 <= c <= 160 and 0.6 < h / w < 1.7 and c / (h * w) > 0.5):
                continue
            reg = np.zeros(white.shape, bool); reg[sl] = comp
            ring = ndimage.binary_dilation(reg, iterations=1) & ~reg
            dark = ((lum < 90) | (al < 30))[ring].mean()
            inked = ((lum < 90) & (al > 60))[ring].mean()          # a drawn black outline, not just the edge
            opaque = (al > 100)[ring].mean()
            small_disc = 5 <= h <= 9 and 5 <= w <= 9 and c / (h * w) > 0.7
            ring_lum = float(lum[ring][al[ring] > 100].mean()) if opaque > 0 else 255.0
            if (dark > 0.6 and inked > 0.4) or (small_disc and opaque > 0.6 and (inked > 0.35 or ring_lum < 140)):
                _fill_from_ring(out, ndimage.binary_dilation(reg, iterations=2), inner_iter=1, outer_iter=4)
    if furniture:
        _trim_overhang(out)
        _trim_overhang(out.transpose(1, 0, 2))
    m = out[..., 3] > 40
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    if n > 1 and furniture:
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        total = sizes.sum()
        for i, sz in enumerate(sizes, 1):
            if sz < 0.006 * total and sz < 500:
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
        im, placeholder = clean_png(img, furniture=(group == 'furniture'), dots=group.startswith('loc_'))
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
        self.colors = self._color_stats()
        self.kind = {}
        for k, sel in t.get('kinds', {}).items():
            for iid in self.select(sel):
                self.kind.setdefault(iid, k)

    def _color_stats(self):
        """Per item: alpha-weighted mean colour in Lab and in RGB (cached in cache/colors.json)."""
        cp = GLITCH / 'cache' / 'colors.json'
        cache = json.loads(cp.read_text()) if cp.exists() else {}
        dirty = False
        for iid in self.items:
            if iid in cache and 'lstd' in cache[iid]:
                continue
            a = np.asarray(Image.open(CLEAN_DIR / f'{safe(iid)}.png').convert('RGBA'), np.float32)
            m = a[..., 3] > 128
            rgb = a[..., :3][m].mean(0) if m.any() else np.array([128, 128, 128], np.float32)
            lstd = float(a[..., :3].mean(2)[m].std()) if m.any() else 0.0
            cache[iid] = dict(rgb=[round(float(v), 1) for v in rgb], lab=[round(float(v), 2) for v in to_lab(rgb[None])[0]], lstd=round(lstd, 1))
            dirty = True
        if dirty:
            cp.parent.mkdir(parents=True, exist_ok=True)
            cp.write_text(json.dumps(cache))
        return cache

    def palette_dist(self, iid, palette):
        """Smallest Lab distance from the item's mean colour to any palette colour (chroma weighted up)."""
        lab = np.array(self.colors[iid]['lab'], np.float32)
        best = 1e9
        for c in palette:
            p = to_lab(hexrgb(c)[None])[0]
            d = math.sqrt(0.5 * (lab[0] - p[0]) ** 2 + (lab[1] - p[1]) ** 2 + (lab[2] - p[2]) ** 2)
            best = min(best, d)
        return best

    def aspect(self, iid):
        r = self.items[iid]
        return r['w'] / r['h']

    def max_h(self, iid):
        r = self.items[iid]
        return self.max_long(iid) * r['h'] / max(r['w'], r['h'])

    def image_h(self, iid, h_px):
        """Item drawn about h_px tall (capped like image())."""
        r = self.items[iid]
        return self.image(iid, h_px * max(r['w'], r['h']) / r['h'])

    def excluded(self, iid):
        rec = self.items[iid]
        lstd = self.colors.get(iid, {}).get('lstd', 99)
        if rec.get('placeholder') or lstd < 4 or (lstd < 13 and max(rec['w'], rec['h']) > 300):
            return True       # Flash placeholders, plain masks and big plain boards (flat cards)
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


def to_lab(rgb):
    """N x 3 sRGB (0-255) -> N x 3 CIE Lab (D65)."""
    c = np.asarray(rgb, np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


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


def g_marble(h, w, rng, colors=('#f2f0ec',), vein='#9a948c', **_):
    base = hexrgb(colors[0])
    n = fbm(h, w, rng, cells=(220, 90, 30, 10))
    n2 = fbm(h, w, rng, cells=(160, 50, 14), weights=(.5, .3, .2))
    v = np.abs(np.sin((n * 9 + n2 * 5) * math.pi))
    veins = np.clip(1 - v * 6, 0, 1) ** 2
    out = shade(np.broadcast_to(base, (h, w, 3)).copy(), (n2 - 0.5) * 0.12)
    vc = hexrgb(vein)
    return out * (1 - veins[..., None] * 0.6) + vc * veins[..., None] * 0.6


def g_paint(h, w, rng, colors, strokes=1.0, **_):
    """Painted plaster: one colour with brush strokes and a few lighter and darker patches."""
    base = hexrgb(colors[0])
    out = shade(np.broadcast_to(base, (h, w, 3)).copy(), (fbm(h, w, rng, cells=(200, 70, 20)) - 0.5) * 0.22)
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    for _ in range(int(h * w / 2500 * strokes)):
        x, y = rng.integers(0, w), rng.integers(0, h)
        L = rng.uniform(20, 70); a = rng.uniform(-0.4, 0.4)
        f = rng.uniform(0.9, 1.1)
        c = tuple(int(v) for v in (base * f).clip(0, 255))
        d.line([x, y, x + L * math.cos(a), y + L * math.sin(a)], fill=c, width=int(rng.integers(2, 5)))
    return np.asarray(im, np.float32)


def g_pegboard(h, w, rng, colors=('#c8a27a',), hole='#5a4632', pitch=46, **_):
    """Workshop pegboard: a fibre board with a regular grid of holes."""
    out = g_paint(h, w, rng, colors, strokes=0.3)
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    hc = tuple(int(v) for v in hexrgb(hole))
    r = max(3, pitch // 9)
    for y in range(pitch // 2, h, pitch):
        for x in range(pitch // 2, w, pitch):
            d.ellipse([x - r, y - r, x + r, y + r], fill=hc)
            d.arc([x - r - 1, y - r - 1, x + r + 1, y + r + 1], 200, 380, fill=tuple(min(255, int(v * 1.25)) for v in hexrgb(colors[0])))
    return np.asarray(im, np.float32)


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
               scatter=g_scatter, cobble=g_cobble, quilt=g_quilt, linen=g_linen, wallpaper=g_wallpaper, marble=g_marble,
               paint=g_paint, pegboard=g_pegboard)


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


# ------------------------------------------------------------------------------------------------ structures
#
# A structure turns a picture's "layout" into zones and a painted ground. Each zone has a spec (cycled from
# the picture's "zones" list), a mode ("pack": items packed in 2D inside a mask; "row": items standing on a
# shelf or floor line) and its region. Kinds:
#   single | hbands | vbands | grid | voronoi | ring | diag   soft-edged regions (pack)
#   cubbies   shelves or pigeonholes in a wooden frame (row): cols, rows, frame, frame_w, board_h, floor_h
#   crates    crates seen from above in a grid (pack): cols, rows, gutter, rim, rim_colors, base (ground)
#   trays     treemap of rounded trays with painted rims (pack): n, gutter, rim, rims, base
#   table     round / oval table seen from above on a floor (pack): shape, margin, plates, edge, base
#   cloth     picnic cloth with a striped border on a ground (pack): margin, border{colors,width}, base

def _rect_mask(hh, ww, x0, y0, x1, y1):
    m = np.zeros((hh, ww), bool)
    m[max(0, int(y0 / S)):int(math.ceil(y1 / S)), max(0, int(x0 / S)):int(math.ceil(x1 / S))] = True
    return m


def _paint(ground, spec, mask_full, seed, H, W, box=None):
    """Paint a ground spec into ground where mask_full is True (box limits the work to a rectangle)."""
    if box is None:
        g = make_ground(spec, H, W, np.random.default_rng(seed))
        ground[mask_full] = g[mask_full]
        return
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(W, x1), min(H, y1)
    if x1 <= x0 or y1 <= y0:
        return
    g = make_ground(spec, y1 - y0, x1 - x0, np.random.default_rng(seed))
    sub = mask_full[y0:y1, x0:x1]
    ground[y0:y1, x0:x1][sub] = g[sub]


def _wood(h, w, rng, colors, vertical=False):
    return g_planks(h, w, rng, colors, width=max(12, (w if vertical else h) + 2), vertical=vertical, seam=0.7, grain=0.22)


def _board(ground, x0, y0, x1, y1, colors, rng, vertical=False, light_top=True):
    x0, y0, x1, y1 = [int(round(v)) for v in (x0, y0, x1, y1)]
    H, W = ground.shape[:2]
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    if x1 <= x0 or y1 <= y0:
        return
    b = _wood(y1 - y0, x1 - x0, rng, colors, vertical)
    t = max(2, (y1 - y0) // 5) if not vertical else max(2, (x1 - x0) // 5)
    if light_top:
        if vertical:
            b[:, :t] = np.minimum(255, b[:, :t] * 1.18)
            b[:, -t:] *= 0.7
        else:
            b[:t] = np.minimum(255, b[:t] * 1.2)
            b[-t:] *= 0.68
    ground[y0:y1, x0:x1] = b


def _shadow_band(ground, x0, y0, x1, y1, strength=0.35, down=True):
    """Soft shadow gradient inside a rectangle (under a shelf board, along a rim)."""
    x0, y0, x1, y1 = [int(round(v)) for v in (x0, y0, x1, y1)]
    H, W = ground.shape[:2]
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    if x1 <= x0 or y1 <= y0:
        return
    n = y1 - y0
    g = np.linspace(1 - strength, 1, n)[:, None, None] if down else np.linspace(1, 1 - strength, n)[:, None, None]
    ground[y0:y1, x0:x1] *= g


def _round_rect(w, h, r):
    im = Image.new('L', (w, h), 0)
    ImageDraw.Draw(im).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return np.asarray(im) > 127


def _treemap(rect, n, rng, min_ratio=0.45):
    rects = [rect]
    while len(rects) < n:
        rects.sort(key=lambda r: -(r[2] - r[0]) * (r[3] - r[1]))
        x0, y0, x1, y1 = rects.pop(0)
        w, h = x1 - x0, y1 - y0
        f = rng.uniform(0.35, 0.65)
        if w > h * 1.1 or (w > h * 0.8 and rng.random() < 0.5):
            xm = x0 + w * f
            rects += [(x0, y0, xm, y1), (xm, y0, x1, y1)]
        else:
            ym = y0 + h * f
            rects += [(x0, y0, x1, ym), (x0, ym, x1, y1)]
    return rects


def build_structure(lay, zone_list, W, H, rng, seed):
    """-> dict(ground HxWx3 float, labels hh x ww int (-1 = no items), zones [dict(spec, mode, mask, rows)])."""
    hh, ww = H // S, W // S
    t = lay.get('type', 'single')
    ground = np.zeros((H, W, 3), np.float32)
    zones = []
    labels = -np.ones((hh, ww), np.int32)
    base_spec = lay.get('base')

    def spec_for(k):
        return zone_list[k % len(zone_list)]

    if t in ('single', 'hbands', 'vbands', 'grid', 'voronoi', 'ring', 'diag', 'cloth'):
        lab = layout_labels(dict(lay, type='ring', square=True) if t == 'cloth' else lay, hh, ww, rng)
        nz = int(lab.max()) + 1
        lab_full = np.asarray(Image.fromarray(lab.astype(np.uint8)).resize((W, H), Image.NEAREST))
        for z in range(nz):
            _paint(ground, spec_for(z)['ground'], lab_full == z, seed * 31 + z, H, W)
            zones.append(dict(spec=spec_for(z), mode='pack', mask=(lab == z)))
        labels = lab
        if t == 'cloth':
            b = lay.get('border', {'colors': ['#ffffff', '#d33f3f'], 'width': 0.035})
            inner = lab_full == 0
            dist = ndimage.distance_transform_edt(inner)
            bw = b.get('width', 0.035) * W
            cols = [hexrgb(c) for c in b['colors']]
            band = (dist > 0) & (dist < bw)
            k = (dist[band] / bw * len(cols) * 2).astype(int) % len(cols)
            ground[band] = np.stack(cols)[k] * 0.97
            ext = (~inner) & (ndimage.distance_transform_edt(~inner) < W * 0.012)
            ground[ext] *= 0.6
            zones[0]['mask'] = zones[0]['mask'] & (ndimage.distance_transform_edt(lab == 0) > bw * 0.5 / S)
        elif nz > 1:
            e = np.zeros((H, W), bool)
            e[:-1] |= lab_full[:-1] != lab_full[1:]
            e[:, :-1] |= lab_full[:, :-1] != lab_full[:, 1:]
            e = ndimage.binary_dilation(e, iterations=4)
            ground[e] *= 0.55
        return dict(ground=ground, labels=labels, zones=zones)

    if base_spec:
        _paint(ground, base_spec, np.ones((H, W), bool), seed * 7, H, W)

    if t == 'cubbies':
        # row_cols (optional): rooms per floor, e.g. [1, 2, 3] for a dolls' house; else cols x rows
        rows = len(lay['row_cols']) if lay.get('row_cols') else lay.get('rows', 4)
        row_cols = lay.get('row_cols') or [lay.get('cols', 1)] * rows
        fw = lay.get('frame_w', 0.022) * W
        bh = lay.get('board_h', 0.018) * H
        wood = lay.get('frame', ['#a8774a', '#9a6b40', '#b4835a'])
        rowh = np.array(lay.get('row_sizes', [1] * rows), np.float32); rowh = rowh / rowh.sum() * (H - bh * (rows + 1))
        assign = lay.get('assign', 'cell')
        y = bh
        k = 0
        posts = []
        for r in range(rows):
            cols = row_cols[r]
            cs = lay.get('col_sizes') if not lay.get('row_cols') else None
            colw = np.array(cs or [1] * cols, np.float32); colw = colw / colw.sum() * (W - fw * (cols + 1))
            x = fw
            for c in range(cols):
                x0, y0, x1, y1 = x, y, x + colw[c], y + rowh[r]
                zi = {'cell': k, 'row': r, 'col': c}[assign]
                spec = spec_for(zi)
                m_full = np.zeros((H, W), bool)
                m_full[int(y0):int(y1) + 1, int(x0):int(x1) + 1] = True
                _paint(ground, spec['ground'], m_full, seed * 31 + k, H, W, box=(x0, y0, x1 + 1, y1 + 1))
                fh = spec.get('floor_h', lay.get('floor_h', 0)) * (y1 - y0)
                if fh > 0 and spec.get('floor'):
                    fm = np.zeros((H, W), bool)
                    fm[int(y1 - fh):int(y1) + 1, int(x0):int(x1) + 1] = True
                    _paint(ground, spec['floor'], fm, seed * 37 + k, H, W, box=(x0, y1 - fh, x1 + 1, y1 + 1))
                    _shadow_band(ground, x0, y1 - fh, x1, y1 - fh + 6, 0.35, down=True)
                _shadow_band(ground, x0, y0, x1, y0 + (y1 - y0) * 0.22, 0.32, down=True)
                base = y1 - fh * 0.4
                zm = _rect_mask(hh, ww, x0, y0, x1, y1)
                labels[zm] = len(zones)
                zones.append(dict(spec=spec, mode='row', mask=zm, rows=[(x0, x1, base, base - y0)], box=(x0, y0, x1, y1)))
                k += 1
                posts.append((x0 - fw, y0 - bh, x0, y1 + bh))
                x = x1 + fw
            posts.append((x - fw, y - bh, x, y + rowh[r] + bh))
            y += rowh[r] + bh
        # frame: boards and posts (posts per floor, so floors can hold different numbers of rooms)
        y = 0
        for r in range(rows + 1):
            _board(ground, 0, y, W, y + bh, wood, np.random.default_rng(seed + r))
            if r < rows:
                _shadow_band(ground, 0, y + bh, W, y + bh + bh * 0.8, 0.3)
                y += bh + rowh[r]
        for j, (x0, y0, x1, y1) in enumerate(posts):
            _board(ground, x0, max(0, y0 + bh), x1, y1 - bh, wood, np.random.default_rng(seed + 50 + j), vertical=True)
        return dict(ground=ground, labels=labels, zones=zones)

    if t in ('crates', 'trays'):
        if t == 'crates':
            cols, rows = lay.get('cols', 2), lay.get('rows', 3)
            g = lay.get('gutter', 0.025) * W
            cw, ch = (W - g * (cols + 1)) / cols, (H - g * (rows + 1)) / rows
            rects = [(g + c * (cw + g), g + r * (ch + g), g + c * (cw + g) + cw, g + r * (ch + g) + ch) for r in range(rows) for c in range(cols)]
        else:
            g = lay.get('gutter', 0.02) * W
            rects = _treemap((g / 2, g / 2, W - g / 2, H - g / 2), lay.get('n', 6), rng)
            rects = [(x0 + g / 2, y0 + g / 2, x1 - g / 2, y1 - g / 2) for x0, y0, x1, y1 in rects]
        rim = lay.get('rim', 0.04 if t == 'crates' else 0.022) * W
        rim_colors = lay.get('rim_colors', ['#b98a55', '#a97b48', '#c89a64'])
        rims = lay.get('rims')
        for k, (x0, y0, x1, y1) in enumerate(rects):
            spec = spec_for(k)
            X0, Y0, X1, Y1 = [int(round(v)) for v in (x0, y0, x1, y1)]
            w, h = X1 - X0, Y1 - Y0
            # drop shadow on the base
            sh = np.zeros((H, W), np.float32)
            sh[min(H - 1, Y0 + 10):min(H, Y1 + 14), min(W - 1, X0 + 8):min(W, X1 + 12)] = 1
            sh = ndimage.gaussian_filter(sh, 9)
            ground *= (1 - 0.35 * sh)[..., None]
            if t == 'crates':
                outer = np.zeros((H, W), bool); outer[Y0:Y1, X0:X1] = True
                r_rng = np.random.default_rng(seed + 100 + k)
                # four boards
                _board(ground, X0, Y0, X1, Y0 + rim, rim_colors, r_rng)
                _board(ground, X0, Y1 - rim, X1, Y1, rim_colors, r_rng)
                _board(ground, X0, Y0, X0 + rim, Y1, rim_colors, r_rng, vertical=True)
                _board(ground, X1 - rim, Y0, X1, Y1, rim_colors, r_rng, vertical=True)
                inner = (X0 + rim, Y0 + rim, X1 - rim, Y1 - rim)
                im = np.zeros((H, W), bool); im[int(inner[1]):int(inner[3]), int(inner[0]):int(inner[2])] = True
                _paint(ground, spec['ground'], im, seed * 31 + k, H, W, box=inner)
                _shadow_band(ground, inner[0], inner[1], inner[2], inner[1] + rim * 0.9, 0.4)
                zm = _rect_mask(hh, ww, *inner)
            else:
                rr = int(min(w, h) * 0.08)
                m = _round_rect(w, h, rr)
                outer = np.zeros((H, W), bool); outer[Y0:Y1, X0:X1] = m[:H - Y0, :W - X0][:Y1 - Y0, :X1 - X0]
                col = hexrgb(rims[k % len(rims)]) if rims else hexrgb(rim_colors[k % len(rim_colors)])
                rim_img = np.broadcast_to(col, (H, W, 3)).copy()
                ground[outer] = rim_img[outer]
                inner_m = ndimage.binary_erosion(outer, iterations=int(rim))
                _paint(ground, spec['ground'], inner_m, seed * 31 + k, H, W, box=(X0, Y0, X1, Y1))
                edge = outer & ~ndimage.binary_erosion(outer, iterations=3)
                ground[edge] *= 0.7
                lip = inner_m & ~ndimage.binary_erosion(inner_m, iterations=int(rim * 0.5))
                ground[lip] *= 0.78
                zm = np.asarray(Image.fromarray(inner_m.astype(np.uint8) * 255).resize((ww, hh), Image.NEAREST)) > 127
            labels[zm] = len(zones)
            zones.append(dict(spec=spec, mode='pack', mask=zm))
        return dict(ground=ground, labels=labels, zones=zones)

    if t == 'table':
        m = lay.get('margin', 0.08)
        shape = lay.get('shape', 'round')
        cx, cy = W / 2, H / 2
        rx = W * (0.5 - m)
        ry = rx if shape == 'round' else H * (0.5 - m * W / H)
        yy, xx = np.mgrid[0:H, 0:W]
        d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
        top = d < 1
        # shadow on the floor
        sh = ndimage.gaussian_filter((((xx - cx - 14) / rx) ** 2 + ((yy - cy - 22) / ry) ** 2 < 1).astype(np.float32), 18)
        ground *= (1 - 0.45 * sh)[..., None]
        _paint(ground, spec_for(0)['ground'], top, seed * 31, H, W)
        edge_w = lay.get('edge', 0.02) * W
        dist = ndimage.distance_transform_edt(top)
        e = top & (dist < edge_w)
        ground[e] = ground[e] * 0.72 + np.array([40, 22, 8], np.float32) * 0.0
        ground[top & (dist < 3)] *= 0.6
        prng = np.random.default_rng(seed + 9)
        im = Image.fromarray(ground.clip(0, 255).astype(np.uint8))
        dr = ImageDraw.Draw(im)
        np_ = lay.get('plates', 0)
        for k in range(np_):
            a = 2 * math.pi * k / max(1, np_) + prng.uniform(-0.1, 0.1)
            pr = min(rx, ry) * prng.uniform(0.13, 0.17)
            px = cx + math.cos(a) * (rx - pr * 1.7)
            py = cy + math.sin(a) * (ry - pr * 1.7)
            pc = tuple(int(v) for v in hexrgb(lay.get('plate', '#f4f1ea')))
            dr.ellipse([px - pr + 6, py - pr + 8, px + pr + 6, py + pr + 8], fill=(0, 0, 0))
            dr.ellipse([px - pr, py - pr, px + pr, py + pr], fill=tuple(int(v * 0.86) for v in pc))
            dr.ellipse([px - pr * 0.72, py - pr * 0.72, px + pr * 0.72, py + pr * 0.72], fill=pc)
        g2 = np.asarray(im, np.float32)
        ground[top] = g2[top]
        top_m = np.asarray(Image.fromarray(top.astype(np.uint8) * 255).resize((ww, hh), Image.NEAREST)) > 127
        top_m &= ndimage.distance_transform_edt(top_m) > edge_w / S
        labels[top_m] = 0
        zones.append(dict(spec=spec_for(0), mode='pack', mask=top_m))
        if len(zone_list) > 1:
            fl = np.asarray(Image.fromarray((~top).astype(np.uint8) * 255).resize((ww, hh), Image.NEAREST)) > 127
            fl &= ndimage.distance_transform_edt(fl) > 3
            labels[fl] = 1
            zones.append(dict(spec=spec_for(1), mode='pack', mask=fl))
        return dict(ground=ground, labels=labels, zones=zones)

    raise ValueError(f'unknown layout type {t}')


# ---------------------------------------------------------------------------------------------- placement

S = 4  # mask resolution: 1 mask pixel = S x S picture pixels


class Composer:
    """Greedy packer on a coarse occupancy grid (1 cell = S x S px). Each item goes where it overlaps least,
    prefers spots that touch other items (tight packing), and keeps to its zone."""
    contact_w = 0.12

    def __init__(self, lib, W, H, rng, banned=frozenset(), budget=10 ** 9):
        self.lib, self.W, self.H, self.rng = lib, W, H, rng
        self.budget = budget
        self.hh, self.ww = H // S, W // S
        self.cov = np.zeros((self.hh, self.ww), np.float32)
        self.placed = []          # (iid, img, x, y)
        self.used = set(banned)
        self.banned = set(banned)

    def item_mask(self, img):
        a = img.getchannel('A')
        w, h = max(1, round(img.size[0] / S)), max(1, round(img.size[1] / S))
        m = np.asarray(a.resize((w, h), Image.BILINEAR), np.float32) / 255.0
        m = (m > 0.35).astype(np.float32)
        pad = np.pad(m, 2)
        ring = ndimage.binary_dilation(pad, iterations=2).astype(np.float32) - pad
        return m, ring

    def full(self):
        return len(self.placed) >= self.budget

    def mark(self, iid, img, x, y):
        if self.full():
            return False
        m, _ = self.item_mask(img)
        y0, x0 = int(round(y / S)), int(round(x / S))
        h, w = m.shape
        ya, xa, yb, xb = max(0, y0), max(0, x0), min(self.hh, y0 + h), min(self.ww, x0 + w)
        if yb > ya and xb > xa:
            self.cov[ya:yb, xa:xb] = np.maximum(self.cov[ya:yb, xa:xb], m[ya - y0:yb - y0, xa - x0:xb - x0])
        self.placed.append((iid, img, int(x), int(y)))
        self.used.add(iid)
        return True

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
        ry0, rx0 = y0 - 2, x0 - 2
        rh, rw = ring.shape
        rya, rxa, ryb, rxb = max(0, ry0), max(0, rx0), min(self.hh, ry0 + rh), min(self.ww, rx0 + rw)
        rtot = ring.sum() + 1e-6
        rin = ring[rya - ry0:ryb - ry0, rxa - rx0:rxb - rx0]
        contact = float((rin * (self.cov[rya:ryb, rxa:rxb] > 0.5)).sum() / rtot)
        s = ov + 0.8 * max(0.0, out - 0.15) + 0.9 * max(0.0, 0.8 - zf) - self.contact_w * contact
        return s, ov, max(out, 1 - zf), (y0, x0)

    def candidates(self, zone_mask, k=30):
        free = self.cov < 0.5
        zone = free if zone_mask is None else (free & zone_mask)
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
        edge = np.flatnonzero(zone & ndimage.binary_dilation(~free, iterations=1))
        if edge.size:
            idx += list(self.rng.choice(edge, size=min(k // 2, edge.size), replace=False))
        idx = np.unique(np.asarray(idx))
        return [(i // self.ww, i % self.ww) for i in idx]

    def try_place(self, iid, long_px, zone_mask, max_ov, min_px, tries=3, at=None, max_out=0.3):
        if iid in self.used or self.full() or self.lib.max_long(iid) < min_px:
            return False      # a PNG-only item cannot be drawn larger than its export
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
            if ov <= max_ov and out <= max_out:
                h, w = m.shape
                ya, xa, yb, xb = max(0, y0), max(0, x0), min(self.hh, y0 + h), min(self.ww, x0 + w)
                self.cov[ya:yb, xa:xb] = np.maximum(self.cov[ya:yb, xa:xb], m[ya - y0:yb - y0, xa - x0:xb - x0])
                px, py = x0 * S + (w * S - img.size[0]) // 2, y0 * S + (h * S - img.size[1]) // 2
                self.placed.append((iid, img, px, py))
                self.used.add(iid)
                return True
            long_px = min(long_px, self.lib.max_long(iid)) * 0.82
            if long_px < min_px:
                return False
        return False

    def largest_hole(self, mask):
        free = self.cov < 0.5
        edt = ndimage.distance_transform_edt(free) * mask
        i = int(edt.argmax())
        return float(edt.ravel()[i]), (i // self.ww, i % self.ww)

    def coverage(self, mask=None):
        c = self.cov > 0.5
        if mask is None:
            return float(c.mean())
        return float(c[mask].mean()) if mask.any() else 1.0


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


def palette_order(lib, ids, palette, rng, max_dist=None, jitter=8.0, counts=None, use_w=10.0):
    """ids sorted by closeness to the palette (with a little noise) and by how often the pack used them
    already (use_w per earlier picture); max_dist drops colours far from the palette."""
    counts = counts or {}
    if not palette:
        return [i for _, i in sorted((counts.get(i, 0) * use_w + rng.uniform(0, jitter), i) for i in ids)]
    scored = [(lib.palette_dist(i, palette), i) for i in ids]
    if max_dist is not None:
        scored = [t for t in scored if t[0] <= max_dist]
    return [i for _, i in sorted((d + rng.uniform(0, jitter) + counts.get(i, 0) * use_w, i) for d, i in scored)]


def pack_row(comp, lib, cands, x0, x1, base, height, rng, rs, scale=1.0, lift=0.0, heroes=()):
    """Items standing on a line (shelf, floor), left to right. rs: dict(min, max, gap, min_frac)."""
    span = x1 - x0
    x = x0 + rng.uniform(0.0, 0.03) * span
    lo, hi = rs.get('min', 0.55), rs.get('max', 0.95)
    gmin, gmax = rs.get('gap', (-0.1, 0.06))
    min_frac = rs.get('min_frac', 0.32)
    queue = list(heroes) + [c for c in cands if c not in heroes]
    tries = 0
    while x < x1 - 0.03 * span and tries < 400:
        tries += 1
        queue = [c for c in queue if c not in comp.used]
        if not queue:
            break
        target = height * scale * rng.uniform(lo, hi)
        room = x1 - x
        pick = None
        for c in queue[:60]:
            hc = min(target, lib.max_h(c))
            wc = hc * lib.aspect(c)
            if hc >= target * 0.75 and wc <= room * 1.05 and hc >= height * scale * min_frac:
                pick = c
                break
        if pick is None:
            for c in queue[:120]:
                hc = min(target, lib.max_h(c))
                wc = hc * lib.aspect(c)
                if hc >= height * scale * min_frac and wc <= room * 1.05:
                    pick = c
                    break
        if pick is None:
            if room < 0.12 * span or comp.full():
                break
            target *= 0.8
            if target < height * scale * min_frac:
                break
            continue
        h = min(target, lib.max_h(pick))
        img = lib.image_h(pick, h)
        y = base - lift - img.size[1] + rng.uniform(0, 0.02) * height
        if not comp.mark(pick, img, x, y):
            break
        x += img.size[0] * (1 + rng.uniform(gmin, gmax))


def core_items(lib, pic):
    """Items a picture names in its zones (items and heroes): reserved for it against other pictures' filler."""
    out = set()
    for zs in pic['zones']:
        out.update(lib.select(zs['items'] + zs.get('hero', [])))
    return out


def compose(lib, pack, pic, W, H, seed, counts=None, reserved=None):
    global S
    S = int(pic.get('grid', pack.get('grid', 4)))     # occupancy-mask cell in px (6 for giant canvases)
    counts = counts or {}
    reserved = reserved or {}
    rng = np.random.default_rng(seed)
    cap = pack.get('max_uses', max(2, math.ceil(len(pack['pictures']) / 3)))
    banned = frozenset(k for k, v in counts.items() if v >= cap)
    budget = pic.get('max_items', pack.get('max_items', 10 ** 9))
    comp = Composer(lib, W, H, rng, banned, budget)
    lay = pic.get('layout', {'type': 'single'})
    st = build_structure(lay, pic['zones'], W, H, rng, seed)
    zones = st['zones']
    defaults = pack.get('defaults', {})
    palette = pic.get('palette')
    pal_max = pic.get('palette_max', defaults.get('palette_max', 42))

    core = core_items(lib, pic)
    core_kinds = {lib.kind[i] for i in core if i in lib.kind}

    def kind_ok(i, filler):
        k = lib.kind.get(i)
        if k is None:
            return True
        n = counts.get('kind:' + k, 0) + (reserved.get('kind:' + k, 0) if filler and k not in core_kinds else 0)
        return n < cap or (k in core_kinds and counts.get('kind:' + k, 0) < cap)

    def pool(sel, zpal=None, strict=False, filler=False):
        ids = [i for i in lib.select(sel) if i not in comp.used and kind_ok(i, filler)]
        if filler:      # keep items that later pictures still need for their own zones
            ids = [i for i in ids if counts.get(i, 0) + reserved.get(i, 0) < cap]
        p = zpal or palette
        if p and strict:
            return palette_order(lib, ids, p, rng, pal_max, counts=counts)
        return palette_order(lib, ids, None, rng, counts=counts, jitter=30.0)

    fill_ids = pool(pic.get('fill', []), strict=True, filler=True) if pic.get('fill') else []
    fill_all = pool(pack.get('fill_all', []), strict=True, filler=True) if pack.get('fill_all') and pic.get('fill_all', True) else []
    # 1. heroes and core items, zone by zone (row zones: back row first, then front row)
    for zi, z in enumerate(zones):
        zs = z['spec']
        zpal = zs.get('palette')
        heroes = [h for h in lib.select(zs.get('hero', [])) if h not in comp.used]
        core = pool(zs['items'], zpal, strict=bool(zs.get('palette_core')))
        if z['mode'] == 'row':
            rs = {**defaults.get('row', {}), **pic.get('row', {}), **zs.get('row', {})}
            extra = pool(zs.get('fill', []), zpal, strict=True, filler=True) + fill_ids + (fill_all if rs.get('fill_all') else [])
            for x0, x1, base, height in z['rows']:
                if rs.get('back', True):
                    pack_row(comp, lib, core + extra, x0, x1, base, height, rng, rs, scale=rs.get('back_scale', 0.8),
                             lift=height * rs.get('back_lift', 0.1))
                pack_row(comp, lib, core + extra, x0, x1, base, height, rng, rs, heroes=heroes)
            continue
        sz = {**defaults.get('size', {}), **zs.get('size', {})}
        min_px = sz.get('min_px', W * 0.03)
        target = zs.get('cover', pic.get('cover', defaults.get('cover', 0.8)))
        hsz = {**sz, **zs.get('hero_size', defaults.get('hero_size', {'min': sz.get('max', 0.2) * 1.1, 'max': sz.get('max', 0.2) * 1.5, 'power': 1.0}))}
        plan = [(i, size_for(lib, i, hsz, W, rng)) for i in heroes]
        plan.sort(key=lambda t: -t[1])
        rest = [(i, size_for(lib, i, sz, W, rng)) for i in core if i not in heroes]
        rest.sort(key=lambda t: -t[1])
        for iid, L in plan + rest:
            if comp.coverage(z['mask']) >= target:
                break
            comp.try_place(iid, L, z['mask'], zs.get('max_ov', defaults.get('max_ov', 0.16)), min_px)
    # 2. fill: always the largest hole among pack zones; an unused item of that zone (its items, its fill, the
    # picture's fill, then the pack's fill_all, palette-filtered) drawn at the hole's size (fill_size caps it)
    pack_mask = np.zeros_like(comp.cov, bool)
    for z in zones:
        if z['mode'] == 'pack':
            pack_mask |= z['mask']
    zone_cands = []
    for z in zones:
        zs = z['spec']
        if z['mode'] != 'pack':
            zone_cands.append([])
            continue
        zpal = zs.get('palette')
        zone_cands.append(list(dict.fromkeys(pool(zs['items'], zpal) + pool(zs.get('fill', []), zpal, strict=True, filler=True) + fill_ids + fill_all)))
    misses = 0
    lab = st['labels']
    all_pack = pack_mask.copy()
    hole_fail = {}
    while pack_mask.any() and misses < 400 and not comp.full():
        r, at = comp.largest_hole(pack_mask)
        zi = int(lab[at])
        if zi < 0 or zones[zi]['mode'] != 'pack':
            break
        zs = zones[zi]['spec']
        fc = zs.get('fill_cover', pic.get('fill_cover', defaults.get('fill_cover', 0.95)))
        if comp.coverage(zones[zi]['mask']) >= fc:
            pack_mask &= ~zones[zi]['mask']
            continue
        sz = {**defaults.get('size', {}), **zs.get('size', {})}
        fsz = {**sz, **defaults.get('fill_size', {}), **pic.get('fill_size', {}), **zs.get('fill_size', {})}
        min_fill = fsz.get('min_px', W * 0.035)
        if r * S * 2 < min_fill * 0.6:
            pack_mask &= ~zones[zi]['mask']
            continue
        cand = [i for i in zone_cands[zi] if i not in comp.used]
        zone_cands[zi] = cand
        if not cand:
            pack_mask &= ~zones[zi]['mask']
            continue
        want = min(max(r * S * 2.3, fsz.get('min', 0.05) * W), fsz.get('max', 0.14) * W)
        able = [i for i in cand[:120] if lib.max_long(i) >= want * 0.85]
        pick = able[0] if able else max(cand[:120], key=lib.max_long)
        L = min(want * rng.uniform(0.9, 1.1), lib.max_long(pick))
        ok = comp.try_place(pick, L, zones[zi]['mask'], zs.get('fill_ov', defaults.get('fill_ov', 0.3)), min_fill * 0.6, tries=3, at=at)
        if not ok:
            misses += 1
            cand.remove(pick)
            if L > min_fill:
                cand.append(pick)
            # a hole that keeps refusing items is left as ground: close it so the next hole gets its turn
            hole_fail[at] = hole_fail.get(at, 0) + 1
            if hole_fail[at] >= 4:
                yy, xx = np.ogrid[:comp.hh, :comp.ww]
                pack_mask &= ~(((yy - at[0]) ** 2 + (xx - at[1]) ** 2) <= max(2.0, r) ** 2)
    # 3. render: ground, then every item with a soft drop shadow, in placement order
    canvas = Image.fromarray(st['ground'].clip(0, 255).astype(np.uint8)).convert('RGBA')
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
    ids = [p[0] for p in comp.placed]
    return canvas.convert('RGB'), ids, comp.coverage(all_pack if all_pack.any() else None)


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


def cmd_render(args):
    """Pictures are composed in order; an item may appear in at most max_uses pictures of the pack
    (default: a third of them), so later pictures get the items earlier ones did not use."""
    pack, pf = load_pack(args.pack)
    lib = Library()
    pics = pack['pictures']
    cap = pack.get('max_uses', max(2, math.ceil(len(pics) / 3)))
    todo = [i for i, p in enumerate(pics) if not args.only or p['slug'] in args.only or str(i + 1) in args.only]
    counts = {}
    cores = {i: core_items(lib, p) for i, p in enumerate(pics)}
    pending = {}
    def keys(ids):      # an item and, once per picture, its kind
        return list(ids) + sorted({'kind:' + lib.kind[i] for i in ids if i in lib.kind})
    for i in todo:
        for iid in keys(cores[i]):
            pending[iid] = pending.get(iid, 0) + 1
    for i, p in enumerate(pics):        # pictures not rendered now keep their items
        mp = pic_path(pack, i, p).with_suffix('.json')
        if i not in todo and mp.exists():
            for iid in keys(json.loads(mp.read_text())['items']):
                counts[iid] = counts.get(iid, 0) + 1
    for name in [p.name for p in out_dir(pack).glob('*.png')]:
        if not any(name == pic_path(pack, i, p).name for i, p in enumerate(pics)) and re.match(r'\d\d-', name):
            (out_dir(pack) / name).unlink()          # a picture dropped from the pack definition
            (out_dir(pack) / name).with_suffix('.json').unlink(missing_ok=True)
    for i in sorted(todo, key=lambda k: -pics[k].get('priority', 0)):     # priority: rendered first, same file order
        pic = pics[i]
        W, H = pic.get('canvas', pack['canvas'])
        t0 = time.time()
        for iid in keys(cores[i]):
            pending[iid] -= 1
        img, ids, cov = compose(lib, pack, pic, W, H, pic.get('seed', 1000 + i), counts, pending)
        for iid in keys(ids):
            counts[iid] = counts.get(iid, 0) + 1
        p = pic_path(pack, i, pic)
        img.save(p, optimize=False, compress_level=6)
        meta = dict(slug=pic['slug'], title=pic['title'], items=ids, count=len(ids), coverage=round(cov, 3), size=[W, H])
        p.with_suffix('.json').write_text(json.dumps(meta, indent=0))
        print(f'  {p.name}: {len(ids)} items, coverage {cov:.2f}, {time.time() - t0:.0f}s', flush=True)
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:5]
    print(f'  max uses {cap}; most used: ' + ', '.join(f'{k} {v}' for k, v in top))


def pic_stats(path):
    sys.path.insert(0, str(REPO / 'tools' / 'content'))
    from cjw import imagecache as ic
    im = Image.open(path).convert('RGB')
    gray = im.convert('L')
    a = np.asarray(im.resize((128, 128), Image.BOX), np.int32) // 32
    hist = np.bincount((a[..., 0] * 64 + a[..., 1] * 8 + a[..., 2]).ravel(), minlength=512).astype(np.float64)
    hist /= hist.sum()
    return dict(phash='%016x' % ic.phash(gray), dhash='%016x' % ic.dhash(gray), mini=ic.mini(im), ok=True, hist=hist)


def cmd_similar(args):
    """Near-repeat check between all pictures of a pack: the content tool's similar() (phash, dhash, 4x4
    colour sketch) plus colour-histogram intersection (flagged >= --hist)."""
    sys.path.insert(0, str(REPO / 'tools' / 'content'))
    from cjw import imagecache as ic
    pack, _ = load_pack(args.pack)
    files = [(i, p, pic_path(pack, i, p)) for i, p in enumerate(pack['pictures'])]
    stats = {i: pic_stats(f) for i, p, f in files if f.exists()}
    rows, flagged = [], 0
    for a in stats:
        for b in stats:
            if b <= a:
                continue
            sim, why = ic.similar(stats[a], stats[b])
            hi = float(np.minimum(stats[a]['hist'], stats[b]['hist']).sum())
            md = ic.mini_dist(stats[a]['mini'], stats[b]['mini'])
            ph = ic.hamming(int(stats[a]['phash'], 16), int(stats[b]['phash'], 16))
            bad = sim or hi >= args.hist
            flagged += bad
            rows.append((hi, a, b, md, ph, why if sim else ('colour histogram' if bad else '')))
    rows.sort(reverse=True)
    for hi, a, b, md, ph, why in rows[:args.top]:
        print(f'  {a + 1:2d} {pack["pictures"][a]["slug"]:24s} {b + 1:2d} {pack["pictures"][b]["slug"]:24s} hist {hi:.2f} mini {md:5.1f} phash {ph:2d}  {why}')
    print(f'{flagged} flagged pairs of {len(rows)}')


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
    s = sub.add_parser('render'); s.add_argument('pack'); s.add_argument('--only', nargs='*')
    s = sub.add_parser('similar'); s.add_argument('pack'); s.add_argument('--hist', type=float, default=0.80); s.add_argument('--top', type=int, default=12)
    s = sub.add_parser('contact'); s.add_argument('pack'); s.add_argument('--crops', action='store_true')
    s = sub.add_parser('measure'); s.add_argument('pack')
    s = sub.add_parser('manifest'); s.add_argument('pack')
    a = ap.parse_args()
    dict(library=cmd_library, sheet=cmd_sheet, render=cmd_render, similar=cmd_similar, contact=cmd_contact, measure=cmd_measure, manifest=cmd_manifest)[a.cmd](a)


if __name__ == '__main__':
    main()
