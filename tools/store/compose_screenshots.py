#!/usr/bin/env python3
"""Compose the App Store marketing screenshots from the raw captures in store/raw/.

Usage (from the repo root, with Pillow installed):
    python3 tools/store/compose_screenshots.py              # all slides
    python3 tools/store/compose_screenshots.py 1 4          # only slides 01 and 04
    python3 tools/store/compose_screenshots.py --canvas neutral   # graphite canvas on every slide
    python3 tools/store/compose_screenshots.py --refresh-collage  # re-download the pack covers
    python3 tools/store/compose_screenshots.py --sheet /tmp/sheet.png  # also a contact sheet of all slides

The system (see docs/store-screenshots.md for the research behind it):

* Canvas: a flat, very dark tone taken from the slide's own photo (hue of
  the picture, low saturation, about 10% lightness). No gradients. With
  `--canvas neutral` every slide uses one graphite instead.
* Caption: 2-5 words, SF Pro Display Bold, centred at the top, sized so it
  is legible in search-result thumbnails (about 120-132 px on a 1320 px
  canvas). One short muted line below it for the product page.
* The app: a real capture in a slim iPhone frame (Dynamic Island, a clean
  9:41 status bar drawn in, because in-app captures have none), large and
  bleeding off the bottom edge.
* Special layouts: a 2x2 grid of real board crops (one picture cut four
  ways), a wall of real pack covers behind the phone, and zoomed callouts
  cut from real captures.

Colour comes only from the photos; the single accent (cobalt, dark-theme
tint 0xFF7C9AFF) is used sparingly for callout rings. Edit SLIDES below to
change copy, order or sources, then rerun.
"""
from __future__ import annotations

import colorsys
import json
import re
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "store" / "raw"
OUT = ROOT / "store" / "screenshots" / "iphone-6.9"
COLLAGE = ROOT / "store" / "collage"

W, H = 1320, 2868  # Apple 6.9" portrait
RAW_W, RAW_H = 1320, 2868  # iPhone 17 Pro Max captures (3x)

INK = (245, 245, 247)
MUTED = (168, 168, 176)
ACCENT_DARK = (0x7C, 0x9A, 0xFF)  # Brand.accent, dark theme
NEUTRAL_CANVAS = (21, 21, 23)
CALLOUT_EDGE = (78, 78, 84)  # hairline around a callout lifted over a dark screen

SF = "/System/Library/Fonts/SFNS.ttf"
HELVETICA = "/System/Library/Fonts/HelveticaNeue.ttc"

APPWRITE = "https://fra.cloud.appwrite.io/v1"
PROJECT = "6acb4de5003e38d5ebd9"

# Pack covers on the "Thousands of pictures" slide: vivid, people-free,
# one per category where possible. Served from our own Storage bucket.
COLLAGE_PACKS = [
    "pack-tulip-fields", "pack-parrots", "pack-hot-air-balloons", "pack-nebulae",
    "pack-fruit-markets", "pack-northern-lights", "pack-canyons", "pack-cherry-blossom",
    "pack-santorini", "pack-hummingbirds", "pack-kyoto", "pack-lavender",
    "pack-japanese-prints", "pack-frogs", "pack-islands", "pack-sushi",
    "pack-lighthouses", "pack-tiles", "pack-sunflowers", "pack-venice",
]


@dataclass
class Callout:
    """A zoomed piece of a real capture, floated over the phone."""

    raw: str  # capture to cut from
    box: tuple[int, int, int, int] | None  # crop in raw px (l, t, r, b); None = the board (boards.json)
    width: int  # on-slide width of the zoomed card
    center: tuple[int, int]  # on-slide centre
    radius: int = 44  # corner radius of the card (slide px)
    ring: bool = False  # cobalt ring around the card (default: a hairline grey edge)
    frac: tuple[float, float, float, float] = (0, 0, 1, 1)  # part of the box to keep (l, t, r, b as fractions)


