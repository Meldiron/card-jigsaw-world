#!/usr/bin/env python3
"""Compose the App Store screenshots in Carden's glass style (one light set with a dark finale).

    .venv/bin/python tools/store/compose_glass.py                   # every slide -> store/screenshots/iphone-6.9
    .venv/bin/python tools/store/compose_glass.py 1 4               # only slides 01 and 04
    .venv/bin/python tools/store/compose_glass.py --font newyork    # rounded (default) | display | newyork
    .venv/bin/python tools/store/compose_glass.py --out /tmp/x --sheet /tmp/sheet.png

Edit the copy and the slides in SLIDES below, the pane colours in GLASS_BASE; the look (panes, halo,
headline, phones, break-out cards) is in tools/store/glass/slides.html. The app parts come from the
raw captures of integration_test/store_screenshots_test.dart in store/raw/: light slides use the
`<name>_light.png` captures (run the test with --dart-define=CJW_STORE_THEME=light), dark slides the
plain ones. Phone frames and the status bar come from compose_screenshots.py, so both styles draw
the same device. Needs a Chromium (Playwright's or Google Chrome; CHROME=/path overrides) and the
macOS system fonts. Research and rules: docs/store-screenshots.md ("Glass set, 2026-10-16").
"""
from __future__ import annotations

import argparse, glob, json, os, re, subprocess, sys, tempfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_screenshots as cs  # noqa: E402  (phone frame, status bar, captures, board boxes, covers)

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = Path(__file__).resolve().parent / "glass" / "slides.html"
OUT = ROOT / "store" / "screenshots" / "iphone-6.9"
ICON = ROOT / "tools" / "brand" / "out" / "carden-icon-light.svg"
W, H = cs.W, cs.H

# --------------------------------------------------------------------------------------------
# The slides. Layouts: "A" headline on top, flat phone below; "B" phone from the top edge, headline
# below, a row of pictures under it; "C" headline on top, phone tilted `tilt` degrees (5-15;
# alternate the direction). Slides 1-3 stay flat: search results show them as thumbnails.
# `phone`/`second`: capture names in store/raw (without _light).
# `out`: cards lifted out of the phone, cut from a capture: `crop` is (capture, (left, top, right,
#   bottom) in capture px) or (capture, "board"); `w` is the card width. Without x/y the card sits
#   centred over the same part of the phone's screen (so it never shows twice); with x/y it is
#   placed in phone px (0,0 = the phone's top-left, before any tilt). Cards tilt with their phone.
# `pics`: pictures on the slide itself: ("covers", ...) for pack covers from store/collage, or
#   capture crops; laid out by `fan()` as a neat row, or at fixed spots.
# Headlines: 2 lines, about five words; "\n" breaks the line. No subtext (illegible in search).

DAILY = "18_daily_month_grid"
STARRED = [(62, 840, 340, 1176), (674, 840, 952, 1176), (368, 1208, 646, 1546), (980, 1208, 1258, 1546), (368, 1576, 646, 1914)]

