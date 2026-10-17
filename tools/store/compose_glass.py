#!/usr/bin/env python3
"""Compose the App Store screenshots in Carden's glass style (one light set with a dark finale).

    .venv/bin/python tools/store/compose_glass.py                   # every slide -> store/screenshots/iphone-6.9
    .venv/bin/python tools/store/compose_glass.py 1 4               # only slides 01 and 04
    .venv/bin/python tools/store/compose_glass.py --font newyork    # rounded (default) | display | newyork
    .venv/bin/python tools/store/compose_glass.py --out /tmp/x --sheet /tmp/sheet.png

Edit the copy and the slides in slides() below, the pane colours in GLASS_BASE; the look (panes,
headline, phones, lifted cards, pictures) is in tools/store/glass/slides.html. The app parts come from the
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
# The slides. Every slide places its own headline and phones, so the layouts take turns:
# `text`: (anchor, y, align): the headline's "top", "bottom" or "center" at y, aligned "left",
#   "center" or "right" (90 px margin). Two lines, about five words; "\n" breaks the line. No
#   subtext: it is illegible in search results.
# `phones`: [{capture, x, y, rot, out, tags}], all the same size (PHONE_W); x, y = the phone's
#   top-left in slide px (it may run off an edge), rot in degrees about 40% of its height.
#   `out`: cards lifted out of that phone, cut from a capture: `crop` = (capture, (l, t, r, b) in
#   capture px) or (capture, "board"); `w` = card width. Without x/y a card centres itself over
#   the same part of the phone's screen (it never shows twice); with x/y it sits in phone px.
#   `tags`: small labels in phone px. Cards and tags turn with their phone.
# `pics`: pictures on the slide behind the phones: pack covers (`covers`, indexes into
#   compose_screenshots.COLLAGE_PACKS) or capture crops, as a `masonry` wall or at fixed `spots`.
# `key`: the slide's stable name; custom product pages reuse a slide by it ({"default": "daily"}).
# Slides 1-3 keep their phones flat (search results show them as thumbnails). No AI pictures.
# Apple takes at most 10 screenshots per set.

DAILY = "18_daily_month_grid"
# The world-day event card on Quests and the leaderboard's podium (capture px).
EVENT_CARD = (60, 1608, 1260, 2532)
PODIUM = (60, 720, 1260, 1200)
STREAK_CARD = (60, 1539, 1260, 2052)  # Home's streak card in 31_home_streak (2026-10-17 Home layout)
# Play together (store capture scene with scripted players, Bora Bora lagoon in Cards 7x7 Master): a shared
# board mid-build with the players chip in the top bar, Leo's purple "L" on the cards he moved and
# Ava's orange "A" on the card she holds; and the player list (avatars in their colour rings, Host /
# You, Here, Remove). Boxes in capture px, checked on a coordinate grid of the 2026-10-17 captures.
COOP_BOARD = "32_coop_board"
COOP_PLAYERS = "33_coop_players"
# Ava's held card with her orange outline: its slot changes from run to run, so the capture test records
# its rectangle in boards.json (`recordCell`, per theme) and the box names that record.
COOP_HELD = "rect:32_coop_held"
COOP_LIST = (60, 1668, 1260, 2250)   # the player list's card: Mia (host, you), Ava, Leo
COOP_LIST_RADIUS = 45                 # that card's corner radius in capture px
# Solved daily pictures with their stars (days 1, 3, 6, 8, 10 of the calendar capture).
STARRED = [(62, 840, 340, 1176), (674, 840, 952, 1176), (368, 1208, 646, 1546), (980, 1208, 1258, 1546), (368, 1576, 646, 1914)]


def cell(name: str, cols: int, rows: int, c: int, r: int, inset: int = 4) -> tuple:
    """Capture box of one card of a cols x rows Cards board (from store/raw/boards.json)."""
    l, t, rr, b = board(name + "_light") if (cs.RAW / f"{name}_light.png").exists() else board(name)
    cw, ch = (rr - l) / cols, (b - t) / rows
    return (round(l + c * cw + inset), round(t + r * ch + inset), round(l + (c + 1) * cw - inset), round(t + (r + 1) * ch - inset))


def board_part(name: str, fx0: float, fy0: float, fx1: float, fy1: float) -> tuple:
    """Capture box of a part of a board, as fractions of the board."""
    l, t, r, b = board(name + "_light") if (cs.RAW / f"{name}_light.png").exists() else board(name)
    return (round(l + (r - l) * fx0), round(t + (b - t) * fy0), round(l + (r - l) * fx1), round(t + (b - t) * fy1))


def slides() -> list[dict]:
    """The story (2.0.0, 2026-10-17): the hook (1-3: how it plays, how much there is, playing it
    together; the three search results show), why you come back and the depth (4-9), the dark
    finale (10). Read in order, the headlines are one text."""
    return [
        # 1. The mechanic, mid-build: some cards locked, some loose, some joined.
        {"key": "hero", "head": "Swap cards.\nReveal the picture.", "brand": True, "text": ("top", 330, "center"),
         "phones": [{"capture": "25_hero", "x": 160, "y": 738}]},
        # 2. How much there is: one straight row of pack covers running off both edges (endless), the
        #    Library rising from the bottom edge, scrolled so its grid starts with packs.
        {"key": "library", "head": "Thousands\nof pictures", "text": ("top", 200, "center"),
         "pics": [{"packs": ["pack-venice", "pack-lavender", "pack-japanese-prints", "pack-nebulae", "pack-northern-lights", "pack-sunflowers", "pack-islands"],
                   "row": {"w": 360, "h": 480, "gap": 28, "y": 640}, "radius": 30}],
         "phones": [{"capture": "15_library", "x": 160, "y": 1300}]},
        # 3. Play together (new in 2.0.0): a shared board mid-build, flat and pushed right, Leo's
        #    purple cards in place on it; Ava's held card (orange, "A") lifted on the left, the player
        #    list (colour rings, Host, Remove) lifted over the toolbar, just under the board. Headline
        #    top left, so slide 4 (top right) answers it.
        {"key": "together", "head": "Play together\nwith friends", "text": ("top", 200, "left"),
         "phones": [{"capture": COOP_BOARD, "x": 360, "y": 600,
                     "out": [{"crop": (COOP_BOARD, COOP_HELD), "x": -325, "y": 560, "w": 330, "rot": -6, "radius": 6},
                             {"crop": (COOP_PLAYERS, COOP_LIST), "x": -300, "y": 1700, "w": 940,
                              "radius": round(COOP_LIST_RADIUS * 940 / 1200)}]}]},
        # 4. Why you come back: the calendar pushed left, today's picture and the streak from Home
        #    lifted, solved days with their stars on the right.
        {"key": "daily", "head": "A new picture\nevery day", "text": ("top", 200, "right"),
         "pics": [{"crops": [(DAILY, STARRED[0]), (DAILY, STARRED[3])],
                   "spots": [(1000, 1330, 350, 6), (990, 1760, 350, -5)], "radius": 26}],
         "phones": [{"capture": DAILY, "x": -60, "y": 600,
                     "out": [{"crop": (DAILY, (60, 530, 1260, 775)), "x": 150, "w": 1140, "radius": 44},
                             {"crop": ("31_home_streak", STREAK_CARD), "x": 120, "y": 1700, "w": 1040, "radius": 40}]}]},
        # 5. The signature, split around the headline: cards above, hexagons below, squares and
        #    triangles lifted; every badge sits on the edge of its board or card that faces the headline.
        {"key": "shapes", "head": "One picture,\nfour ways to cut it", "text": ("center", 1600, "center"),
         "phones": [{"capture": "06_mode_cards", "x": 160, "y": -700, "rot": -3, "tags": [{"text": "Cards", "edge": "bottom"}],
                     "out": [{"crop": ("07_mode_squares", "board"), "x": 640, "y": 1330, "w": 400, "rot": 6, "label": "Squares"}]},
                    {"capture": "09_mode_hexagons", "x": 160, "y": 1880, "rot": 3, "tags": [{"text": "Hexagons", "edge": "top"}],
                     "out": [{"crop": ("08_mode_triangles", "board"), "x": -60, "y": 430, "w": 400, "rot": -6, "label": "Triangles", "label_at": "top"}]}]},
        # 6. Painting: Monet's chrysanthemums mostly grey, a few cards back in colour; the phone straight
        #    and centred (owner), a loose and a locked card lifted.
        {"key": "painting", "head": "Bring the colour\nback, card by card", "text": ("center", 2390, "center"),
         "phones": [{"capture": "26_painting", "x": 160, "y": -150,
                     "out": [{"crop": ("26_painting", cell("26_painting", 4, 4, 0, 0)), "x": -110, "y": 1560, "w": 300, "rot": -7, "radius": 26, "label": "Loose"},
                             {"crop": ("26_painting", cell("26_painting", 4, 4, 1, 1)), "x": 810, "y": 1520, "w": 300, "rot": 6, "radius": 26, "label": "Locked"}]}]},
        # 7. Giant boards: zoomed in with the overview map in the corner; the whole board in its
        #    hundreds of tiny squares (a small part solved) lifted beside it.
        {"key": "giant", "head": "Giant boards of\nhundreds of cards", "text": ("top", 200, "left"),
         "phones": [{"capture": "30_giant_zoom", "x": 360, "y": 620, "rot": 6,
                     "out": [{"crop": ("27_giant", "board"), "x": -360, "y": 520, "w": 640, "rot": -5, "radius": 30}]}]},
        # 8. The personal one: your own photos, one played as a puzzle; the headline bottom right, the
        #    phone pushed left and the corgi board lifted on the right.
        {"key": "photos", "head": "Puzzle your\nown photos", "text": ("bottom", 2740, "right"),
         "phones": [{"capture": "20_my_puzzles", "x": -60, "y": 140,
                     "out": [{"crop": ("21_my_puzzle_game", "board"), "x": 660, "y": 980, "w": 600, "rot": 5, "radius": 40}]}]},
        # 9. Quests, with the world-day event card lifted (cut exactly at the card's own edges and
        #    corners, 48 px in the capture, so no rounding cuts into it).
        {"key": "quests", "head": "Quests and\nworld-day events", "text": ("top", 200, "center"),
         "phones": [{"capture": "13_quests", "x": 120, "y": 620, "rot": -7,
                     "out": [{"crop": ("14_quests_live", EVENT_CARD), "w": 900, "radius": round(48 * 900 / 1200)}]}]},
        # 10. The finale: the same calm in dark mode, a board mid-build.
        {"key": "dark", "head": "Just as calm\nin the dark", "text": ("top", 200, "center"), "dark": True,
         "phones": [{"capture": "29_dark_board", "x": 160, "y": 608}]},
    ]


# Not in the set since 2.0.0 (Apple takes 10 screenshots; Play together carries friends now), kept for
# custom product pages: {"default": "league"}.
EXTRA_SLIDES = [
    # Friends and the leaderboard: the player (level 17 by now) second on the podium.
    {"key": "league", "head": "Climb the ranks\nwith friends", "text": ("bottom", 2740, "right"),
     "phones": [{"capture": "22_social_league", "x": -20, "y": -120, "rot": -5,
                 "out": [{"crop": ("22_social_league", PODIUM), "w": 1120, "radius": 44}]}]},
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


def hand(items: list[str], w: int, h: int, top: int, spread: float, radius_px: int, radius: int) -> list[dict]:
    """A hand of cards: the pictures fanned from one pivot far below, the middle one upright and
    highest, the outer ones turned out and lower (like cards held in one hand)."""
    import math
    mid = (len(items) - 1) / 2 or 1
    pivot_y = top + h / 2 + radius_px
    out = []
    for i, src in enumerate(items):
        a = math.radians(spread * (i - mid) / mid)
        cx, cy = W / 2 + radius_px * math.sin(a), pivot_y - radius_px * math.cos(a)
        out.append({"src": src, "x": round(cx - w / 2), "y": round(cy - h / 2), "w": w, "h": h, "r": round(math.degrees(a), 1), "radius": radius})
    return out


def row(items: list[str], w: int, h: int, gap: int, y: int, radius: int) -> list[dict]:
    """One straight row of pictures running off both edges of the slide (it reads as endless):
    centred on the middle picture, so both edges cut a picture in half."""
    mid = (len(items) - 1) / 2
    return [{"src": src, "x": round(W / 2 + (i - mid) * (w + gap) - w / 2), "y": y, "w": w, "h": h, "r": 0, "radius": radius}
            for i, src in enumerate(items)]


def cover(pack_id: str, width: int = 900) -> str:
    """A pack's cover from our Storage at [width] px, cached in build/store-glass/covers."""
    import urllib.request
    cache = ROOT / "build" / "store-glass" / "covers"
    cache.mkdir(parents=True, exist_ok=True)
    f = cache / f"{pack_id}-{width}.jpg"
    if not f.exists():
        req = urllib.request.Request(f"{cs.APPWRITE}/tablesdb/cjw/tables/packs/rows/{pack_id}", headers={"X-Appwrite-Project": cs.PROJECT})
        url = json.load(urllib.request.urlopen(req))["coverUrl"]
        url = re.sub(r"width=\d+", f"width={width}", url) if "width=" in url else url.replace("/view?", "/preview?") + f"&width={width}"
        f.write_bytes(urllib.request.urlopen(url, timeout=60).read())
    return str(f)


