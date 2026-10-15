#!/usr/bin/env python3
"""Render the Carden app icon (tools/brand/icon-glass.js, id FINAL) into every icon file the app ships.

  python3 tools/brand/export_icon.py          # writes iOS, web, Android, README and store icons

Needs node, Pillow and a Chromium (CHROME=/path/to/chrome, else Playwright's or Google Chrome).
Each look is drawn at 2048 px and scaled down, so small sizes stay crisp:
  light   opaque white ground (the App Store icon must have no alpha)
  dark    artwork on transparent; iOS draws the dark ground itself
  tinted  grey artwork on transparent; iOS tints it with the person's colour
"""
from __future__ import annotations
import glob, json, os, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "tools/brand"
APPICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

def chrome() -> str:
    if os.environ.get("CHROME"): return os.environ["CHROME"]
    hits = glob.glob(os.path.expanduser("~/Library/Caches/ms-playwright/chromium-*/chrome-mac*/*.app/Contents/MacOS/*"))
    for c in sorted(hits, reverse=True) + ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]:
        if os.path.exists(c): return c
    sys.exit("no Chromium found: set CHROME")

def svg(mode: str, **opts) -> str:
    js = f"const m = require({json.dumps(str(BRAND / 'icon-glass.js'))}); process.stdout.write(m.svg(m.FINAL, {json.dumps(mode)}, {json.dumps(opts)}));"
    return subprocess.run(["node", "-e", "global.window = undefined;" + js], check=True, capture_output=True, text=True).stdout

def render(svg_text: str, out: Path, px: int = 2048) -> Image.Image:
    with tempfile.TemporaryDirectory() as d:
        page = Path(d) / "icon.html"
        page.write_text(f'<!doctype html><html><head><style>html,body{{margin:0;background:transparent}}svg{{display:block;width:1024px;height:1024px}}</style></head><body>{svg_text}</body></html>')
        subprocess.run([chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
                        f"--window-size=1024,1024", f"--force-device-scale-factor={px / 1024}", "--virtual-time-budget=4000",
                        f"--screenshot={out}", f"file://{page}"], check=True, capture_output=True)
    return Image.open(out).convert("RGBA")

def fit(im: Image.Image, size: int, opaque: bool) -> Image.Image:
    out = im.resize((size, size), Image.LANCZOS)
    if opaque:
        bg = Image.new("RGB", out.size, (255, 255, 255)); bg.paste(out, mask=out.split()[3]); return bg
    return out

def rounded(im: Image.Image, size: int) -> Image.Image:
    """The icon with iOS-like rounded corners on transparent (favicon, README)."""
    big = im.resize((size * 4, size * 4), Image.LANCZOS)
    mask = Image.new("L", big.size, 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, big.size[0] - 1, big.size[1] - 1), radius=int(big.size[0] * .2237), fill=255)
    big.putalpha(mask); return big.resize((size, size), Image.LANCZOS)

def main() -> None:
    tmp = Path(tempfile.mkdtemp())
    light = render(svg("light"), tmp / "light.png")
    dark = render(svg("dark", background=False), tmp / "dark.png")
    tinted = render(svg("tintD", background=False, tint="#FFFFFF"), tmp / "tinted.png")
    maskable = render(svg("light", scale=.8), tmp / "maskable.png")
    looks = {"light": (light, True), "dark": (dark, False), "tinted": (tinted, False)}

    contents = json.loads((APPICON / "Contents.json").read_text())
    n = 0
    for img in contents["images"]:
        look = (img.get("appearances") or [{"value": "light"}])[0]["value"]
        pts = float(img["size"].split("x")[0]); scale = int(img.get("scale", "1x").rstrip("x"))
        src, opaque = looks[look]
        fit(src, round(pts * scale), opaque).save(APPICON / img["filename"], "PNG", optimize=True); n += 1
    print(f"iOS: {n} files in {APPICON.relative_to(ROOT)}")

    web = ROOT / "web/icons"
    for name, size in [("Icon-192.png", 192), ("Icon-512.png", 512), ("apple-touch-icon.png", 180)]:
        fit(light, size, True).save(web / name, "PNG", optimize=True)
    for name, size in [("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)]:
        fit(maskable, size, True).save(web / name, "PNG", optimize=True)
    rounded(light, 64).save(ROOT / "web/favicon.png", "PNG", optimize=True)
    print("web: icons, maskable icons, apple-touch-icon, favicon")

    for folder, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        fit(light, size, True).save(ROOT / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png", "PNG", optimize=True)
    print("android: 5 launcher sizes")

    fit(light, 256, True).save(ROOT / "docs/images/app-icon.png", "PNG", optimize=True)
    (BRAND / "out").mkdir(exist_ok=True)
    fit(light, 1024, True).save(BRAND / "out/carden-icon-light-1024.png", "PNG", optimize=True)
    fit(dark, 1024, False).save(BRAND / "out/carden-icon-dark-1024.png", "PNG", optimize=True)
    fit(tinted, 1024, False).save(BRAND / "out/carden-icon-tinted-1024.png", "PNG", optimize=True)
    rounded(light, 512).save(BRAND / "out/carden-icon-rounded-512.png", "PNG", optimize=True)
    for mode, opts in [("light", {}), ("dark", {"background": False}), ("tintD", {"background": False, "tint": "#FFFFFF"})]:
        (BRAND / f"out/carden-icon-{'tinted' if mode == 'tintD' else mode}.svg").write_text(svg(mode, **opts))
    print("docs/images/app-icon.png and tools/brand/out/ (1024 PNGs, rounded 512, SVGs)")

if __name__ == "__main__":
    main()
