#!/usr/bin/env python3
"""Build the App Store Connect side assets:

  store/promo/app-icon-1024.png          1024x1024 icon, RGB (no alpha)
  store/promo/vip-promotional-1024.png   1024x1024 VIP promotional image
  store/review/subscription-review.png   store screen showing the VIP card

Usage (repo root, Pillow installed):  python tools/store/make_promo.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ICON_SRC = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
RAW_STORE_VIP = ROOT / "store/raw/12_store_vip.png"
PROMO = ROOT / "store/promo"
REVIEW = ROOT / "store/review"

BG = (242, 242, 244)
INK = (17, 24, 39)
MUTED = (107, 114, 128)
ACCENT = (0x2F, 0x4F, 0xBF)  # Brand.accent (cobalt)
EDGE = (205, 205, 210)
SF = "/System/Library/Fonts/SFNS.ttf"


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    big = Image.new("L", (size[0] * 2, size[1] * 2), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * 2, fill=255)
    return big.resize(size, Image.LANCZOS)


def app_icon_no_alpha() -> Image.Image:
    icon = Image.open(ICON_SRC).convert("RGBA")
    flat = Image.new("RGB", icon.size, (255, 255, 255))
    flat.paste(icon, mask=icon.getchannel("A"))
    return flat


def vip_promo(icon: Image.Image) -> Image.Image:
    S = 1024
    im = Image.new("RGB", (S, S), BG)
    d = ImageDraw.Draw(im)

    # Icon tile, iOS-style corner radius (~22%), thin edge.
    size = 440
    tile = icon.resize((size, size), Image.LANCZOS)
    mask = rounded_mask((size, size), int(size * 0.22))
    x = (S - size) // 2
    y = 130
    edge = Image.new("RGB", (size + 4, size + 4), EDGE)
    im.paste(edge, (x - 2, y - 2), rounded_mask((size + 4, size + 4), int(size * 0.22) + 2))
    im.paste(tile, (x, y), mask)

    # Word mark.
    f_vip = font(200, "Bold")
    tw = d.textlength("VIP", font=f_vip)
    d.text(((S - tw) / 2 - 6, y + size + 36), "VIP", font=f_vip, fill=ACCENT)

    f_sub = font(44, "Medium")
    sub = "Every pack unlocked. No videos. 7 days free."
    sw = d.textlength(sub, font=f_sub)
    d.text(((S - sw) / 2, y + size + 36 + 232), sub, font=f_sub, fill=INK)

    f_name = font(34, "Regular")
    name = "Carden"
    nw = d.textlength(name, font=f_name)
    d.text(((S - nw) / 2, S - 86), name, font=f_name, fill=MUTED)
    return im


def main() -> None:
    PROMO.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)

    icon = app_icon_no_alpha()
    icon.save(PROMO / "app-icon-1024.png", "PNG", optimize=True)
    print("wrote store/promo/app-icon-1024.png", icon.size, icon.mode)

    promo = vip_promo(icon)
    promo.save(PROMO / "vip-promotional-1024.png", "PNG", optimize=True)
    print("wrote store/promo/vip-promotional-1024.png", promo.size, promo.mode)

    if RAW_STORE_VIP.exists():
        shot = Image.open(RAW_STORE_VIP).convert("RGB")
        shot.save(REVIEW / "subscription-review.png", "PNG", optimize=True)
        print("wrote store/review/subscription-review.png", shot.size, shot.mode)
    else:
        print("skipped subscription-review.png: store/raw/12_store_vip.png missing")


if __name__ == "__main__":
    main()
