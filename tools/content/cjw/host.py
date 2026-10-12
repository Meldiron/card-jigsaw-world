"""Self-hosting of every catalogue picture in Appwrite Storage (owner rule, 2026-10-13).

The app must never load a picture from a third party: each source image is downloaded once,
normalised to a JPEG of at most MAX_W px wide (MAX_H tall) and uploaded to the `puzzle-images`
bucket. Rows then point at our own endpoints:

  imageUrl  -> /view                       (full picture, the game decodes it)
  thumbUrl  -> /preview?width=THUMB_W      (grid tiles)
  coverUrl  -> /preview?width=COVER_W      (pack and event covers)

The original address is kept in `sourceUrl` (puzzles) / `coverSourceUrl` (packs, events) for
attribution, duplicate checks and rejects, which all key on the source URL.

File ids are derived from the source URL, so hosting is idempotent and a picture used by two
packs is stored once. `state/hosted.json` maps source URL -> file id (git-tracked).
"""
import hashlib, io, json, time, urllib.request, urllib.error, uuid
from PIL import Image, ImageOps
from .paths import ROOT, STATE
from .lock import locked
from . import api, imagecache

BUCKET = 'puzzle-images'
BASE = f'{api.ENDPOINT}/storage/buckets/{BUCKET}/files'
MAX_W, MAX_H, QUALITY = 1200, 2134, 86
THUMB_W, COVER_W = 600, 1080
HOSTED = STATE / 'hosted.json'
STORAGE_KEY = ROOT / 'secrets' / 'appwrite-storage-key.txt'
_key = None


def _headers(extra=None):
    global _key
    if _key is None:
        _key = STORAGE_KEY.read_text().strip()
    h = {'X-Appwrite-Project': api.PROJECT, 'X-Appwrite-Key': _key}
    if extra: h.update(extra)
    return h


def is_hosted(url):
    return bool(url) and url.startswith(BASE + '/')


def file_id_for(src):
    return 'p' + hashlib.sha1(src.encode()).hexdigest()[:35]


def view_url(fid): return f'{BASE}/{fid}/view?project={api.PROJECT}'
def thumb_url(fid): return f'{BASE}/{fid}/preview?project={api.PROJECT}&width={THUMB_W}&quality=80'
def cover_url(fid): return f'{BASE}/{fid}/preview?project={api.PROJECT}&width={COVER_W}&quality=82'


def file_id_of(hosted_url):
    """File id inside one of our URLs, else None."""
    if not is_hosted(hosted_url): return None
    return hosted_url[len(BASE) + 1:].split('/', 1)[0]


_map_cache = (None, {})   # (mtime, map): hosted.json is read once per change, not per lookup


def _load_map():
    global _map_cache
    try:
        mtime = HOSTED.stat().st_mtime
    except FileNotFoundError:
        return {}
    if _map_cache[0] != mtime:
        try: _map_cache = (mtime, json.loads(HOSTED.read_text()))
        except json.JSONDecodeError: return dict(_map_cache[1])
    return _map_cache[1]


def source_of(url):
    """Source URL behind one of our URLs (or the URL itself when it is not ours)."""
    fid = file_id_of(url)
    if not fid: return url
    for src, f in _load_map().items():
        if f == fid: return src
    return url


def _normalise(data):
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img).convert('RGB')
    w, h = img.size
    scale = min(1.0, MAX_W / w, MAX_H / h)
    if scale < 1.0:
        img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, 'JPEG', quality=QUALITY, optimize=True, progressive=True)
    return out.getvalue(), img.size


def _exists(fid):
    req = urllib.request.Request(f'{BASE}/{fid}', headers=_headers(), method='GET')
    try:
        with urllib.request.urlopen(req, timeout=30): return True
    except urllib.error.HTTPError as e:
        if e.code == 404: return False
        raise