SLIDES = [
    {"layout": "A", "head": "Swap cards.\nReveal the picture.", "phone": "03_game_cards", "brand": True},
    {"layout": "B", "head": "Thousands\nof pictures", "phone": "15_library",
     "pics": [{"covers": [0, 3, 6, 9], "spots": [(-50, 300, 330, -8), (1040, 230, 380, 7), (-70, 1120, 330, 6), (1060, 1060, 380, -6)]},
              {"covers": [12, 15, 18, 1, 4], "fan": {"w": 228, "h": 296, "top": 2480, "step": 244, "spread": 9, "drop": 50}}]},
    {"layout": "A", "head": "A new picture\nevery day", "phone": DAILY,
     "out": [{"crop": (DAILY, (60, 530, 1260, 775)), "w": 1180, "radius": 44}]},
    {"layout": "C", "head": "Four ways\nto play", "phone": "09_mode_hexagons", "tilt": -7,
     "out": [{"crop": ("06_mode_cards", "board"), "x": -60, "y": 880, "w": 430, "rot": -9, "label": "Cards"},
             {"crop": ("07_mode_squares", "board"), "x": 690, "y": 560, "w": 400, "rot": 8, "label": "Squares"},
             {"crop": ("08_mode_triangles", "board"), "x": 680, "y": 1440, "w": 400, "rot": 5, "label": "Triangles"}]},
    {"layout": "A", "head": "Puzzle your\nown photos", "phone": "20_my_puzzles",
     "out": [{"crop": ("21_my_puzzle_game", "board"), "x": 540, "y": 1060, "w": 560, "rot": 4, "radius": 40}]},
    {"layout": "B", "head": "Fewer moves,\nmore stars", "phone": "04_complete",
     "out": [{"crop": ("04_complete", (40, 1400, 1280, 1890)), "w": 1200, "radius": 48}],
     "pics": [{"crops": [(DAILY, b) for b in STARRED], "fan": {"w": 228, "h": 276, "top": 2480, "step": 250, "spread": 8, "drop": 44}, "radius": 22}]},
    {"layout": "C", "head": "Quests and\nlive events", "phone": "13_quests", "tilt": 7,
     "out": [{"crop": ("14_quests_live", (60, 1440, 1260, 2480)), "x": 50, "y": 1180, "w": 900, "radius": 44}]},
    {"layout": "A", "head": "Climb the\nleaderboard", "phone": "22_social_league",
     "out": [{"crop": ("22_social_league", (60, 720, 1260, 1200)), "w": 1180, "radius": 48}]},
    {"layout": "C", "head": "Every pack\nwith VIP", "phone": "12_store_vip", "tilt": -7,
     "out": [{"crop": ("12_store_vip", (60, 670, 1260, 990)), "w": 1080, "radius": 40}]},
    {"layout": "A", "head": "Just as calm\nin the dark", "phone": "03_game_cards", "dark": True},
]

# Lotus glass, as in the app icon: the light and deep end of each pane colour.
GLASS_BASE = {"pink": ("#FF8FB5", "#FF4F8B"), "gold": ("#FFD36A", "#F0A30F"), "blue": ("#8CCBFF", "#2F86F2"), "teal": ("#7FE3C9", "#16927E")}
PANE_COLOURS = ["blue", "pink", "gold", "teal"]
BODY_OPACITY = (.5, .74)  # light end, deep end of a pane's tinted body
SHADOW_OPACITY = .2


def mix(a: str, b: str, t: float) -> str:
    x, y = (tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)) for c in (a, b))
    return "#" + "".join(f"{round(p + (q - p) * t):02x}" for p, q in zip(x, y))


def glass_tones() -> dict:
    """The tones of each glass colour (icon-glass.js): body ends, edge zone, crisp line, shadow."""
    return {k: {"hi": mix(c0, "#ffffff", .22), "lo": mix(c1, "#000000", .1), "edge": mix(c0, "#ffffff", .7),
                "line": mix(c1, "#000000", .3), "shadow": mix(c1, "#000000", .45)} for k, (c0, c1) in GLASS_BASE.items()}


def panes(n: int) -> list[dict]:
    """Two panes on every seam (and both outer edges): a large one and a smaller one on the other
    band, alternating up and down, so white canvas shows between them, a pane cut by a slide edge
    goes on in the next slide, and only the background ever crosses a seam."""
    out = []
    for k in range(n + 1):
        up = k % 2 == 0
        out.append({"x": k * W - 590 + (50 if k % 2 else -50), "y": 150 if up else 1120, "w": 1180, "h": 1600,
                    "rx": 120, "r": [12, -10, 10, -12][k % 4], "c": PANE_COLOURS[k % 4]})
        out.append({"x": k * W - 380 + (-80 if k % 2 else 80), "y": 1850 if up else 110, "w": 760, "h": 900,
                    "rx": 100, "r": [-9, 8, -7, 9][k % 4], "c": PANE_COLOURS[(k + 2) % 4]})
    return out


