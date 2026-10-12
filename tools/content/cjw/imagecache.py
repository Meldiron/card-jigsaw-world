"""Download images once, keep a small thumbnail + measurements (size, dHash, pHash, colour, blurhash)."""
import hashlib, io, json, math, time, urllib.request, urllib.error, colorsys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image, ImageFile
from .paths import CACHE
from . import blurhash

ImageFile.LOAD_TRUNCATED_IMAGES = True
UA = {'User-Agent': 'CardJigsawWorld/1.0 (content tooling; contact matej@appwrite.io)'}
THUMB = 480
MAX_BYTES = 40 * 1024 * 1024

def key_for(url):
    return hashlib.sha1(url.encode()).hexdigest()[:16]

def meta_path(url): return CACHE / 'meta' / (key_for(url) + '.json')
def thumb_path(url): return CACHE / 'thumbs' / (key_for(url) + '.jpg')

def load_meta(url):
    p = meta_path(url)
    return json.loads(p.read_text()) if p.exists() else None

PACE = 0.7    # seconds between download starts across ALL worker processes on this machine
_PACE_FILE = CACHE / '.fetch-pace'

def _pace():
    """Cross-process spacing of download starts: Commons renders uncached thumbnails on demand and
    throttles per client, so eight workers must share one token stream instead of each retrying."""
    import fcntl
    with (CACHE / '.fetch-pace.lock').open('w') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            try: last = float(_PACE_FILE.read_text() or 0)
            except Exception: last = 0.0
            now = time.time()
            start = max(now, last + PACE)
            _PACE_FILE.write_text(repr(start))
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)
    delay = start - time.time()
    if delay > 0: time.sleep(delay)

def _download(url, timeout=45):
    """GET with cross-process pacing and 429 handling (honours Retry-After, up to 5 attempts)."""
    for attempt in range(5):
        _pace()
        req = urllib.request.Request(url, headers=UA)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                ct = r.headers.get('Content-Type', '')
                data = r.read(MAX_BYTES + 1)
                if len(data) > MAX_BYTES:
                    raise ValueError('too large')
                return data, ct, r.geturl()
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 4:
                try: delay = float(e.headers.get('Retry-After', '15'))
                except ValueError: delay = 15.0
                time.sleep(min(max(delay, 5.0), 60.0) + attempt * 5)
                continue
            raise

def dhash(gray):
    small = np.asarray(gray.resize((9, 8), Image.LANCZOS), dtype=np.float32)
    bits = (small[:, 1:] > small[:, :-1]).flatten()
    return int(''.join('1' if b else '0' for b in bits), 2)

_DCT = None
def _dct_matrix(n=32):
    global _DCT
    if _DCT is None:
        m = np.zeros((n, n), dtype=np.float64)
        for k in range(n):
            for i in range(n):
                m[k, i] = math.cos(math.pi * (2 * i + 1) * k / (2 * n))
        _DCT = m
    return _DCT

def phash(gray):
    a = np.asarray(gray.resize((32, 32), Image.LANCZOS), dtype=np.float64)
    m = _dct_matrix()
    d = m @ a @ m.T
    low = d[:8, :8].flatten()[1:]
    med = np.median(low)
    return int(''.join('1' if v > med else '0' for v in low), 2)

def hamming(a, b):
    return bin(a ^ b).count('1')

def mini(img):
    """4x4 RGB colour sketch (used for 'same scene, same palette' similarity)."""
    a = np.asarray(img.convert('RGB').resize((4, 4), Image.BOX), dtype=np.uint8)
    return a.flatten().tolist()

def mini_dist(a, b):
    a = np.asarray(a, dtype=np.float32); b = np.asarray(b, dtype=np.float32)
    return float(np.sqrt(((a - b) ** 2).mean()))

def flatness(img):
    """Share of the image that is almost uniform (low local contrast). High values = big flat areas."""
    g = np.asarray(img.convert('L').resize((64, 64), Image.LANCZOS), dtype=np.float32)
    blocks = g.reshape(8, 8, 8, 8).std(axis=(1, 3))
    return float((blocks < 6).mean())

def entropy(img):
    g = np.asarray(img.convert('L').resize((128, 128), Image.LANCZOS), dtype=np.uint8)
    hist = np.bincount(g.flatten(), minlength=256).astype(np.float64)
    p = hist / hist.sum(); p = p[p > 0]
    return float(-(p * np.log2(p)).sum())

