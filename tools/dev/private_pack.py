"""Private packs: a hidden pack whose pictures sit in the private bucket `private-packs`.

  .venv/bin/python tools/dev/private_pack.py create --pack-id ID --name NAME --description TEXT \
      --author NAME --source TEXT [--source-url URL] [--category Giant] [--sort-order 1290] \
      [--max-px 4096] [--titles "Scene 1" "Scene 2" ...] FILE [FILE ...]
  .venv/bin/python tools/dev/private_pack.py delete --pack-id ID

A private pack is for pictures the game may not show publicly (an internal test of art we have not
licensed yet) and for special packs given out with pack codes. `create` writes:
- every FILE as a JPEG (at most --max-px on the long side, quality 90) into `private-packs` with NO
  permissions: only the server can read it until a player redeems one of the pack's codes (function
  `/code/redeem` on function `api` adds read(user) per claimant);
- one puzzle row per picture and a pack row with `hidden: true`, so the app lists the pack only for
  players who own it. Rows stay readable like every catalogue row (names and titles are public data),
  the pictures do not.
Then make a code: `tools/dev/pack_codes.py create --pack ID --uses N`.
`delete` removes the pack row, its puzzle rows and its files. Never put the source pictures in the
repo. Uses secrets/appwrite-users-key.txt (rows and files scopes); key values are never printed.
"""
import argparse, datetime, io, json, os, sys, time, urllib.error, urllib.request, uuid

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'content'))
from cjw_admin import Client, ENDPOINT, PROJECT, q  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402
from cjw import blurhash  # noqa: E402
from cjw.imagecache import accent_from  # noqa: E402

BUCKET = 'private-packs'
Image.MAX_IMAGE_PIXELS = None


def view_url(fid): return f'{ENDPOINT}/storage/buckets/{BUCKET}/files/{fid}/view?project={PROJECT}'
def thumb_url(fid): return f'{ENDPOINT}/storage/buckets/{BUCKET}/files/{fid}/preview?project={PROJECT}&width=600&quality=80'
def cover_url(fid): return f'{ENDPOINT}/storage/buckets/{BUCKET}/files/{fid}/preview?project={PROJECT}&width=1080&quality=82'


def jpeg_of(path, max_px):
    img = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    w, h = img.size
    if h < w:
        raise SystemExit(f'{path}: landscape ({w}x{h}); packs are portrait or square only')
    scale = min(1.0, max_px / max(w, h))
    if scale < 1.0:
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, 'JPEG', quality=90, optimize=True, progressive=True)
    return out.getvalue(), img


def upload(key, fid, data):
    """Uploads a file with no permissions (single request: files stay under 5 MB at 4096 px)."""
    if len(data) > 5 * 1024 * 1024:
        raise SystemExit(f'{fid}: {len(data)} bytes, over the single-request limit; lower --max-px')
    boundary = uuid.uuid4().hex
    body = b''.join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileId"\r\n\r\n{fid}\r\n'.encode(),
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{fid}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode(),
        data, f'\r\n--{boundary}--\r\n'.encode()])
    req = urllib.request.Request(f'{ENDPOINT}/storage/buckets/{BUCKET}/files', data=body, method='POST', headers={
        'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': key, 'Content-Type': f'multipart/form-data; boundary={boundary}'})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 409:
            return {'$id': fid}
        raise SystemExit(f'upload {fid} -> {e.code}: {e.read().decode(errors="replace")[:200]}')


def create(c, a):
    if c.row('packs', a.pack_id) is not None:
        raise SystemExit(f'pack {a.pack_id} exists; delete it first')
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    first = None
    for i, path in enumerate(a.files):
        fid = f'{a.pack_id}-{i + 1:02d}'[:36]
        data, img = jpeg_of(path, a.max_px)
        upload(c.key, fid, data)
        small = img.copy()
        small.thumbnail((400, 400))
        hashed = blurhash.encode(small)
        accent = accent_from(small)
        title = a.titles[i] if a.titles and i < len(a.titles) else f'Scene {i + 1}'
        c.call('POST', '/tablesdb/cjw/tables/puzzles/rows', body={'rowId': f'p-{fid}'[:36], 'data': {
            'packId': a.pack_id, 'title': title, 'imageUrl': view_url(fid), 'thumbUrl': thumb_url(fid),
            'author': a.author, 'source': a.source, 'sortOrder': i, 'accent': accent, 'blurhash': hashed,
            'sourceUrl': a.source_url}})
        print(f'  {fid}: {img.size[0]}x{img.size[1]}, {len(data) // 1024} KB, "{title}"')
        first = first or (fid, accent, hashed)
    fid, accent, hashed = first
    c.call('POST', '/tablesdb/cjw/tables/packs/rows', body={'rowId': a.pack_id, 'data': {
        'name': a.name, 'category': a.category, 'description': a.description, 'coverUrl': cover_url(fid),
        'priceCoins': 0, 'priceTickets': 0, 'isFree': False, 'isPremium': True, 'isSeasonal': False,
        'sortOrder': a.sort_order, 'imageCount': len(a.files), 'accent': accent, 'emoji': '', 'blurhash': hashed,
        'coverSourceUrl': a.source_url, 'puzzlesUpdatedAt': now, 'hidden': True,
        # App versions from before hidden packs list every released pack: a start date far ahead
        # makes them treat this one as an event that has not opened. The current app ignores it.
        'startAt': '2100-01-01T00:00:00.000+00:00'}})
    print(f'pack {a.pack_id} "{a.name}" ({a.category}, hidden, {len(a.files)} pictures in {BUCKET})')
    print(f'next: .venv/bin/python tools/dev/pack_codes.py create --pack {a.pack_id} --uses N')


def delete(c, a):
    for r in c.rows('puzzles', [q('equal', 'packId', [a.pack_id])]):
        c.delete_row('puzzles', r['$id'])
        fid = r['imageUrl'].split(f'/buckets/{BUCKET}/files/')[-1].split('/')[0]
        try:
            c.delete_file(BUCKET, fid)
        except Exception as e:  # noqa: BLE001
            print(f'  file {fid}: {e}')
    if c.row('packs', a.pack_id) is not None:
        c.delete_row('packs', a.pack_id)
    print(f'deleted pack {a.pack_id}')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    cr = sub.add_parser('create')
    cr.add_argument('--pack-id', required=True)
    cr.add_argument('--name', required=True)
    cr.add_argument('--description', required=True)
    cr.add_argument('--author', required=True)
    cr.add_argument('--source', required=True)
    cr.add_argument('--source-url')
    cr.add_argument('--category', default='Giant')
    cr.add_argument('--sort-order', type=int, default=1290)
    cr.add_argument('--max-px', type=int, default=4096)
    cr.add_argument('--titles', nargs='*')
    cr.add_argument('files', nargs='+')
    dl = sub.add_parser('delete')
    dl.add_argument('--pack-id', required=True)
    a = p.parse_args()
    c = Client()
    {'create': create, 'delete': delete}[a.cmd](c, a)


if __name__ == '__main__':
    main()