@dataclass
class Slide:
    kind: str  # "phone" | "grid4" | "collage"
    headline: str  # 2-5 words; "\n" forces a break
    sub: str = ""
    raw: str = ""  # main capture (phone / collage)
    raws: list[str] = field(default_factory=list)  # grid4: four game captures
    labels: list[str] = field(default_factory=list)  # grid4: one per panel
    phone_w: int = 1150  # outer width of the phone
    phone_gap: int = 96  # space between the text block and the phone
    callouts: list[Callout] = field(default_factory=list)
    # Where the canvas hue comes from: None = the slide's photo (board, or
    # the whole capture), "neutral" = graphite, or (raw, box) = that crop.
    tone: str | tuple[str, tuple[int, int, int, int] | None] | None = None


SLIDES: list[Slide] = [
    # 1-3 show in search results: the core loop, the catalogue, the daily hook.
    Slide(
        "phone",
        "Swap pieces.\nReveal the picture.",
        "Tap two pieces to trade places. Right spot, it locks.",
        raw="03_game_cards",
    ),
    Slide(
        "collage",
        "Thousands\nof pictures",
        "Nature, animals, cities, art and space, in 150+ packs.",
        raw="15_library",
        phone_w=960,
    ),
    Slide(
        "phone",
        "A new picture\nevery day",
        "Solve today's puzzle for a bonus.",
        raw="18_daily_month_grid",
    ),
    Slide(
        "grid4",
        "Four ways\nto play",
        "Trickier shapes pay more. Eight board sizes each.",
        raws=["06_mode_cards", "07_mode_squares", "08_mode_triangles", "09_mode_hexagons"],
        labels=["Cards", "Squares", "Triangles", "Hexagons"],
    ),
    Slide(
        "phone",
        "Puzzle your\nown photos",
        "Add a photo from your library or camera and play it.",
        raw="20_my_puzzles",
        tone=("21_my_puzzle_game", None),
        # The newest photo, mid-game, over the lower half of the grid.
        callouts=[Callout("21_my_puzzle_game", None, width=600, center=(905, 2235), radius=34)],
    ),
    Slide(
        "phone",
        "Fewer moves,\nmore stars",
        "Coins and XP for every picture you finish.",
        raw="04_complete",
    ),
    Slide(
        "phone",
        "Quests and\nlive events",
        "Daily and weekly quests, plus world-day events.",
        raw="13_quests",
        tone=("14_quests_live", (60, 690, 1260, 1566)),
        # A world-day event card from further down the Quests tab.
        callouts=[Callout("14_quests_live", (60, 690, 1260, 1566), width=1020, center=(660, 2330), radius=50)],
    ),
    Slide(
        "phone",
        "Climb\nthe league",
        "Ranked by XP each season. Add your friends.",
        raw="22_social_league",
        tone="neutral",
    ),
    Slide(
        "phone",
        "Every pack\nwith VIP",
        "7 days free. No bonus videos. 500 coins a week.",
        raw="12_store_vip",
        tone="neutral",
    ),
]


# --------------------------------------------------------------------------
# Fonts and text


def font(size: int, weight: int = 700, opsz: float | None = None) -> ImageFont.FreeTypeFont:
    """SF Pro at [weight]; optical size follows the point size (Display for
    headlines). Falls back to Helvetica Neue."""
    try:
        f = ImageFont.truetype(SF, size)
        # Axes: Width, Optical Size, GRAD, Weight.
        f.set_variation_by_axes([100, max(17, min(96, opsz if opsz is not None else size / 1.4)), 400, weight])
        return f
    except Exception:  # noqa: BLE001 - any font failure falls back
        return ImageFont.truetype(HELVETICA, size, index=1 if weight >= 600 else 0)


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    lines: list[str] = []
    for para in text.split("\n"):
        cur = ""
        for word in para.split(" "):
            trial = f"{cur} {word}".strip()
            if draw.textlength(trial, font=f) <= max_w or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def headline_font(draw: ImageDraw.ImageDraw, text: str, max_w: int) -> ImageFont.FreeTypeFont:
    """Largest size from 132 down to 104 px whose longest line fits."""
    for size in range(132, 102, -2):
        f = font(size, 700, opsz=96)
        if all(draw.textlength(line, font=f) <= max_w for line in text.split("\n")):
            return f
    return font(104, 700, opsz=96)


