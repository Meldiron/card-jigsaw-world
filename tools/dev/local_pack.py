"""Publish a pack of locally made or locally picked pictures (composed collages, film-frame crops,
crops of finished game paintings) the same way the content tool publishes its picks.

  .venv/bin/python tools/dev/local_pack.py check MANIFEST.json      # validate, print what would happen
  .venv/bin/python tools/dev/local_pack.py publish MANIFEST.json
  .venv/bin/python tools/dev/local_pack.py delete --pack-id PACK_ID

MANIFEST.json:
  {"pack": {"id": "pack-...", "name": "...", "category": "Food", "description": "...", "sortOrder": 1300,
            "price": "coins" | "tickets" | "free", "premium": false},
   "pictures": [{"file": "/abs/path.png", "title": "...", "author": "...", "licence": "CC0",
                 "source": "Tiny Speck (Glitch), CC0", "page": "https://...", "changes": "composed from 214 items"}]}

Category `Giant` hosts each picture at up to 4096 px on the long side (quality 90); every other category
at most 1200 x 2134 (quality 86), like `host.py`. Pictures must be portrait or square, at least 900 px on
the short side (3800 px on the long side for Giant). `publish` uploads to `puzzle-images`, creates the
pack row (400 coins or 3 tickets, as the content tool does: run tools/store/apply_pack_prices.py --only
PACK after), the puzzle rows, sets `puzzlesUpdatedAt`, and records provenance (provider `local`, with
the changes note) and a change-log line. The picture files themselves never go into the repo.
"""
import argparse, datetime, hashlib, io, json, os, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CONTENT = os.path.join(ROOT, 'tools', 'content')
CALLER_DIR = os.getcwd()          # manifest paths are relative to where the command was run
sys.path.insert(0, CONTENT)
os.chdir(CONTENT)
from PIL import Image, ImageOps  # noqa: E402
from cjw import api, host, state, blurhash  # noqa: E402
from cjw.imagecache import accent_from  # noqa: E402
from cjw.writer import puzzle_id_for  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
GIANT_MAX, GIANT_MIN_LONG = 4096, 3800


def load(path):
    m = json.load(open(os.path.join(CALLER_DIR, path)))
    pack, pics = m['pack'], m['pictures']
    for key in ('id', 'name', 'category', 'description'):
        if not pack.get(key):
            raise SystemExit(f'pack.{key} missing')
    if len(pics) < 20:
        raise SystemExit(f'{len(pics)} pictures: a pack needs at least 20 (content rules)')
    giant = pack['category'] == 'Giant'
    for i, p in enumerate(pics):
        for key in ('file', 'title', 'author', 'licence', 'source'):
            if not p.get(key):
                raise SystemExit(f'picture {i + 1}: {key} missing')
        with Image.open(p['file']) as im:
            w, h = ImageOps.exif_transpose(im).size
        if h < w:
            raise SystemExit(f"{p['file']}: landscape {w}x{h} (portrait or square only)")
        if min(w, h) < 900:
            raise SystemExit(f"{p['file']}: {w}x{h}, short side under 900 px")
        if giant and max(w, h) < GIANT_MIN_LONG:
            raise SystemExit(f"{p['file']}: {w}x{h}, a Giant picture needs {GIANT_MIN_LONG} px on the long side")
        p['_size'] = (w, h)
    return pack, pics, giant


def exists(table, row_id):
    try:
        api.get_row(table, row_id)
        return True
    except RuntimeError as e:
        if '-> 404' in str(e):
            return False
        raise


def jpeg(path, giant):
    img = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    w, h = img.size
    scale = min(1.0, GIANT_MAX / max(w, h)) if giant else min(1.0, host.MAX_W / w, host.MAX_H / h)
    if scale < 1.0:
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, 'JPEG', quality=host.GIANT_QUALITY if giant else host.QUALITY, optimize=True, progressive=True)
    return out.getvalue(), img


