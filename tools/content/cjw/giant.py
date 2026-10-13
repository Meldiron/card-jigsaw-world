"""Checks for Giant packs (category Giant: boards of about 100 to 300 cards).

A giant picture is cut into up to ~300 cards, each about 200 px of the hosted 4096 px copy, so it must
be sharp at 100% and carry detail and colour in every card. `run.sh giantcheck PACK` downloads each
candidate (or puzzle) at its full rendition, scales it to the spec's host_max_px exactly as hosting
will, and measures:

  long      long side of the source rendition (want >= GIANT_MIN_LONG, about 4000)
  sharp     high-frequency energy at hosted size: mean |img - blur(img)| on the luminance, 0-255.
            Real detail scores high; upscaled or soft scans score low (want >= GIANT_MIN_SHARP)
  flat      share of cards at the 300-card cut that are almost uniform (luminance std < 6)
  dark      share of cards that are nearly black (mean luminance < 28)
  alike     share of cards whose colour and texture match 8 or more other cards (repeating pattern,
            plain background): those cards cannot be told apart

and writes a 100% crop sheet per item (four 512 px crops of the hosted copy) to
<cache>/sheets/giant/<pack>/<key>.png for the visual sharpness check. Results are cached per URL.
"""
import io, json
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageOps
from .paths import CACHE
from . import imagecache, host, sheet

GIANT_MIN_LONG = 3800      # source rendition long side (Commons' largest standard step is 3840)
GIANT_MIN_SHARP = 1.8      # sharp museum scan 2.8, the same scan upscaled 3x 0.98 (calibrated 2026-10-14)
GIANT_MAX_FLAT = 0.22      # about a fifth of the board may be sky or plain wall (calibrated on Colourful Houses)
GIANT_MAX_DARK = 0.15
GIANT_MAX_ALIKE = 0.30
CARDS = 300

STATS = CACHE / 'giant'
STATS.mkdir(parents=True, exist_ok=True)


def grid_for(w, h, cards=CARDS):
    """Columns and rows of about `cards` near-square cards for a w x h picture."""
    cols = max(1, round((cards * w / h) ** 0.5))
    rows = max(1, round(cards / cols))
    return cols, rows


def _hosted(img, max_px):
    w, h = img.size
    scale = min(1.0, max_px / max(w, h))
    if scale < 1.0:
        img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    return img