def masonry(items: list[str], cols: int, w: int, gap: int, offsets: list[int], end: int, radius: int) -> list[dict]:
    """A wall of pictures in staggered columns across the slide, down to y = end."""
    heights = [380, 300, 420, 330, 360, 400]
    x0 = (W - (cols * w + (cols - 1) * gap)) / 2
    out, k = [], 0
    for c in range(cols):
        y = offsets[c % len(offsets)]
        n = c
        while y < end - 120:
            h = heights[n % len(heights)]
            out.append({"src": items[k % len(items)], "x": round(x0 + c * (w + gap)), "y": y, "w": w, "h": min(h, end - y), "r": 0, "radius": radius})
            y += h + gap; n += 1; k += 1
    return out


FONTS = {  # headline face: file, weight, tracking (em)
    "rounded": ("/System/Library/Fonts/SFNSRounded.ttf", 700, -0.012),
    "display": ("/System/Library/Fonts/SFNS.ttf", 700, -0.018),
    "newyork": ("/System/Library/Fonts/NewYork.ttf", 650, -0.01),
}
PHONE_W = 1000  # outer phone width on every slide
HEAD_SIZE, MEASURE = 136, 1180  # headline px; widest line allowed


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


def crop_box(capture_name: str, spec) -> tuple[int, int, int, int]:
    """A crop box: "board" (the capture's board), "rect:<name>" (a rectangle the capture test recorded in
    boards.json, in the capture's theme) or (l, t, r, b) in capture px."""
    if spec == "board":
        return board(capture_name)
    if isinstance(spec, str) and spec.startswith("rect:"):
        return board(spec[5:] + ("_light" if capture_name.endswith("_light") else ""))
    return tuple(spec)