def check(args):
    pack, pics, giant = load(args.manifest)
    print(f"{pack['id']} \"{pack['name']}\" ({pack['category']}{', giant 4096 px' if giant else ''}): {len(pics)} pictures")
    for p in pics:
        print(f"  {p['_size'][0]}x{p['_size'][1]}  {p['title']}  ·  {p['author']}  ·  {p['licence']}")


def publish(args):
    pack, pics, giant = load(args.manifest)
    pid_pack = pack['id']
    if exists('packs', pid_pack):
        raise SystemExit(f'pack {pid_pack} exists: delete it first, or change the id')
    first = None
    for i, p in enumerate(pics):
        data, img = jpeg(p['file'], giant)
        fid = 'l' + hashlib.sha1(pid_pack.encode() + b'|' + data).hexdigest()[:31]
        host._upload(fid, data)
        small = img.copy()
        small.thumbnail((400, 400))
        accent, hashed = accent_from(small), blurhash.encode(small)
        src = f'local:{pid_pack}/{os.path.basename(p["file"])}'
        pid = puzzle_id_for(src, pid_pack)
        api.create_row('puzzles', {
            'packId': pid_pack, 'title': p['title'][:128], 'imageUrl': host.view_url(fid), 'thumbUrl': host.thumb_url(fid),
            'author': p['author'][:128], 'source': p['source'][:128], 'sortOrder': i, 'accent': accent, 'blurhash': hashed,
            'sourceUrl': p.get('page') or src}, row_id=pid)
        state.add_provenance(pid, dict(url=host.view_url(fid), author=p['author'], licence=p['licence'], source=p['source'],
                                       page=p.get('page', ''), provider='local', packId=pid_pack, changes=p.get('changes', ''),
                                       file=os.path.basename(p['file']), at=time.strftime('%Y-%m-%d')))
        print(f"  {i + 1:>2}. {img.size[0]}x{img.size[1]} {len(data) // 1024} KB  {p['title']}")
        first = first or (fid, accent, hashed, p)
    fid, accent, hashed, p0 = first
    price = pack.get('price', 'coins')
    api.create_row('packs', {
        'name': pack['name'][:64], 'category': pack['category'][:32], 'description': pack['description'][:256],
        'coverUrl': host.cover_url(fid), 'priceCoins': 400 if price == 'coins' else 0, 'priceTickets': 3 if price == 'tickets' else 0,
        'isFree': price == 'free', 'isPremium': bool(pack.get('premium', False)), 'isSeasonal': False,
        'sortOrder': int(pack.get('sortOrder', 500)), 'imageCount': len(pics), 'accent': accent, 'emoji': '', 'blurhash': hashed,
        'coverSourceUrl': p0.get('page') or '', 'puzzlesUpdatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()},
        row_id=pid_pack)
    state.log('local-pack', pack=pid_pack, category=pack['category'], pictures=len(pics))
    print(f"published {pid_pack}; next: .venv/bin/python tools/store/apply_pack_prices.py --only {pid_pack} (dry run, then --apply)")


def delete(args):
    rows = api.list_rows('puzzles', [api.q('equal', args.pack_id, attribute='packId')])
    for r in rows:
        api.delete_row('puzzles', r['$id'])
    if exists('packs', args.pack_id):
        api.delete_row('packs', args.pack_id)
    state.log('local-pack-delete', pack=args.pack_id, puzzles=len(rows))
    print(f'deleted {args.pack_id} ({len(rows)} puzzles; hosted files stay in puzzle-images)')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('check', 'publish'):
        s = sub.add_parser(name)
        s.add_argument('manifest')
    d = sub.add_parser('delete')
    d.add_argument('--pack-id', required=True)
    a = p.parse_args()
    {'check': check, 'publish': publish, 'delete': delete}[a.cmd](a)


if __name__ == '__main__':
    main()