def draw_text_block(canvas: Image.Image, slide: Slide, top: int = 150) -> int:
    """Centred headline and subhead. Returns the y just below the block."""
    draw = ImageDraw.Draw(canvas)
    max_w = W - 2 * 84
    hf = headline_font(draw, slide.headline, max_w)
    lh = round(hf.size * 1.06)
    y = top
    for line in slide.headline.split("\n"):
        tw = draw.textlength(line, font=hf)
        draw.text(((W - tw) / 2, y), line, font=hf, fill=INK)
        y += lh
    if slide.sub:
        sf = font(46, 400, opsz=28)
        y += 34
        for line in wrap(draw, slide.sub, sf, W - 2 * 120):
            tw = draw.textlength(line, font=sf)
            draw.text(((W - tw) / 2, y), line, font=sf, fill=MUTED)
            y += 60
    return y


# --------------------------------------------------------------------------
# Images


def load_raw(name: str) -> Image.Image:
    im = Image.open(RAW / f"{name}.png").convert("RGB")
    if im.size != (RAW_W, RAW_H):
        im = im.resize((RAW_W, RAW_H), Image.LANCZOS)
    return im


def board_rects() -> dict:
    p = RAW / "boards.json"
    return json.loads(p.read_text()) if p.exists() else {}


def has_board(name: str) -> bool:
    return name in board_rects()


def board_box(name: str) -> tuple[int, int, int, int]:
    """The board's rectangle in a game capture (store/raw/boards.json)."""
    rects = board_rects()
    if name not in rects:
        raise SystemExit(f"store/raw/boards.json has no board for {name}; recapture with the store test")
    l, t, w, h = rects[name]
    return round(l), round(t), round(l + w), round(t + h)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    # Drawn at 3x and downsampled for smooth corners.
    s = 3
    big = Image.new("L", (size[0] * s, size[1] * s), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * s, fill=255)
    return big.resize(size, Image.LANCZOS)


def canvas_tone(sample: Image.Image) -> tuple[int, int, int]:
    """A flat, very dark tone in the hue of the photo in [sample]: the
    saturation-weighted mean hue, low saturation, about 10% lightness."""
    small = sample.convert("RGB").resize((96, 96), Image.BILINEAR)
    sx = sy = wsum = 0.0
    import math

    for r, g, b in small.get_flattened_data() if hasattr(small, "get_flattened_data") else small.getdata():
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        wgt = s * v * v
        sx += math.cos(2 * math.pi * h) * wgt
        sy += math.sin(2 * math.pi * h) * wgt
        wsum += wgt
    if wsum < 1e-3:
        return NEUTRAL_CANVAS
    hue = (math.atan2(sy, sx) / (2 * math.pi)) % 1.0
    strength = min(1.0, math.hypot(sx, sy) / wsum)  # how dominant one hue is
    r, g, b = colorsys.hls_to_rgb(hue, 0.095, 0.16 + 0.22 * strength)
    return round(r * 255), round(g * 255), round(b * 255)


# --------------------------------------------------------------------------
# Status bar and device frame


def is_dark(im: Image.Image, box: tuple[int, int, int, int]) -> bool:
    region = im.crop(box).convert("L").resize((40, 10))
    data = region.get_flattened_data() if hasattr(region, "get_flattened_data") else region.getdata()
    return sum(data) / 400 < 128


