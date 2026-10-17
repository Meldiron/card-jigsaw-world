"""The link preview cards (og:image): their lettering and the site's default card.

Since 2026-10-17 every Play together invite (https://join.carden.page/<code>) has its own card, drawn
by the `api` function (functions/api/src/invite/card.js): the real picture dealt in the board's real
shapes and size, the picture blurred and zoomed behind it, the Carden logo and a few words. The
function has no fonts, so its lettering comes from here, set in SF Pro Rounded (the brand's headline
face) as white glyphs on a transparent atlas:

  functions/api/assets/invite/text.png + text.json   every word and digit a card can show
  functions/api/assets/invite/logo.png                the app icon, rounded

Then it draws the default card of the site with the same code (node tools/brand/invite_card.mjs):

  web/invite-card.jpg   1200 x 630, every link of play.carden.page (and an ended or unknown invite)

and a few sample invite cards to look at (build/invite_cards/). Run after changing the words, the
font or the icon:

  .venv/bin/python tools/brand/invite_card.py
"""
import json
import math
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ICON = os.path.join(ROOT, 'tools', 'brand', 'out', 'carden-icon-rounded-512.png')
OUT_DIR = os.path.join(ROOT, 'functions', 'api', 'assets', 'invite')
FONT = '/System/Library/Fonts/SFNSRounded.ttf'

DIGITS = list('0123456789')

# Every style the card sets: size and weight (the font's Weight axis), and the words it may show.
# A line is made of these tokens and spaces (card.js, `line`), so only what is listed can be drawn.
STYLES = {
    'wordmark': (96, 700, ['Carden']),
    'headline': (42, 600, ['Play together', 'Your calm picture puzzle']),
    'detail': (32, 600, ['Cards', 'Squares', 'Triangles', 'Hexagons', 'x'] + DIGITS),
    'muted': (27, 500, ['cards', 'pieces', 'Painting', '·', 'play.carden.page', 'join.carden.page'] + DIGITS),
}

PAD = 4


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    # Axes: GRAD (grade), then Weight.
    f.set_variation_by_axes([400, weight])
    return f


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    glyphs = []  # (style, token, image, advance)
    meta = {}
    for name, (size, weight, tokens) in STYLES.items():
        f = font(size, weight)
        ascent, descent = f.getmetrics()
        meta[name] = {'size': size, 'ascent': ascent, 'descent': descent, 'space': f.getlength(' '), 'tokens': {}}
        for tok in tokens:
            adv = f.getlength(tok)
            w, h = math.ceil(adv) + 2 * PAD, ascent + descent + 2 * PAD
            im = Image.new('L', (w, h), 0)
            ImageDraw.Draw(im).text((PAD, PAD + ascent), tok, font=f, fill=255, anchor='ls')
            glyphs.append((name, tok, im, adv))

    # Shelf packing, one row after another.
    width = 1024
    x = y = row = 0
    places = []
    for name, tok, im, adv in glyphs:
        if x + im.width > width:
            x, y, row = 0, y + row + 2, 0
        places.append((name, tok, im, adv, x, y))
        x += im.width + 2
        row = max(row, im.height)
    atlas = Image.new('LA', (width, y + row), (255, 0))
    for name, tok, im, adv, px, py in places:
        white = Image.new('LA', im.size, (255, 0))
        white.putalpha(im)
        atlas.paste(white, (px, py))
        meta[name]['tokens'][tok] = [px, py, im.width, im.height, round(adv, 3)]
    atlas.save(os.path.join(OUT_DIR, 'text.png'), optimize=True)
    with open(os.path.join(OUT_DIR, 'text.json'), 'w') as fh:
        json.dump({'pad': PAD, 'styles': meta}, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    icon = Image.open(ICON).convert('RGBA').resize((208, 208), Image.LANCZOS)
    icon.save(os.path.join(OUT_DIR, 'logo.png'), optimize=True)
    print(f'{os.path.relpath(OUT_DIR, ROOT)}: text.png {atlas.size[0]}x{atlas.size[1]}, logo.png 208 px')

    subprocess.run(['node', os.path.join(ROOT, 'tools', 'brand', 'invite_card.mjs')], check=True, cwd=ROOT)


if __name__ == '__main__':
    main()