def phone_screen() -> tuple[float, float]:
    """Where a capture sits inside the phone frame of compose_screenshots.phone(): offset, scale."""
    band, bezel = round(PHONE_W * 0.011), round(PHONE_W * 0.026)
    return band + bezel, (PHONE_W - 2 * (band + bezel)) / cs.RAW_W


def export_parts(parts: Path, slide_list: list[dict]) -> list[dict]:
    """Phones (one size), lifted cards and slide pictures for every slide, as files the template loads."""
    off, k = phone_screen()
    covers = [cs.COLLAGE / f"{p}.jpg" for p in cs.COLLAGE_PACKS if (cs.COLLAGE / f"{p}.jpg").exists()]
    out_slides = []
    for i, s in enumerate(slide_list, start=1):
        dark = bool(s.get("dark"))
        edge = (20, 20, 24) if dark else (240, 240, 244)
        anchor, ty, align = s["text"]
        d = {"head": s["head"], "brand": s.get("brand", False), "dark": dark, "text": {"anchor": anchor, "y": ty, "align": align}, "phones": []}
        for pi, ph in enumerate(s["phones"]):
            n = capture(ph["capture"], dark)
            f = f"phone-{n}.png"
            if not (parts / f).exists():
                cs.phone(cs.load_raw(n), PHONE_W, edge).save(parts / f)
            outs = []
            for j, o in enumerate(ph.get("out", [])):
                cn = capture(o["crop"][0], dark)
                box = crop_box(cn, o["crop"][1])
                cf = f"crop-{i}-{pi}-{j}.png"
                cs.load_raw(cn).crop(box).save(parts / cf)
                h = (box[3] - box[1]) * o["w"] / (box[2] - box[0])
                x = o.get("x", off + (box[0] + box[2]) / 2 * k - o["w"] / 2)
                y = o.get("y", off + (box[1] + box[3]) / 2 * k - h / 2)
                outs.append({"img": cf, "x": round(x), "y": round(y), "w": o["w"], "rot": o.get("rot", 0),
                             "radius": o.get("radius", 34), "label": o.get("label", ""), "label_at": o.get("label_at", "bottom")})
            tags = []
            for t in ph.get("tags", []):
                if "edge" in t:  # centred on the board's top or bottom edge
                    bl, bt, br, bb = board(n)
                    tags.append({"text": t["text"], "x": round(off + (bl + br) / 2 * k), "y": round(off + (bt if t["edge"] == "top" else bb) * k)})
                else:
                    tags.append(t)
            d["phones"].append({"img": f, "x": ph["x"], "y": ph["y"], "rot": ph.get("rot", 0), "out": outs, "tags": tags})
        d["pics"] = []
        for j, g in enumerate(s.get("pics", [])):
            if "packs" in g:
                srcs = [cover(pid) for pid in g["packs"]]
            elif "covers" in g:
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
            if "row" in g:
                d["pics"] += row(srcs, radius=radius, **g["row"])
            elif "hand" in g:
                d["pics"] += hand(srcs, radius=radius, **g["hand"])
            elif "masonry" in g:
                d["pics"] += masonry(srcs, radius=radius, **g["masonry"])
            elif "fan" in g:
                d["pics"] += fan(srcs, radius=radius, **g["fan"])
            else:
                d["pics"] += [{"src": src, "x": x, "y": y, "w": round(hh * .83), "h": hh, "r": r, "radius": radius}
                              for src, (x, y, hh, r) in zip(srcs, g["spots"])]
        out_slides.append(d)
    return out_slides


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


