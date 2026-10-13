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

Giant packs (category Giant, 100-300 card boards) keep far more pixels: a spec with
`"host_max_px": 4096` stores its pictures at up to that many px on the long side (JPEG quality
GIANT_QUALITY) instead of MAX_W. Such a copy gets its own file id and map key (`<source>|4096px`),
so a picture hosted at 1200 px for another pack is never reused at the wrong size.
"""
import hashlib, io, json, re, time, urllib.request, urllib.error, uuid
from PIL import Image, ImageOps
from .paths import ROOT, STATE
from .lock import locked
from . import api, imagecache

BUCKET = 'puzzle-images'
BASE = f'{api.ENDPOINT}/storage/buckets/{BUCKET}/files'
MAX_W, MAX_H, QUALITY = 1200, 2134, 86
GIANT_QUALITY = 90
THUMB_W, COVER_W = 600, 1080
HOSTED = STATE / 'hosted.json'
STORAGE_KEY = ROOT / 'secrets' / 'appwrite-storage-key.txt'
# The QA purge key (users, rows, files scopes) can host too when the storage key is not on this machine.
FALLBACK_KEY = ROOT / 'secrets' / 'appwrite-users-key.txt'
_key = None


def _read_key():
    if STORAGE_KEY.exists():
        return STORAGE_KEY.read_text().strip()
    if FALLBACK_KEY.exists():
        print('  host: secrets/appwrite-storage-key.txt is missing; using secrets/appwrite-users-key.txt '
              '(files.read/files.write). Restore the storage key to stop this fallback.', flush=True)
        return FALLBACK_KEY.read_text().strip()
    raise SystemExit('missing secrets/appwrite-storage-key.txt (an API key with files.read, files.write)')


def _headers(extra=None):
    global _key
    if _key is None:
        _key = _read_key()
    h = {'X-Appwrite-Project': api.PROJECT, 'X-Appwrite-Key': _key}
    if extra: h.update(extra)
    return h


def is_hosted(url):
    return bool(url) and url.startswith(BASE + '/')


def map_key(src, max_px=None):
    """hosted.json key: the source URL, plus the size for a giant copy."""
    return f'{src}|{int(max_px)}px' if max_px else src


def _source_of_key(key):
    return re.sub(r'\|\d+px$', '', key)


def file_id_for(src, max_px=None):
    return 'p' + hashlib.sha1(map_key(src, max_px).encode()).hexdigest()[:35]


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
        if f == fid: return _source_of_key(src)
    return url


def _normalise(data, max_px=None):
    """JPEG of at most MAX_W x MAX_H, or (giant packs) at most max_px on the long side."""
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img).convert('RGB')
    w, h = img.size
    scale = min(1.0, max_px / max(w, h)) if max_px else min(1.0, MAX_W / w, MAX_H / h)
    if scale < 1.0:
        img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, 'JPEG', quality=GIANT_QUALITY if max_px else QUALITY, optimize=True, progressive=True)
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
    if 'images-assets.nasa.gov' in src and '~medium.' in src:
        # NASA refuses some ~medium renditions (403); the large and original files work
        for alt in (src, src.replace('~medium.', '~large.'), src.replace('~medium.', '~orig.')):
            try: return _fetch_direct(alt)
            except urllib.error.HTTPError as e:
                if e.code not in (403, 404): raise
        raise RuntimeError(f'no NASA rendition for {src}')
    return _fetch_direct(src)


def _fetch_direct(src):
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


def ensure(src, max_px=None):
    """Host `src` (a third-party URL) and return its file id. Idempotent and safe across processes.
    max_px (giant packs) stores a larger copy under its own id."""
    if is_hosted(src):
        return file_id_of(src)
    key = map_key(src, max_px)
    m = _load_map()
    if key in m:
        return m[key]
    fid = file_id_for(src, max_px)
    if not _exists(fid):
        data = _fetch(src)
        jpeg, size = _normalise(data, max_px)
        _upload(fid, jpeg)
        if max_px:
            print(f'  hosted {fid} at {size[0]}x{size[1]} ({len(jpeg) / 1e6:.1f} MB)', flush=True)
    with locked('hosted'):
        m = dict(_load_map())
        m[key] = fid
        HOSTED.write_text(json.dumps(m, indent=0, sort_keys=True))
    return fid


def puzzle_urls(src, max_px=None):
    """Row fields for a puzzle picture whose source is `src` (max_px: giant packs, see the module doc)."""
    fid = ensure(src, max_px)
    return {'imageUrl': view_url(fid), 'thumbUrl': thumb_url(fid), 'sourceUrl': src}


def cover_fields(src):
    """Row fields for a pack or event cover whose source is `src` ('' clears it)."""
    if not src:
        return {'coverUrl': '', 'coverSourceUrl': ''}
    src = source_of(src)
    return {'coverUrl': cover_url(ensure(src)), 'coverSourceUrl': src}


def _pack_sizes(snap):
    """pack id -> host_max_px of its spec (giant packs only)."""
    from . import specs
    out = {}
    for p in snap['packs']:
        try:
            if specs.spec_path(p['$id']).exists():
                px = specs.load(p['$id']).get('host_max_px')
                if px: out[p['$id']] = int(px)
        except SystemExit:
            pass
    return out


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

    sizes = _pack_sizes(snap)
    pack_of = {p['$id']: p['packId'] for p in snap['puzzles']}

    def work(job):
        table, rid, src, kind = job
        if kind == 'puzzle':
            fields = puzzle_urls(src, sizes.get(pack_of.get(rid)))
        else:
            fields = cover_fields(src)
        api.update_row(table, rid, fields)
        return job

    # Wikimedia throttles this machine per client, so its pictures go one at a time on their own
    # stream; everything else (Flickr, iNaturalist, Picsum, museum CDNs) runs in parallel.
    wiki = [j for j in jobs if 'wikimedia.org' in j[2]]
    rest = [j for j in jobs if 'wikimedia.org' not in j[2]]
    print(f'  {len(rest)} from other hosts in parallel, {len(wiki)} from Wikimedia one at a time', flush=True)
    with ThreadPoolExecutor(max_workers=workers) as ex, ThreadPoolExecutor(max_workers=1) as wx:
        futs = {ex.submit(work, j): j for j in rest}
        futs.update({wx.submit(work, j): j for j in wiki})
        for f in as_completed(futs):
            j = futs[f]
            try:
                f.result(); done += 1
            except Exception as e:      # keep going; report at the end
                failures.append((j, str(e)[:160]))
            if (done + len(failures)) % 50 == 0:
                print(f'  {done + len(failures)}/{len(jobs)} ({len(failures)} failed)', flush=True)
    print(f'  hosted {done}, failed {len(failures)}')
    for (table, rid, src, kind), err in failures[:40]:
        print(f'   FAIL {table} {rid} {src[:80]} :: {err}')
    return done, failures