def measure(img, max_px=4096):
    """Stats dict for a PIL image (see the module doc)."""
    img = _hosted(ImageOps.exif_transpose(img).convert('RGB'), max_px)
    w, h = img.size
    gray = img.convert('L')
    g = np.asarray(gray, dtype=np.float32)
    blur = np.asarray(gray.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32)
    sharp = float(np.abs(g - blur).mean())
    cols, rows = grid_for(w, h)
    cw, ch = w // cols, h // rows
    a = np.asarray(img, dtype=np.float32)
    feats, flat, dark = [], 0, 0
    for r in range(rows):
        for c in range(cols):
            cell = a[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
            lum = cell.mean(axis=2)
            std = float(lum.std()); mean = float(lum.mean())
            if std < 6: flat += 1
            if mean < 28: dark += 1
            feats.append([*cell.reshape(-1, 3).mean(axis=0), std])
    f = np.asarray(feats, dtype=np.float32)
    d = np.sqrt(((f[:, None, :] - f[None, :, :]) ** 2).sum(axis=2))
    alike = float(((d < 10).sum(axis=1) - 1 >= 8).mean())
    n = cols * rows
    return dict(w=w, h=h, cols=cols, rows=rows, sharp=round(sharp, 2), flat=round(flat / n, 3),
                dark=round(dark / n, 3), alike=round(alike, 3))


def crops(img, max_px=4096, size=512):
    """Four 100% crops (centre, and the centres of three quadrants) of the hosted copy, side by side."""
    img = _hosted(ImageOps.exif_transpose(img).convert('RGB'), max_px)
    w, h = img.size
    spots = [(0.5, 0.5), (0.25, 0.25), (0.75, 0.4), (0.4, 0.8)]
    out = Image.new('RGB', (size * 2 + 6, size * 2 + 6), (250, 250, 250))
    for i, (fx, fy) in enumerate(spots):
        x = int(min(max(0, fx * w - size / 2), w - size)); y = int(min(max(0, fy * h - size / 2), h - size))
        out.paste(img.crop((x, y, x + size, y + size)), ((i % 2) * (size + 6), (i // 2) * (size + 6)))
    return out


def check(url, max_px=4096, force=False, crop_path=None):
    """Stats for one source URL (cached by URL and size); writes the crop sheet when crop_path is given."""
    sp = STATS / f'{imagecache.key_for(url)}-{max_px}.json'
    if sp.exists() and not force and (crop_path is None or crop_path.exists()):
        return json.loads(sp.read_text())
    try:
        data = host._fetch(url)
        img = Image.open(io.BytesIO(data)); img.load()
    except Exception as e:
        st = {'ok': False, 'err': str(e)[:120]}
        sp.write_text(json.dumps(st)); return st
    st = dict(ok=True, src_w=img.size[0], src_h=img.size[1], bytes=len(data), **measure(img, max_px))
    st['long'] = max(st['src_w'], st['src_h'])
    if crop_path is not None:
        crop_path.parent.mkdir(parents=True, exist_ok=True)
        cr = crops(img, max_px)
        ImageDraw.Draw(cr).text((8, 8), f"{st['src_w']}x{st['src_h']} sharp {st['sharp']}", fill=(255, 255, 0), font=sheet.font(18))
        cr.save(crop_path, 'PNG', optimize=True)
    sp.write_text(json.dumps(st))
    return st


def prescreen(thumb_path):
    """Card measures (flat / dark / alike) on a cached 480 px thumbnail: no download, rough (fine
    texture is lost, so flat and alike read high). Use it to drop hopeless candidates before
    `check` downloads the full renditions."""
    return measure(Image.open(thumb_path), max_px=10_000)


def review_sheets(items, out_dir):
    """2 x 2 sheets of each (key, url, title) at about 700 x 1050 for the people / text check that the
    480 px contact sheet cannot do (passers-by, reflections in glass, statues, faces on murals).
    Commons pictures come as 1280 px renditions to save bandwidth. Returns the sheet paths."""
    from . import sources
    out_dir.mkdir(parents=True, exist_ok=True)
    ims = []
    for key, url, title in items:
        src = sources.commons_rendition(url, 1280) if 'upload.wikimedia.org' in url else url
        try:
            im = Image.open(io.BytesIO(host._fetch(src))).convert('RGB')
        except Exception as e:
            print(f'  review: {key} could not be read ({str(e)[:60]})'); continue
        im.thumbnail((700, 1050), Image.LANCZOS)
        ims.append((key, title, im))
    paths = []
    for s in range(0, len(ims), 4):
        sh = Image.new('RGB', (1420, 2140), (255, 255, 255)); d = ImageDraw.Draw(sh)
        for i, (key, title, im) in enumerate(ims[s:s + 4]):
            x, y = (i % 2) * 710, (i // 2) * 1070
            sh.paste(im, (x, y + 20)); d.text((x + 4, y), f'{key} {title[:60]}', fill=(0, 0, 0), font=sheet.font(16))
        p = out_dir / f'review-{s // 4 + 1}.png'
        sh.save(p, 'PNG', optimize=True); paths.append(p)
    return paths


def verdict(st):
    """Reasons a picture fails the giant rules ('' when it passes the measurable ones)."""
    if not st.get('ok'): return 'unreadable ' + st.get('err', '')
    why = []
    if st['long'] < GIANT_MIN_LONG: why.append(f"long side {st['long']} < {GIANT_MIN_LONG}")
    if st['src_w'] > st['src_h']: why.append('landscape')
    if st['sharp'] < GIANT_MIN_SHARP: why.append(f"soft (sharp {st['sharp']})")
    if st['flat'] > GIANT_MAX_FLAT: why.append(f"flat cards {st['flat']:.0%}")
    if st['dark'] > GIANT_MAX_DARK: why.append(f"dark cards {st['dark']:.0%}")
    if st['alike'] > GIANT_MAX_ALIKE: why.append(f"look-alike cards {st['alike']:.0%}")
    return '; '.join(why)