def render(page: Path, n, out: Path) -> None:
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


INK = {"light": (0x11, 0x11, 0x18), "dark": (0xF5, 0xF5, 0xF8)}  # headline colours (slides.html)
MIN_CONTRAST = 4.5  # headline ink against the 2% of its background that is closest to the ink


def luminance(rgb) -> "object":
    import numpy as np
    c = np.asarray(rgb, dtype=float) / 255
    c = np.where(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def contrast_report(page: Path, slide_list: list[dict], weight: int, track: float, font_file: str) -> list[tuple]:
    """Renders every slide without its headline and measures the headline ink against what lies
    behind each line (the 2nd percentile: the worst small area, not the average)."""
    import numpy as np
    from PIL import ImageFont
    font = ImageFont.truetype(font_file, HEAD_SIZE)
    try:
        font.set_variation_by_axes([400, weight])
    except Exception:
        pass
    rows = []
    with tempfile.TemporaryDirectory() as d:
        for n, sl in enumerate(slide_list, start=1):
            out = Path(d) / f"{n}.png"
            render(page, f"{n}-notext", out)
            bg = np.asarray(Image.open(out).convert("RGB"))
            lines = sl["head"].split("\n")
            anchor, ty, align = sl["text"]
            widths = [font.getlength(l) * (1 + track) for l in lines]
            measure = MEASURE if align == "center" else MEASURE - 40
            size = min(HEAD_SIZE, int(HEAD_SIZE * measure / max(widths)))
            k, lh = size / HEAD_SIZE, size * 1.06
            top = ty if anchor == "top" else ty - len(lines) * lh if anchor == "bottom" else ty - len(lines) * lh / 2
            ink = INK["dark" if sl.get("dark") else "light"]
            li = (luminance(ink) + 0.05)
            worst = 99.0
            for i, wpx in enumerate(widths):
                wpx *= k
                x0 = 90 if align == "left" else W - 90 - wpx if align == "right" else (W - wpx) / 2
                y0 = top + i * lh + size * 0.12
                box = bg[int(y0):int(y0 + size * 0.86), int(max(0, x0)):int(min(W, x0 + wpx))]
                lum = luminance(box).ravel()
                if sl.get("dark"):  # light ink: the brightest bits behind it are the worst
                    c = li / (np.percentile(lum, 98) + 0.05)
                else:  # dark ink: the darkest bits are the worst
                    c = (np.percentile(lum, 2) + 0.05) / li
                worst = min(worst, c)
            rows.append((n, sl["head"].replace("\n", " "), round(worst, 2)))
    return rows


def main(argv: list[str]) -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("only", nargs="*", type=int, help="slide numbers to render (default: all)")
    ap.add_argument("--font", choices=FONTS, default="rounded")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--sheet", type=Path, help="also write a contact sheet of the whole set")
    ap.add_argument("--contrast", action="store_true", help="measure every headline against its background and stop")
    a = ap.parse_args(argv)

    build = ROOT / "build" / "store-glass"
    parts = build / "parts"
    parts.mkdir(parents=True, exist_ok=True)
    for f in parts.glob("*.png"):
        f.unlink()
    font_file, weight, track = FONTS[a.font]
    slide_list = slides()
    data = {"W": W, "H": H, "slides": export_parts(parts, slide_list), "panes": panes(len(slide_list)), "glass": glass_tones(),
            "body": BODY_OPACITY, "shadow": SHADOW_OPACITY,
            "parts": str(parts), "icon": str(ICON), "phone_w": PHONE_W,
            "phone_h": Image.open(next(parts.glob("phone-*.png"))).height,
            "head_size": HEAD_SIZE, "measure": MEASURE,
            "font": {"weight": weight, "track": track}}
    page = build / "slides.html"
    page.write_text(TEMPLATE.read_text().replace("__DATA__", json.dumps(data)).replace("__FONT__", font_file))

    if a.contrast:
        for n, head, c in contrast_report(page, slide_list, weight, track, font_file):
            print(f"{n:02d}  {c:5.2f}  {'ok' if c >= MIN_CONTRAST else 'LOW'}  {head}")
        return
    a.out.mkdir(parents=True, exist_ok=True)
    todo = a.only or list(range(1, len(slide_list) + 1))
    for n in todo:
        render(page, n, a.out / f"{n:02d}.png")
        print(f"{n:02d}  {slide_list[n - 1]['head'].replace(chr(10), ' ')}")
    if not a.only:  # a shorter set: drop numbered slides past the end
        for f in a.out.glob("[0-9][0-9].png"):
            if int(f.stem) > len(slide_list):
                f.unlink()
                print(f"removed {f.name}")
    if a.sheet:
        cs.contact_sheet(sorted(a.out.glob("[0-9][0-9].png")), a.sheet)
        print(f"sheet {a.sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
