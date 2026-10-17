"""Contact sheets and numbers for the twin cards report (docs/twins.md).

Reads the JSON written by tools/dev/twins_report_test.dart and draws the pairs closest to the
threshold: the ones just accepted as twins and the ones just rejected, each as card A, card B and
their difference amplified eight times (so a faint cloud the eye might miss shows up), with the
measured numbers. Also prints how often twins occur.

    python3 tools/dev/twins_sheets.py out/twins_report.json out/sheets
"""
import json
import os
import random
import statistics
import sys

from PIL import Image, ImageChops, ImageDraw, ImageOps

TILE = 132


def speck_ratio(p):
    """The speck against what its sample may have (TwinPair.speckAllowed): twins at 1 or less."""
    return p['speck'] / p['speckAllowed']


def shape_ratio(p):
    """A broad shape on dark cards against TwinFinder.shapeLimit (0 in reports made before it)."""
    return p.get('shape', 0)


AMPLIFY = 8


def card_image(img, poly, scale):
    """The card's picture (its bounding box, outside the shape greyed) from the original file."""
    pts = [(x * scale, y * scale) for x, y in poly]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    box = (int(min(xs)), int(min(ys)), int(max(xs) + 0.999), int(max(ys) + 0.999))
    crop = img.crop(box)
    mask = Image.new('L', crop.size, 0)
    ImageDraw.Draw(mask).polygon([(x - box[0], y - box[1]) for x, y in pts], fill=255)
    grey = Image.new('RGB', crop.size, (128, 128, 128))
    return Image.composite(crop, grey, mask)


def fit(im):
    w, h = im.size
    s = TILE / max(w, h)
    return im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)


def sheet(pairs, title, path, cache):
    cols = 3
    cell_w, cell_h = TILE * 3 + 16, TILE + 34
    rows = (len(pairs) + cols - 1) // cols
    out = Image.new('RGB', (cols * cell_w + 16, rows * cell_h + 40), (250, 250, 250))
    d = ImageDraw.Draw(out)
    d.text((10, 10), title, fill=(0, 0, 0))
    for i, (board, p) in enumerate(pairs):
        img, scale = cache(board['file'], board['decoded'])
        a = card_image(img, board['polys'][str(p['a'])], scale)
        b = card_image(img, board['polys'][str(p['b'])], scale)
        if b.size != a.size:
            b = b.resize(a.size, Image.LANCZOS)
        diff = ImageChops.difference(a, b).point(lambda v: min(255, v * AMPLIFY))
        x0 = 8 + (i % cols) * cell_w
        y0 = 36 + (i // cols) * cell_h
        for k, im in enumerate([a, b, ImageOps.invert(diff)]):
            out.paste(fit(im), (x0 + k * (TILE + 4), y0))
        label = f"{board['id'][:18]} {board['spec'].split(':')[0][:3]} {board['spec'].split(':')[1]}  s={p['score']:.2f}"
        nums = f"mean {p['mean']:.2f} p95 {p['p95']:.2f} max {p['max']:.2f} edge {p['edge']:.2f} speck {p['speck']:.1f}/{p['speckAllowed']:.1f} shape {shape_ratio(p):.2f} specks {p.get('specks', '-')}"
        d.text((x0, y0 + TILE + 2), label, fill=(0, 0, 0))
        d.text((x0, y0 + TILE + 16), nums, fill=(60, 60, 60))
    out.save(path)
    print('wrote', path, len(pairs), 'pairs')


def main():
    report, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    boards = json.load(open(report))
    # The score again with the speck limits given here (the same as the app's by default).
    for b in boards:
        for p in b['near']:
            p['score'] = max(p['colour'], speck_ratio(p), shape_ratio(p))
    images = {}

    def cache(file, decoded):
        if file not in images:
            im = Image.open(file).convert('RGB')
            images[file] = (im, im.size[0] / decoded[0])
        return images[file]

    # How often twins occur.
    def kind(b):
        mode = b['spec'].split(':')[0]
        return ('giant ' if b['cells'] > 120 else '') + mode
    groups = {}
    for b in boards:
        groups.setdefault(kind(b), []).append(b)
    print(f"{len(boards)} boards from {len({b['id'] for b in boards})} pictures")
    print(f"{'boards':22} {'n':>4} {'with twins':>11} {'twin cards (median / max share)':>32} {'crowded':>8} {'find ms (max)':>14}")
    for k in sorted(groups):
        bs = groups[k]
        withs = [b for b in bs if b['twinCards'] > 0]
        shares = [b['twinCards'] / b['cells'] for b in bs]
        crowded = sum(1 for b in bs if b['crowded'])
        print(f"{k:22} {len(bs):4} {len(withs):5} ({100 * len(withs) / len(bs):3.0f}%) "
              f"{100 * statistics.median(shares):12.1f}% / {100 * max(shares):5.1f}% {crowded:8} {max(b['findMs'] for b in bs):14}")
    flat = sorted({(b['id'], b['category']) for b in boards if b['twinCards'] > 0})
    print('pictures with twins on some board:', len(flat), 'of', len({b['id'] for b in boards}))

    near = [(b, p) for b in boards for p in b['near']]
    accepted = sorted([x for x in near if x[1]['score'] <= 1], key=lambda x: -x[1]['score'])
    rejected = sorted([x for x in near if x[1]['score'] > 1], key=lambda x: x[1]['score'])
    print('pairs: accepted', len(accepted), 'rejected within 1.6x', len(rejected))

    def spread(xs, n):
        # One pair per picture first, so a single sky does not fill the sheet.
        seen, first, rest = set(), [], []
        for x in xs:
            (first if x[0]['id'] not in seen else rest).append(x)
            seen.add(x[0]['id'])
        return (first + rest)[:n]

    sheet(spread([x for x in accepted if x[1]['score'] > 0.8], 30), 'Just accepted as twins (score 0.80-1.00): A | B | difference x8, inverted', f'{out_dir}/accepted_borderline.png', cache)
    sheet(spread(rejected, 30), 'Just rejected (score 1.00-1.6): A | B | difference x8, inverted', f'{out_dir}/rejected_borderline.png', cache)
    # The speck test on its own: pairs the colour test accepts, by how much a speck stands out.
    colour_ok = [x for x in near if x[1]['colour'] <= 1]
    sheet(spread(sorted([x for x in colour_ok if speck_ratio(x[1]) <= 1], key=lambda x: -speck_ratio(x[1])), 30),
          'Colour alike, speck just under the limit (accepted): A | B | difference x8, inverted', f'{out_dir}/speck_accepted.png', cache)
    sheet(spread(sorted([x for x in colour_ok if speck_ratio(x[1]) > 1], key=lambda x: speck_ratio(x[1])), 30),
          'Colour alike, kept apart by a speck (just over the limit): A | B | difference x8, inverted', f'{out_dir}/speck_rejected.png', cache)
    if colour_ok:
        sp = sorted(x[1]['speck'] for x in colour_ok)

        def q(f):
            return sp[min(len(sp) - 1, int(f * len(sp)))]
        print(f"speck among colour-alike pairs: n={len(sp)} median {q(0.5):.1f} p90 {q(0.9):.1f} p99 {q(0.99):.1f} "
              f"max {sp[-1]:.1f}; kept apart {sum(1 for x in colour_ok if speck_ratio(x[1]) > 1)}")
    random.Random(3).shuffle(accepted)
    sheet(spread(accepted, 30), 'Accepted twins, a random spread: A | B | difference x8, inverted', f'{out_dir}/accepted_random.png', cache)


if __name__ == '__main__':
    main()