def accent_from(img):
    """Dominant saturated hue -> usable accent colour (#RRGGBB)."""
    a = np.asarray(img.convert('RGB').resize((64, 64), Image.LANCZOS), dtype=np.float32) / 255.0
    r, g, b = a[..., 0].flatten(), a[..., 1].flatten(), a[..., 2].flatten()
    mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    v = mx
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.maximum(d, 1e-6), 0); gc = np.where(m, (mx - g) / np.maximum(d, 1e-6), 0); bc = np.where(m, (mx - b) / np.maximum(d, 1e-6), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2 + rc - bc, 4 + gc - rc)); h = (h / 6) % 1
    mask = (s > 0.28) & (v > 0.18) & (v < 0.97)
    if mask.sum() < 40:
        mask = (s > 0.12) & (v > 0.12)
    if mask.sum() < 20:
        # neutral image: slate accent
        return '#475569'
    hh = h[mask]
    bins = np.bincount((hh * 24).astype(int) % 24, minlength=24)
    top = int(bins.argmax())
    sel = ((hh * 24).astype(int) % 24) == top
    hue = float(np.median(hh[sel]))
    sat = float(np.clip(np.median(s[mask][sel]), 0.5, 0.78))
    val = float(np.clip(np.median(v[mask][sel]), 0.55, 0.82))
    rr, gg, bb = colorsys.hsv_to_rgb(hue, sat, val)
    return '#%02X%02X%02X' % (int(rr * 255), int(gg * 255), int(bb * 255))

def fetch(url, force=False):
    """Return meta dict for url (cached). meta['ok'] False with 'err' when the image is unusable."""
    mp = meta_path(url)
    if mp.exists() and not force:
        m = json.loads(mp.read_text())
        if m.get('ok') or (m.get('tries', 1) >= 2 and not str(m.get('err', '')).startswith(('http 429', 'http 503'))):
            return m
    meta = {'url': url, 'ok': False, 'at': time.strftime('%Y-%m-%dT%H:%M:%S')}
    prev = json.loads(mp.read_text()) if mp.exists() else {}
    meta['tries'] = prev.get('tries', 0) + 1
    try:
        data, ct, final = _download(url)
        if 'images-assets.nasa.gov' in url and not ct.startswith('image/'):
            raise ValueError('nasa non-image')
        img = Image.open(io.BytesIO(data))
        img.load()
        w, h = img.size
        rgb = img.convert('RGB')
        gray = rgb.convert('L')
        meta.update(ok=True, w=w, h=h, bytes=len(data), mime=ct.split(';')[0],
                    dhash='%016x' % dhash(gray), phash='%016x' % phash(gray), mini=mini(rgb),
                    flat=round(flatness(rgb), 3), entropy=round(entropy(rgb), 2),
                    accent=accent_from(rgb), blurhash=blurhash.encode(rgb.copy()))
        t = rgb.copy(); t.thumbnail((THUMB, THUMB), Image.LANCZOS)
        t.save(thumb_path(url), 'JPEG', quality=82)
    except urllib.error.HTTPError as e:
        meta['err'] = f'http {e.code}'
        if e.code in (429, 503): meta['tries'] = 0      # throttled: never treat as a permanent failure
        if 'images-assets.nasa.gov' in url and '~medium' in url and e.code in (403, 404):
            alt = fetch(url.replace('~medium.jpg', '~orig.jpg'), force)
            if alt.get('ok'):
                meta.update(alt); meta['url'] = url; meta['redirect'] = alt['url']; meta['ok'] = True
                import shutil; shutil.copy(thumb_path(alt['url']), thumb_path(url))
    except Exception as e:
        meta['err'] = str(e)[:120]
    mp.write_text(json.dumps(meta))
    return meta

def fetch_many(urls, workers=3, progress=None):
    out = {}
    urls = list(dict.fromkeys(urls))
    with ThreadPoolExecutor(workers) as ex:
        for i, m in enumerate(ex.map(fetch, urls)):
            out[m['url']] = m
            if progress and i % progress == 0:
                print(f'  fetched {i}/{len(urls)}', flush=True)
    return out

def similar(m1, m2):
    """Near-duplicate / same-scene score. Returns (is_similar, reason)."""
    if not (m1 and m2 and m1.get('ok') and m2.get('ok')):
        return False, ''
    ph = hamming(int(m1['phash'], 16), int(m2['phash'], 16))
    dh = hamming(int(m1['dhash'], 16), int(m2['dhash'], 16))
    md = mini_dist(m1['mini'], m2['mini'])
    if ph <= 8 or dh <= 6:
        return True, f'near-duplicate (phash {ph}, dhash {dh})'
    if ph <= 14 and md < 22:
        return True, f'same scene (phash {ph}, colour {md:.0f})'
    if md < 9:
        return True, f'same palette and layout (colour {md:.0f}, phash {ph})'
    return False, ''
