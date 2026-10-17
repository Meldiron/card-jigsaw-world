"""The link preview of the web site (og:image in web/index.html): 1200 x 630, under 600 KB.

iMessage wants an image at least 900 px wide, WhatsApp one under 600 KB; both read the static meta
tags only. It shows what an invite (Play together) is: a real picture from the welcome pages
(assets/welcome/, public domain or CC0) dealt as cards, two of them still to swap, beside the Carden
name. No emojis, colour from the photo.

  .venv/bin/python tools/brand/invite_card.py      writes web/invite-card.jpg
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PHOTO = os.path.join(ROOT, 'assets', 'welcome', 'red-panda.jpg')
ICON = os.path.join(ROOT, 'tools', 'brand', 'out', 'carden-icon-rounded-512.png')
OUT = os.path.join(ROOT, 'web', 'invite-card.jpg')
FONT = '/System/Library/Fonts/SFNSRounded.ttf'
W, H = 1200, 630


def cover(im, w, h):
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def rounded(im, r):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
    out = im.convert('RGBA')
    out.putalpha(mask)
    return out


def main():
    photo = Image.open(PHOTO).convert('RGB')
    # The photo, blurred and dimmed, behind everything: the page takes its colour from it.
    bg = cover(photo, W, H).filter(ImageFilter.GaussianBlur(36))
    bg = Image.blend(bg, Image.new('RGB', (W, H), (12, 12, 16)), 0.52).convert('RGBA')

    # The board: the photo dealt as 3 x 3 cards, two of them still to swap.
    bw, bh, gap, cols, rows = 405, 540, 8, 3, 3
    bx, by = 96, (H - bh) // 2
    pic = cover(photo, bw, bh)
    cw, ch = (bw - gap * (cols - 1)) / cols, (bh - gap * (rows - 1)) / rows
    cells = [(c, r) for r in range(rows) for c in range(cols)]
    order = list(range(9))
    order[4], order[8] = order[8], order[4]
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for i in range(9):
        c, r = cells[i]
        x, y = bx + c * (cw + gap), by + r * (ch + gap)
        sd.rounded_rectangle((x, y + 6, x + cw, y + ch + 6), 14, fill=(0, 0, 0, 90))
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(10)))
    for slot in range(9):
        sc, sr = cells[order[slot]]
        src = pic.crop((round(sc * (cw + gap)), round(sr * (ch + gap)), round(sc * (cw + gap) + cw), round(sr * (ch + gap) + ch)))
        c, r = cells[slot]
        x, y = round(bx + c * (cw + gap)), round(by + r * (ch + gap))
        bg.alpha_composite(rounded(src, 14), (x, y))

    # The name.
    d = ImageDraw.Draw(bg)
    tx = 590
    icon = rounded(Image.open(ICON).convert('RGB').resize((104, 104), Image.LANCZOS), 24)
    bg.alpha_composite(icon, (tx, 150))
    d.text((tx - 4, 270), 'Carden', font=font(98), fill=(255, 255, 255))
    d.text((tx, 392), 'Play a picture together', font=font(42, 600), fill=(255, 255, 255, 230))
    d.text((tx, 452), 'play.carden.page', font=font(28, 500), fill=(255, 255, 255, 160))

    bg.convert('RGB').save(OUT, 'JPEG', quality=86, optimize=True, progressive=True)
    print(f'{os.path.relpath(OUT, ROOT)}: {os.path.getsize(OUT) // 1024} KB')


if __name__ == '__main__':
    main()