def draw_status_bar(shot: Image.Image) -> Image.Image:
    """A clean iOS status bar (9:41, full signal, Wi-Fi, full battery) on a
    raw 1320x2868 capture. In-app captures are taken without one."""
    im = shot.copy()
    d = ImageDraw.Draw(im)
    fg = (255, 255, 255) if is_dark(im, (0, 0, RAW_W, 180)) else (0, 0, 0)
    cy = 92  # vertical centre, level with the Dynamic Island
    # Time, centred in the left ear.
    tf = font(53, 600, opsz=17)
    tw = d.textlength("9:41", font=tf)
    bbox = d.textbbox((0, 0), "9:41", font=tf)
    d.text((262 - tw / 2, cy - (bbox[1] + bbox[3]) / 2), "9:41", font=tf, fill=fg)
    # Right cluster: cellular, Wi-Fi, battery (3x points).
    x = 966
    bars = [(14, 0.38), (14, 0.58), (14, 0.79), (14, 1.0)]
    full_h = 36
    for i, (bw, frac) in enumerate(bars):
        bh = full_h * frac
        d.rounded_rectangle((x + i * 18, cy + full_h / 2 - bh, x + i * 18 + bw, cy + full_h / 2), 4, fill=fg)
    x += 4 * 18 + 16
    # Wi-Fi: three concentric wedges, each cut by the next smaller circle.
    wx, wy = x + 28, cy + 19
    big = Image.new("L", (RAW_W, 200), 0)
    bd = ImageDraw.Draw(big)
    for r_out, r_in in [(41, 31), (26, 16), (11, 0)]:
        bd.pieslice((wx - r_out, wy - r_out, wx + r_out, wy + r_out), 225, 315, fill=255)
        if r_in:
            bd.pieslice((wx - r_in, wy - r_in, wx + r_in, wy + r_in), 225, 315, fill=0)
    im.paste(Image.new("RGB", big.size, fg), (0, 0), big)
    x += 68
    # Battery: outline at 40% plus a full fill and the nub.
    bx0, by0, bx1, by1 = x, cy - 20, x + 80, cy + 20
    outline = Image.new("L", (RAW_W, 200), 0)
    od = ImageDraw.Draw(outline)
    od.rounded_rectangle((bx0, by0, bx1, by1), 13, outline=255, width=4)
    od.rounded_rectangle((bx1 + 4, cy - 7, bx1 + 9, cy + 7), 3, fill=255)
    im.paste(Image.new("RGB", outline.size, fg), (0, 0), outline.point(lambda v: int(v * 0.42)))
    d.rounded_rectangle((bx0 + 7, by0 + 7, bx1 - 7, by1 - 7), 8, fill=fg)
    return im


def phone(shot: Image.Image, outer_w: int, edge_on: tuple[int, int, int]) -> Image.Image:
    """The capture inside a slim iPhone 17 Pro Max style frame (RGBA)."""
    band = round(outer_w * 0.011)  # titanium band
    bezel = round(outer_w * 0.026)  # black glass border
    sw = outer_w - 2 * (band + bezel)
    sh = round(sw * RAW_H / RAW_W)
    outer_h = sh + 2 * (band + bezel)
    r_screen = round(sw * 0.125)
    r_inner = r_screen + bezel
    r_outer = r_inner + band

    lum = sum(edge_on) / 3
    band_col = (58, 58, 62) if lum < 90 else (40, 40, 44)
    edge_col = (104, 104, 110) if lum < 90 else (150, 150, 156)

    body = Image.new("RGBA", (outer_w, outer_h), (0, 0, 0, 0))
    # Titanium band with a hairline highlight, then black glass.
    body.paste(Image.new("RGBA", body.size, edge_col + (255,)), (0, 0), rounded_mask(body.size, r_outer))
    body.paste(Image.new("RGBA", (outer_w - 4, outer_h - 4), band_col + (255,)), (2, 2), rounded_mask((outer_w - 4, outer_h - 4), r_outer - 2))
    glass = (outer_w - 2 * band, outer_h - 2 * band)
    body.paste(Image.new("RGBA", glass, (4, 4, 5, 255)), (band, band), rounded_mask(glass, r_inner))
    # Screen.
    scr = draw_status_bar(shot).resize((sw, sh), Image.LANCZOS)
    sd = ImageDraw.Draw(scr)
    # Dynamic Island (3x points: 126 x 37 at y 11, scaled to this screen).
    k = sw / RAW_W
    iw, ih, it = 378 * k, 111 * k, 34 * k
    sd.rounded_rectangle(((sw - iw) / 2, it, (sw + iw) / 2, it + ih), ih / 2, fill=(0, 0, 0))
    body.paste(scr.convert("RGBA"), (band + bezel, band + bezel), rounded_mask((sw, sh), r_screen))
    return body