def fan(items: list[str], w: int, h: int, top: int, step: int, spread: float, drop: float, radius: int) -> list[dict]:
    """A neat row of pictures centred on the slide, on a gentle arc: the middle one highest and
    straight, the outer ones lower and turned outwards."""
    mid = (len(items) - 1) / 2 or 1
    return [{"src": src, "x": round(W / 2 + (i - mid) * step - w / 2), "y": round(top + drop * ((i - mid) / mid) ** 2),
             "w": w, "h": h, "r": round(spread * (i - mid) / mid, 1), "radius": radius} for i, src in enumerate(items)]


FONTS = {  # headline face: file, weight, tracking (em)
    "rounded": ("/System/Library/Fonts/SFNSRounded.ttf", 700, -0.012),
    "display": ("/System/Library/Fonts/SFNS.ttf", 700, -0.018),
    "newyork": ("/System/Library/Fonts/NewYork.ttf", 650, -0.01),
}
PHONE_W = 1000  # outer phone width on every slide
HEAD_SIZE, MEASURE = 136, 1180  # headline px; widest line allowed
LAYOUT = {"a_head_top": 200, "a_head_top_brand": 330, "a_gap": 120, "b_phone_top": -150, "b_gap": 150}


# --------------------------------------------------------------------------------------------

def capture(name: str, dark: bool) -> str:
    n = name if dark else f"{name}_light"
    if not (cs.RAW / f"{n}.png").exists():
        sys.exit(f"store/raw/{n}.png is missing: run integration_test/store_screenshots_test.dart"
                 f"{'' if dark else ' with --dart-define=CJW_STORE_THEME=light'} (see store/README.md)")
    return n


def board(name: str) -> tuple[int, int, int, int]:
    rects = cs.board_rects()
    key = name if name in rects else re.sub(r"_light$", "", name)
    if key not in rects:
        sys.exit(f"store/raw/boards.json has no board for {name}")
    left, top, w, h = rects[key]
    return round(left), round(top), round(left + w), round(top + h)


def phone_screen() -> tuple[float, float]:
    """Where a capture sits inside the phone frame of compose_screenshots.phone(): offset, scale."""
    band, bezel = round(PHONE_W * 0.011), round(PHONE_W * 0.026)
    return band + bezel, (PHONE_W - 2 * (band + bezel)) / cs.RAW_W


def export_parts(parts: Path) -> list[dict]:
    """Phones (one size), lifted cards and slide pictures for every slide, as files the template loads."""
    off, k = phone_screen()
    covers = [cs.COLLAGE / f"{p}.jpg" for p in cs.COLLAGE_PACKS if (cs.COLLAGE / f"{p}.jpg").exists()]
    slides = []
    for i, s in enumerate(SLIDES, start=1):
        dark = bool(s.get("dark"))
        edge = (20, 20, 24) if dark else (240, 240, 244)
        d = {key: s[key] for key in ("layout", "head", "brand", "tilt", "dark") if key in s}
        for key in ("phone", "second"):
            if key in s:
                n = capture(s[key], dark)
                f = f"phone-{n}.png"
                if not (parts / f).exists():
                    cs.phone(cs.load_raw(n), PHONE_W, edge).save(parts / f)
                d[key] = f
        d["out"] = []
        for j, o in enumerate(s.get("out", [])):
            n = capture(o["crop"][0], dark)
            box = board(n) if o["crop"][1] == "board" else o["crop"][1]
            f = f"crop-{i}-{j}.png"
            cs.load_raw(n).crop(box).save(parts / f)
            h = (box[3] - box[1]) * o["w"] / (box[2] - box[0])
            x = o.get("x", off + (box[0] + box[2]) / 2 * k - o["w"] / 2)
            y = o.get("y", off + (box[1] + box[3]) / 2 * k - h / 2)
            d["out"].append({"img": f, "x": round(x), "y": round(y), "w": o["w"], "rot": o.get("rot", 0),
                             "radius": o.get("radius", 34), "label": o.get("label", "")})
        d["pics"] = []
        for j, g in enumerate(s.get("pics", [])):
            if "covers" in g:
                if not covers:
                    sys.exit("no pack covers in store/collage/; run tools/store/compose_screenshots.py --refresh-collage")
                srcs = [str(covers[c % len(covers)]) for c in g["covers"]]
            else:
                srcs = []
                for m, (name, box) in enumerate(g["crops"]):
                    f = f"pic-{i}-{j}-{m}.png"
                    cs.load_raw(capture(name, dark)).crop(box).save(parts / f)
                    srcs.append(str(parts / f))
            radius = g.get("radius", 30)
            if "fan" in g:
                d["pics"] += fan(srcs, radius=radius, **g["fan"])
            else:
                d["pics"] += [{"src": src, "x": x, "y": y, "w": round(hh * .8), "h": hh, "r": r, "radius": radius}
                              for src, (x, y, hh, r) in zip(srcs, g["spots"])]
        slides.append(d)
    return slides