def _upload(fid, jpeg):
    boundary = uuid.uuid4().hex
    body = b''.join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileId"\r\n\r\n{fid}\r\n'.encode(),
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{fid}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode(),
        jpeg, f'\r\n--{boundary}--\r\n'.encode()])
    for attempt in range(5):
        req = urllib.request.Request(BASE, data=body, method='POST',
                                     headers=_headers({'Content-Type': f'multipart/form-data; boundary={boundary}'}))
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors='replace')
            if e.code == 409: return {'$id': fid}          # already there (another process won the race)
            if e.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(3 * (attempt + 1)); continue
            raise RuntimeError(f'upload {fid} -> {e.code}: {text[:200]}')
        except (urllib.error.URLError, TimeoutError):
            if attempt < 4: time.sleep(3 * (attempt + 1)); continue
            raise


def _fetch(src):
    """Wikimedia downloads share the machine-wide pace (Commons throttles per client); other hosts
    (Flickr, iNaturalist, Picsum, museum CDNs) are fetched directly with a few retries."""
    if 'wikimedia.org' in src:
        return imagecache._download(src)[0]
    for attempt in range(4):
        req = urllib.request.Request(src, headers=imagecache.UA)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read(imagecache.MAX_BYTES + 1)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(4 * (attempt + 1)); continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 3: time.sleep(4 * (attempt + 1)); continue
            raise


def ensure(src):
    """Host `src` (a third-party URL) and return its file id. Idempotent and safe across processes."""
    if is_hosted(src):
        return file_id_of(src)
    m = _load_map()
    if src in m:
        return m[src]
    fid = file_id_for(src)
    if not _exists(fid):
        data = _fetch(src)
        jpeg, _size = _normalise(data)
        _upload(fid, jpeg)
    with locked('hosted'):
        m = dict(_load_map())
        m[src] = fid
        HOSTED.write_text(json.dumps(m, indent=0, sort_keys=True))
    return fid


def puzzle_urls(src):
    """Row fields for a puzzle picture whose source is `src`."""
    fid = ensure(src)
    return {'imageUrl': view_url(fid), 'thumbUrl': thumb_url(fid), 'sourceUrl': src}


def cover_fields(src):
    """Row fields for a pack or event cover whose source is `src` ('' clears it)."""
    if not src:
        return {'coverUrl': '', 'coverSourceUrl': ''}
    src = source_of(src)
    return {'coverUrl': cover_url(ensure(src)), 'coverSourceUrl': src}


def migrate(snap, pack=None, workers=4, dry=False):
    """Host every picture and cover that still points at a third party, and rewrite its row.
    Idempotent: rows already on our storage are skipped. Returns (updated, failures)."""
    from concurrent.futures import ThreadPoolExecutor, as_completed
    jobs = []   # (table, row id, source url, kind)
    for p in snap['puzzles']:
        if pack and p['packId'] != pack: continue
        if not is_hosted(p.get('hostedImageUrl') or '') or not p.get('sourceUrl'):
            jobs.append(('puzzles', p['$id'], p['imageUrl'], 'puzzle'))
    for table in ('packs', 'events'):
        for r in snap[table]:
            if pack and table == 'packs' and r['$id'] != pack: continue
            if pack and table == 'events': continue
            if r.get('coverUrl') and (not is_hosted(r.get('hostedCoverUrl') or '') or not r.get('coverSourceUrl')):
                jobs.append((table, r['$id'], r['coverUrl'], 'cover'))
    print(f'  {len(jobs)} rows to host ({sum(1 for j in jobs if j[3] == "puzzle")} pictures, {sum(1 for j in jobs if j[3] == "cover")} covers)')
    if dry: return 0, []
    done, failures = 0, []

    def work(job):
        table, rid, src, kind = job
        fields = puzzle_urls(src) if kind == 'puzzle' else cover_fields(src)
        api.update_row(table, rid, fields)
        return job

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(work, j): j for j in jobs}
        for f in as_completed(futs):
            j = futs[f]
            try:
                f.result(); done += 1
            except Exception as e:      # keep going; report at the end
                failures.append((j, str(e)[:160]))
            if (done + len(failures)) % 100 == 0:
                print(f'  {done + len(failures)}/{len(jobs)} ({len(failures)} failed)', flush=True)
    print(f'  hosted {done}, failed {len(failures)}')
    for (table, rid, src, kind), err in failures[:40]:
        print(f'   FAIL {table} {rid} {src[:80]} :: {err}')
    return done, failures
