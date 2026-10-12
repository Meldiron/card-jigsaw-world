"""Contact sheets for visual review: a grid of thumbnails with short labels."""
from PIL import Image, ImageDraw, ImageFont
from .paths import CACHE
from . import imagecache

COLS, CELL_W, CELL_H, LABEL_H, PAD = 6, 200, 266, 30, 6
_font = None
def font(size=15):
    global _font
    if _font is None:
        for p in ('/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Helvetica.ttc', '/Library/Fonts/Arial.ttf'):
            try:
                _font = ImageFont.truetype(p, size); break
            except Exception:
                continue
        else:
            _font = ImageFont.load_default()
    return _font

def render(items, out_path, title='', per_sheet=48):
    """items: list of dicts {label, url, note(optional), bad(optional bool)}. Returns list of written paths."""
    paths = []
    for s in range(0, max(len(items), 1), per_sheet):
        chunk = items[s:s + per_sheet]
        rows = (len(chunk) + COLS - 1) // COLS
        W = COLS * (CELL_W + PAD) + PAD
        H = rows * (CELL_H + LABEL_H + PAD) + PAD + 28
        sheet = Image.new('RGB', (W, H), (250, 250, 250))
        d = ImageDraw.Draw(sheet)
        d.text((PAD, 6), f'{title}  (sheet {s // per_sheet + 1}, {len(chunk)} of {len(items)})', fill=(20, 20, 20), font=font())
        for i, it in enumerate(chunk):
            x = PAD + (i % COLS) * (CELL_W + PAD); y = 28 + PAD + (i // COLS) * (CELL_H + LABEL_H + PAD)
            tp = imagecache.thumb_path(it['url'])
            box = (x, y, x + CELL_W, y + CELL_H)
            if tp.exists():
                im = Image.open(tp).convert('RGB')
                im.thumbnail((CELL_W, CELL_H), Image.LANCZOS)
                sheet.paste(im, (x + (CELL_W - im.width) // 2, y + (CELL_H - im.height) // 2))
            else:
                d.rectangle(box, fill=(225, 225, 225)); d.text((x + 8, y + 8), 'no image', fill=(120, 0, 0), font=font())
            d.rectangle(box, outline=(200, 40, 40) if it.get('bad') else (190, 190, 190), width=2)
            lab = it['label']
            d.rectangle((x, y + CELL_H, x + CELL_W, y + CELL_H + LABEL_H), fill=(255, 255, 255))
            d.text((x + 4, y + CELL_H + 2), lab[:16], fill=(0, 0, 0), font=font())
            note = it.get('note', '')
            if note:
                d.text((x + 4, y + CELL_H + 15), note[:30], fill=(90, 90, 90), font=font(12))
        p = str(out_path).replace('.png', f'-{s // per_sheet + 1}.png') if len(items) > per_sheet else str(out_path)
        sheet.save(p, 'PNG', optimize=True)
        paths.append(p)
    return paths
