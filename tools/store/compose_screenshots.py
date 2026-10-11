#!/usr/bin/env python3
"""Compose App Store marketing screenshots from the raw captures in store/raw/.

Usage (from the repo root, with Pillow installed):
    python tools/store/compose_screenshots.py            # all slides
    python tools/store/compose_screenshots.py 1 4        # only slides 01 and 04

Each slide is a flat neutral canvas (1320x2868, the 6.9" iPhone size), a short
headline and optional subhead at the top, and the raw capture inside a rounded
dark device-like frame. Colour comes only from the puzzle photos; the single
accent is the app's cobalt (0xFF2F4FBF), used for the small kicker label.

Edit SLIDES below to change copy, order or source captures, then rerun.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "store" / "raw"
OUT = ROOT / "store" / "screenshots" / "iphone-6.9"

W, H = 1320, 2868  # Apple 6.9" portrait

# Palette: flat neutrals plus the one brand accent.
LIGHT_BG = (242, 242, 244)
DARK_BG = (17, 17, 19)
INK_ON_LIGHT = (17, 24, 39)
MUTED_ON_LIGHT = (107, 114, 128)
INK_ON_DARK = (245, 245, 247)
MUTED_ON_DARK = (161, 161, 170)
ACCENT = (0x2F, 0x4F, 0xBF)
FRAME = (28, 28, 30)
FRAME_EDGE_ON_LIGHT = (205, 205, 210)
FRAME_EDGE_ON_DARK = (62, 62, 66)

SF = "/System/Library/Fonts/SFNS.ttf"
HELVETICA = "/System/Library/Fonts/HelveticaNeue.ttc"


@dataclass
class Slide:
    raw: str  # file name inside store/raw (without .png)
    headline: str  # 2-5 words, may contain "\n" to force a break
    subhead: str = ""
    kicker: str = ""  # tiny indigo label above the headline
    dark: bool = False  # near-black canvas instead of light grey
    frame_top: int = 620  # y of the frame's top edge
    frame_width: int = 1080  # outer frame width; the phone bleeds off the bottom


SLIDES: list[Slide] = [
    Slide("05_game_cards", "Swap cards.\nReveal the picture.", "Tap two cards to trade places. Right spot, it locks.", kicker="Gameplay"),
    Slide("03_daily_month", "A new puzzle\nevery day", "One fresh picture per day, with a bonus for today's.", kicker="Daily"),
    Slide("04_pack", "Thousands of photos\nin packs", "Nature, animals, cities, art and more.", kicker="Library"),
    Slide("16_game_hexagons_dark", "Hexagons, triangles,\nsquares", "Four board shapes, any size you like.", kicker="Modes"),
    Slide("06_complete", "Three stars,\nreal rewards", "Beat par for coins, XP and a perfect finish.", kicker="Rewards"),
    Slide("10_social_league", "Climb\nthe league", "Ranked by XP against real players. Add friends.", kicker="Social"),
    Slide("09_events", "Daily and\nweekly goals", "Earn coins and tickets just for playing.", kicker="Events"),
    Slide("12_store_vip", "VIP: every pack,\nno breaks", "7 days free. Every pack unlocked, no videos.", kicker="VIP"),
]


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    """SF Pro (system) at the given weight, Helvetica Neue as a fallback."""
    try:
        f = ImageFont.truetype(SF, size)
        f.set_variation_by_name(weight)
        return f
    except Exception:  # noqa: BLE001 - any font failure falls back
        idx = {"Bold": 1, "Semibold": 1, "Medium": 10, "Regular": 0}.get(weight, 0)
        return ImageFont.truetype(HELVETICA, size, index=idx)


def fit_headline(draw: ImageDraw.ImageDraw, text: str, max_w: int) -> ImageFont.FreeTypeFont:
    """Largest headline size between 80 and 96 px whose longest line fits."""
    for size in range(96, 78, -2):
        f = font(size, "Bold")
        if all(draw.textlength(line, font=f) <= max_w for line in text.split("\n")):
            return f
    return font(80, "Bold")


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    # Draw at 2x and downsample for smooth corners.
    big = Image.new("L", (size[0] * 2, size[1] * 2), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * 2, fill=255)
    return big.resize(size, Image.LANCZOS)


def load_raw(name: str) -> Image.Image:
    im = Image.open(RAW / f"{name}.png").convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


def compose(slide: Slide) -> Image.Image:
    bg = DARK_BG if slide.dark else LIGHT_BG
    ink = INK_ON_DARK if slide.dark else INK_ON_LIGHT
    muted = MUTED_ON_DARK if slide.dark else MUTED_ON_LIGHT
    edge = FRAME_EDGE_ON_DARK if slide.dark else FRAME_EDGE_ON_LIGHT

    canvas = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(canvas)
    margin = 100
    y = 150

    if slide.kicker:
        kf = font(34, "Semibold")
        text = slide.kicker.upper()
        # Simple letter spacing: draw glyph by glyph.
        x = margin
        for ch in text:
            draw.text((x, y), ch, font=kf, fill=ACCENT)
            x += draw.textlength(ch, font=kf) + 5
        y += 34 + 34

    hf = fit_headline(draw, slide.headline, W - 2 * margin)
    line_h = int(hf.size * 1.12)
    for line in slide.headline.split("\n"):
        draw.text((margin - 4, y), line, font=hf, fill=ink)
        y += line_h
    y += 18

    if slide.subhead:
        sf = font(42, "Regular")
        draw.text((margin, y), slide.subhead, font=sf, fill=muted)
        y += 42 + 24

    # Device frame: rounded dark rectangle, thin edge, screenshot inside.
    bezel = 18
    outer_w = slide.frame_width
    inner_w = outer_w - 2 * bezel
    inner_h = round(inner_w * H / W)
    outer_h = inner_h + 2 * bezel
    fx = (W - outer_w) // 2
    fy = max(slide.frame_top, y + 60)

    frame = Image.new("RGB", (outer_w, outer_h), FRAME)
    frame_mask = rounded_mask((outer_w, outer_h), 118)
    shot = load_raw(slide.raw).resize((inner_w, inner_h), Image.LANCZOS)
    shot_mask = rounded_mask((inner_w, inner_h), 100)
    frame.paste(shot, (bezel, bezel), shot_mask)
    # Thin edge line drawn on the frame itself.
    edge_layer = Image.new("RGB", (outer_w, outer_h), edge)
    edge_mask = rounded_mask((outer_w, outer_h), 118)
    inner_cut = Image.new("L", (outer_w, outer_h), 0)
    inner_cut.paste(rounded_mask((outer_w - 4, outer_h - 4), 116), (2, 2))
    ring = Image.eval(inner_cut, lambda v: 255 - v)
    ring = Image.composite(edge_mask, Image.new("L", edge_mask.size, 0), ring)
    frame.paste(edge_layer, (0, 0), ring)

    canvas.paste(frame, (fx, fy), frame_mask)
    return canvas


def main(argv: list[str]) -> None:
    wanted = {int(a) for a in argv} if argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    for i, slide in enumerate(SLIDES, start=1):
        if wanted and i not in wanted:
            continue
        out = OUT / f"{i:02d}.png"
        compose(slide).save(out, "PNG", optimize=True)
        print(f"wrote {out.relative_to(ROOT)}  ({W}x{H})  <- raw/{slide.raw}.png")


if __name__ == "__main__":
    main(sys.argv[1:])