def chrome() -> str:
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    cache = os.path.expanduser("~/Library/Caches/ms-playwright")
    hits = sorted(glob.glob(f"{cache}/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell"), reverse=True)
    hits += sorted(glob.glob(f"{cache}/chromium-*/chrome-mac*/*.app/Contents/MacOS/*"), reverse=True)
    for c in hits + ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]:
        if os.path.exists(c):
            return c
    sys.exit("no Chromium found: set CHROME=/path/to/chrome")


def render(page: Path, n: int, out: Path) -> None:
    """Screenshot slide n. The window is taller than the slide (headless Chrome paints a little less
    than its window) and the result is cropped, flattened and saved without alpha (App Store)."""
    with tempfile.TemporaryDirectory() as d:
        shot = Path(d) / "shot.png"
        args = [chrome(), "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                f"--window-size={W},{H + 200}", "--force-device-scale-factor=1", "--virtual-time-budget=10000",
                f"--screenshot={shot}", f"file://{page}#{n}"]
        if "headless-shell" not in args[0]:
            args.insert(1, "--headless=new")
        subprocess.run(args, check=True, capture_output=True)
        Image.open(shot).convert("RGB").crop((0, 0, W, H)).save(out, "PNG", optimize=True)


def main(argv: list[str]) -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("only", nargs="*", type=int, help="slide numbers to render (default: all)")
    ap.add_argument("--font", choices=FONTS, default="rounded")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--sheet", type=Path, help="also write a contact sheet of the whole set")
    a = ap.parse_args(argv)

    build = ROOT / "build" / "store-glass"
    parts = build / "parts"
    parts.mkdir(parents=True, exist_ok=True)
    for f in parts.glob("*.png"):
        f.unlink()
    font_file, weight, track = FONTS[a.font]
    data = {"W": W, "H": H, "slides": export_parts(parts), "panes": panes(len(SLIDES)), "glass": glass_tones(),
            "body": BODY_OPACITY, "shadow": SHADOW_OPACITY,
            "parts": str(parts), "icon": str(ICON), "phone_w": PHONE_W,
            "phone_h": Image.open(next(parts.glob("phone-*.png"))).height,
            "head_size": HEAD_SIZE, "measure": MEASURE, "layout": LAYOUT,
            "font": {"weight": weight, "track": track}}
    page = build / "slides.html"
    page.write_text(TEMPLATE.read_text().replace("__DATA__", json.dumps(data)).replace("__FONT__", font_file))

    a.out.mkdir(parents=True, exist_ok=True)
    todo = a.only or list(range(1, len(SLIDES) + 1))
    for n in todo:
        render(page, n, a.out / f"{n:02d}.png")
        print(f"{n:02d}  {SLIDES[n - 1]['head'].replace(chr(10), ' ')}")
    if not a.only:  # a shorter set: drop numbered slides past the end
        for f in a.out.glob("[0-9][0-9].png"):
            if int(f.stem) > len(SLIDES):
                f.unlink()
                print(f"removed {f.name}")
    if a.sheet:
        cs.contact_sheet(sorted(a.out.glob("[0-9][0-9].png")), a.sheet)
        print(f"sheet {a.sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