def drop_shadow(size: tuple[int, int], radius: int, blur: int, alpha: int) -> Image.Image:
    pad = blur * 3
    sh = Image.new("L", (size[0] + 2 * pad, size[1] + 2 * pad), 0)
    sh.paste(rounded_mask(size, radius).point(lambda v: v * alpha // 255), (pad, pad))
    return sh.filter(ImageFilter.GaussianBlur(blur))


def paste_shadowed(canvas: Image.Image, im: Image.Image, xy: tuple[int, int], radius: int, blur: int = 40, alpha: int = 150, dy: int = 24) -> None:
    sh = drop_shadow(im.size, radius, blur, alpha)
    pad = blur * 3
    canvas.paste((0, 0, 0), (xy[0] - pad, xy[1] - pad + dy), sh)
    canvas.paste(im, xy, im if im.mode == "RGBA" else None)


def card(im: Image.Image, width: int, radius: int, ring: tuple[int, int, int] | None = None, ring_w: int = 0) -> Image.Image:
    """[im] scaled to [width] with rounded corners (RGBA), optional ring."""
    h = round(im.height * width / im.width)
    scaled = im.convert("RGB").resize((width, h), Image.LANCZOS)
    if ring:
        out = Image.new("RGBA", (width + 2 * ring_w, h + 2 * ring_w), (0, 0, 0, 0))
        out.paste(Image.new("RGBA", out.size, ring + (255,)), (0, 0), rounded_mask(out.size, radius + ring_w))
        out.paste(scaled.convert("RGBA"), (ring_w, ring_w), rounded_mask((width, h), radius))
        return out
    out = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    out.paste(scaled.convert("RGBA"), (0, 0), rounded_mask((width, h), radius))
    return out


# --------------------------------------------------------------------------
# Slide kinds


def tone_for(slide: Slide, neutral: bool) -> tuple[int, int, int]:
    if neutral or slide.tone == "neutral":
        return NEUTRAL_CANVAS
    if isinstance(slide.tone, tuple):
        raw, box = slide.tone
        return canvas_tone(load_raw(raw).crop(box or board_box(raw)))
    if slide.kind == "grid4":
        sample = load_raw(slide.raws[0]).crop(board_box(slide.raws[0]))
    elif slide.kind == "collage":
        sample = Image.open(COLLAGE / f"{COLLAGE_PACKS[0]}.jpg")
    else:
        im = load_raw(slide.raw)
        sample = im.crop(board_box(slide.raw)) if has_board(slide.raw) else im
    return canvas_tone(sample)


def compose_phone(slide: Slide, bg: tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGB", (W, H), bg)
    y = draw_text_block(canvas, slide)
    ph = phone(load_raw(slide.raw), slide.phone_w, bg)
    canvas.paste(ph, ((W - ph.width) // 2, y + slide.phone_gap), ph)
    add_callouts(canvas, slide, bg)
    return canvas


def compose_grid4(slide: Slide, bg: tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGB", (W, H), bg)
    text_bottom = draw_text_block(canvas, slide)
    draw = ImageDraw.Draw(canvas)
    margin, gap_x, gap_y, label_h = 64, 40, 56, 96
    col_w = (W - 2 * margin - gap_x) // 2
    crops = [load_raw(r).crop(board_box(r)) for r in slide.raws]
    # Common panel height so the rows line up (boards share one picture).
    panel_h = max(round(c.height * col_w / c.width) for c in crops)
    grid_h = 2 * (panel_h + label_h) + gap_y
    y = text_bottom + max(90, (H - text_bottom - grid_h) // 2)
    lf = font(52, 600, opsz=28)
    for i, (crop, label) in enumerate(zip(crops, slide.labels)):
        cx = margin + (i % 2) * (col_w + gap_x)
        cy = y + (i // 2) * (panel_h + label_h + gap_y)
        tile = card(crop, col_w, 36)
        canvas.paste(tile, (cx, cy + (panel_h - tile.height) // 2), tile)
        tw = draw.textlength(label, font=lf)
        draw.text((cx + (col_w - tw) / 2, cy + panel_h + 26), label, font=lf, fill=INK)
    return canvas


def refresh_collage() -> None:
    COLLAGE.mkdir(parents=True, exist_ok=True)
    for pid in COLLAGE_PACKS:
        url = f"{APPWRITE}/tablesdb/cjw/tables/packs/rows/{pid}"
        req = urllib.request.Request(url, headers={"X-Appwrite-Project": PROJECT})
        cover = json.load(urllib.request.urlopen(req))["coverUrl"]
        cover = re.sub(r"width=\d+", "width=600", cover)
        urllib.request.urlretrieve(cover, COLLAGE / f"{pid}.jpg")
        print(f"cover {pid}")


def compose_collage(slide: Slide, bg: tuple[int, int, int]) -> Image.Image:
    """A wall of real pack covers behind the phone (Library screen)."""
    covers = [Image.open(COLLAGE / f"{p}.jpg").convert("RGB") for p in COLLAGE_PACKS if (COLLAGE / f"{p}.jpg").exists()]
    if not covers:
        raise SystemExit("no pack covers in store/collage/; run with --refresh-collage")
    probe = Image.new("RGB", (W, H), bg)
    y = draw_text_block(probe, slide)
    ph = phone(load_raw(slide.raw), slide.phone_w, bg)
    px, py = (W - ph.width) // 2, y + slide.phone_gap
    hidden = (px + 60, py + 60, px + ph.width - 60, py + ph.height - 60)

    # Four staggered columns running off both edges; the middle two sit
    # mostly behind the phone. Covers go to the most visible tiles first
    # (outer columns), so no pack shows twice; tiles the phone nearly hides
    # reuse covers.
    wall = Image.new("RGB", (W, H), bg)
    col_w, gap = 330, 26
    xs = [-140, -140 + col_w + gap, W - 2 * col_w - gap + 140, W - col_w + 140]
    starts = [y + 60, y + 250, y + 150, y + 330]
    shapes = [1.25, 1.0, 1.25, 0.8, 1.25, 1.0]  # height / width of successive tiles
    tiles: list[tuple[float, int, tuple[int, int, int, int], float]] = []
    for ci, x in enumerate(xs):
        cy, n = starts[ci], ci
        while cy < H:
            ratio = shapes[n % len(shapes)]
            n += 1
            th = round(col_w * ratio)
            rect = (x, cy, x + col_w, cy + th)
            ox = max(0, min(rect[2], hidden[2]) - max(rect[0], hidden[0]))
            oy = max(0, min(rect[3], hidden[3]) - max(rect[1], hidden[1]))
            on_canvas = max(0, min(rect[2], W) - max(rect[0], 0)) * max(0, min(rect[3], H) - max(rect[1], 0))
            visible = max(0, on_canvas - ox * oy) / (col_w * th)
            tiles.append((visible, ci, rect, ratio))
            cy += th + gap
    order = sorted(range(len(tiles)), key=lambda i: -tiles[i][0])
    pick: dict[int, Image.Image] = {}
    for rank, i in enumerate(order):
        pick[i] = covers[rank % len(covers)]
    for i, (visible, _ci, rect, ratio) in enumerate(tiles):
        if visible <= 0:
            continue
        im = pick[i]
        cw, ch = im.width, round(im.width * ratio)
        if ch > im.height:
            ch, cw = im.height, round(im.height / ratio)
        left, upper = (im.width - cw) // 2, (im.height - ch) // 2
        tile = card(im.crop((left, upper, left + cw, upper + ch)), col_w, 30)
        wall.paste(tile, rect[:2], tile)
    # Hold the wall back a little so the phone leads.
    canvas = Image.blend(wall, Image.new("RGB", (W, H), bg), 0.32)
    draw_text_block(canvas, slide)
    paste_shadowed(canvas, ph, (px, py), round(ph.width * 0.16), blur=46, alpha=210, dy=30)
    return canvas


def add_callouts(canvas: Image.Image, slide: Slide, bg: tuple[int, int, int]) -> None:
    for c in slide.callouts:
        l, t, r, b = c.box or board_box(c.raw)
        fl, ft, fr, fb = c.frac
        crop = load_raw(c.raw).crop((round(l + (r - l) * fl), round(t + (b - t) * ft), round(l + (r - l) * fr), round(t + (b - t) * fb)))
        ring = ACCENT_DARK if c.ring else CALLOUT_EDGE
        tile = card(crop, c.width, c.radius, ring=ring, ring_w=6 if c.ring else 3)
        x, y = c.center[0] - tile.width // 2, c.center[1] - tile.height // 2
        paste_shadowed(canvas, tile, (x, y), c.radius, blur=36, alpha=190, dy=26)


def compose(slide: Slide, neutral: bool) -> Image.Image:
    bg = tone_for(slide, neutral)
    if slide.kind == "grid4":
        return compose_grid4(slide, bg)
    if slide.kind == "collage":
        return compose_collage(slide, bg)
    return compose_phone(slide, bg)


def contact_sheet(paths: list[Path], out: Path) -> None:
    tw, th, gap = 330, 717, 24
    sheet = Image.new("RGB", (len(paths) * (tw + gap) + gap, th + 2 * gap), (236, 236, 240))
    for i, p in enumerate(paths):
        sheet.paste(Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS), (gap + i * (tw + gap), gap))
    sheet.save(out)


def main(argv: list[str]) -> None:
    neutral = "--canvas" in argv and argv[argv.index("--canvas") + 1] == "neutral"
    if "--refresh-collage" in argv or not any(COLLAGE.glob("*.jpg")):
        refresh_collage()
    wanted = {int(a) for a in argv if a.isdigit()}
    OUT.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for i, slide in enumerate(SLIDES, start=1):
        if wanted and i not in wanted:
            continue
        out = OUT / f"{i:02d}.png"
        im = compose(slide, neutral)
        assert im.size == (W, H) and im.mode == "RGB"
        im.save(out, "PNG", optimize=True)
        written.append(out)
        src = slide.raw or ", ".join(slide.raws)
        print(f"wrote {out.relative_to(ROOT)}  ({W}x{H})  <- {src}")
    # Remove slides beyond the current set (the set used to have more).
    if not wanted:
        for extra in OUT.glob("*.png"):
            if extra.stem.isdigit() and int(extra.stem) > len(SLIDES):
                extra.unlink()
                print(f"removed {extra.relative_to(ROOT)}")
    if "--sheet" in argv:
        sheet = Path(argv[argv.index("--sheet") + 1])
        contact_sheet(sorted(OUT.glob("[0-9][0-9].png")), sheet)
        print(f"wrote {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
