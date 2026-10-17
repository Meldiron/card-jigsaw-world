"""Before/after sheets for the twin cards measure (docs/twins.md): the pairs newly accepted, the
pairs newly kept apart and the ones kept apart just over the limit, each as A and B at about phone
size (dimmed 16% like a loose card), the same lifted 5x (darks) and their difference x8 (inverted),
with the numbers. Reads two reports of tools/dev/twins_report_test.dart on the same pictures.

    .venv/bin/python tools/dev/twins_diff_sheets.py before/twins_report.json after/twins_report.json out [pairs]
"""
import json
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from twins_sheets import card_image, shape_ratio, speck_ratio  # noqa: E402

PHONE = 1110  # a phone board is about 370 pt wide, 3 px a point


def columns(spec):
    mode, rest = spec.split(':')
    cols = int(rest.split('x')[0])
    return (cols - 1) // 2 if mode == 'triangles' else cols


def score(p):
    return max(p['colour'], speck_ratio(p), shape_ratio(p))


def key(b, p):
    return (b['id'], b['spec'], p['a'], p['b'])


def load(path):
    boards = json.load(open(path))
    pairs = {}
    for b in boards:
        for p in b['near']:
            pairs[key(b, p)] = (b, p)
    return boards, pairs


images = {}


def cache(file, decoded):
    if file not in images:
        im = Image.open(file).convert('RGB')
        images[file] = (im, im.size[0] / decoded[0])
    return images[file]


def tile(im, spec, cap=200):
    """About the size it has on a phone (cards of a 7x7 board about 158 px wide), at most [cap]."""
    w, h = im.size
    target = PHONE / max(3, columns(spec))
    s = min(target / w, cap / max(w, h))
    return im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)


def sheet(items, title, path):
    if not items:
        print('no pairs for', path)
        return
    rows = []
    for board, p, before in items:
        img, scale = cache(board['file'], board['decoded'])
        a = card_image(img, board['polys'][str(p['a'])], scale)
        b = card_image(img, board['polys'][str(p['b'])], scale)
        if b.size != a.size:
            b = b.resize(a.size, Image.LANCZOS)
        diff = ImageOps.invert(ImageChops.difference(a, b).point(lambda v: min(255, v * 8)))
        lift = lambda t: t.point(lambda v: min(255, v * 5))  # noqa: E731
        dim = lambda t: ImageEnhance.Brightness(t).enhance(0.84)  # noqa: E731
        tiles = [tile(dim(a), board['spec']), tile(dim(b), board['spec']), tile(lift(a), board['spec']), tile(lift(b), board['spec']), tile(diff, board['spec'])]
        rows.append((board, p, before, tiles))
    width = max(sum(t.size[0] + 6 for t in r[3]) for r in rows) + 330
    height = sum(max(t.size[1] for t in r[3]) + 8 for r in rows) + 40
    out = Image.new('RGB', (width, height), (24, 24, 28))
    d = ImageDraw.Draw(out)
    d.text((8, 8), title, fill=(235, 235, 235))
    d.text((8, 22), 'A and B as on a phone (dimmed 16% like a loose card) | A and B lifted 5x | difference x8, inverted', fill=(180, 180, 180))
    y = 40
    for board, p, before, tiles in rows:
        x = 8
        for t in tiles:
            out.paste(t, (x, y))
            x += t.size[0] + 6
        lines = [
            f"{board['id'][:22]}",
            f"{board['spec']}  cards {p['a']} - {p['b']}",
            f"score {score(p):.2f} (before {before})",
            f"mean {p['mean']:.2f} p95 {p['p95']:.2f} max {p['max']:.2f}",
            f"edge {p['edge']:.2f} speck {p['speck']:.1f}/{p['speckAllowed']:.1f}",
            f"shape {shape_ratio(p):.2f} specks {p.get('specks')}",
        ]
        for k, line in enumerate(lines):
            d.text((x + 6, y + 4 + 14 * k), line, fill=(225, 225, 225))
        y += max(t.size[1] for t in tiles) + 8
    out.save(path, quality=85)
    print('wrote', path, len(items), 'pairs', out.size)


def spread(xs, n):
    seen, first, rest = set(), [], []
    for x in xs:
        k = (x[0]['id'])
        (first if k not in seen else rest).append(x)
        seen.add(k)
    return (first + rest)[:n]


def main():
    before_path, after_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 24
    os.makedirs(out_dir, exist_ok=True)
    _, before = load(before_path)
    boards, after = load(after_path)
    newly, dropped, border = [], [], []
    for k, (b, p) in after.items():
        s = score(p)
        old = before.get(k)
        olds = score(old[1]) if old else None
        tag = f'{olds:.2f}' if olds is not None else 'colour > 1.6'
        if s <= 1 and (olds is None or olds > 1):
            newly.append((b, p, tag))
        if s > 1 and olds is not None and olds <= 1:
            dropped.append((b, p, tag))
        if 1 < s <= 1.35:
            border.append((b, p, tag))
    print(f'newly accepted {len(newly)}, newly rejected {len(dropped)}, rejected 1.0-1.35 after {len(border)}')
    newly.sort(key=lambda x: -score(x[1]))
    dropped.sort(key=lambda x: score(x[1]))
    border.sort(key=lambda x: score(x[1]))
    with open(os.path.join(out_dir, 'pairs.txt'), 'w') as f:
        for name, xs in [('newly accepted', newly), ('newly rejected', dropped)]:
            f.write(f'== {name} ({len(xs)})\n')
            for b, p, tag in xs:
                f.write(f"{b['id']} {b['spec']} {p['a']}-{p['b']} score {score(p):.2f} before {tag} speck {speck_ratio(p):.2f} shape {shape_ratio(p):.2f} specks {p.get('specks')}\n")
    sheet(spread(newly, n), 'Newly accepted as twins (after <= 1, before > 1), closest to the limit first', os.path.join(out_dir, 'newly_accepted.jpg'))
    sheet(spread(dropped, n), 'Twins before, kept apart now, closest to the limit first', os.path.join(out_dir, 'newly_rejected.jpg'))
    sheet(spread(border, n), 'Kept apart, just over the limit (score 1.0-1.35)', os.path.join(out_dir, 'rejected_borderline.jpg'))


if __name__ == '__main__':
    main()
