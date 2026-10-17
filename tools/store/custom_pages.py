#!/usr/bin/env python3
"""Custom product pages for Carden: compose their screenshots and keep them as DRAFTS on App Store Connect.

    .venv/bin/python tools/store/custom_pages.py compose [SLUG ...]      # slides -> store/custom/<slug>/01.png ...
    .venv/bin/python tools/store/custom_pages.py compose --contrast      # measure every headline, write nothing
    .venv/bin/python tools/store/custom_pages.py list                    # what exists on Apple (ids, states, URLs, counts)
    .venv/bin/python tools/store/custom_pages.py plan [SLUG ...]         # what `sync` would change (reads Apple, writes nothing)
    .venv/bin/python tools/store/custom_pages.py sync [SLUG ...]         # create or update the drafts on Apple

A page is defined in store/metadata/custom_pages/<slug>.json: its reference name (the name in App Store
Connect), promotional text, optional deep link, the app keywords it should take over in search, and its
slides. Slides use the format of slides() in tools/store/compose_glass.py, plus two shortcuts: {"default": "daily"}
reuses the default set's slide with that `key` (a number still picks a slide by position; any other key given
next to it overrides that key), and a crop box can be
a name from BOXES below, {"cell": [cols, rows, c, r]} or {"part": [fx0, fy0, fx1, fy1]} of the capture's board.
Every slide is rendered with the default set's look (panes, phone, SF Pro Rounded) from the light captures in
store/raw/ (the dark finale from the dark ones).

`sync` never submits anything for review and never touches the default product page: it creates the page
(name, first version, en-GB localization), sets the deep link and promotional text, uploads the 6.9-inch
screenshot set (the folder is the source of truth, as in asc_publish.py screenshots), and assigns keywords
once the app has approved keywords. A version that is waiting for or in review is left alone; an approved one
gets a new draft version only with --new-version. Apple ids and URLs are recorded in
store/metadata/custom_pages/apple.json. Research, the pages and how to submit them:
tools/store/custom-product-pages.md.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_publish as ap  # noqa: E402  (App Store Connect client, uploads, credentials)
from asc_publish import ApiError, attr, log, md5_of, rel, rel_many  # noqa: E402

ROOT = ap.ROOT
DEFS = ROOT / "store" / "metadata" / "custom_pages"
APPLE_FILE = DEFS / "apple.json"
NOT_PAGES = {"apple.json", "header_assets.json"}  # files in DEFS that are not page definitions
OUT = ROOT / "store" / "custom"
BUILD = ROOT / "build" / "store-custom"
SCREENSHOT_TYPE = ap.SCREENSHOT_TYPE  # the 6.9-inch iPhone set, as on the default product page
PROMO_LIMIT = 170
EDITABLE_STATES = ("PREPARE_FOR_SUBMISSION", "REJECTED")
IN_REVIEW_STATES = ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW")
LIVE_STATES = ("ACCEPTED", "APPROVED")

# Named crop boxes (capture px, 1320 x 2868) for the custom slides. Check them on a coordinate grid after new
# captures; the default set's own boxes (EVENT_CARD, PODIUM, STREAK_CARD) come from compose_glass.py.
BOXES = {
    "TOOLBAR": (14, 2578, 1306, 2780),       # Shuffle, Peek, Magic, Hint on any board
    "ALPINE_TILE": (58, 604, 630, 1340),     # Alpine Lakes tile in 28_library_more
    "AUGUST_TILE": (58, 1596, 630, 2340),    # August 2026 tile in 16_library_daily
    "GIANT_MAP": (992, 636, 1262, 1048),     # overview map in 30_giant_zoom
    "TODAY_CARD": (60, 530, 1260, 775),      # today's picture on the daily calendar (18_daily_month_grid)
}


# ---------------------------------------------------------------------------------------------
# Definitions
# ---------------------------------------------------------------------------------------------

def load_defs(slugs: list[str] | None = None) -> list[dict]:
    pages = []
    for f in sorted(DEFS.glob("*.json")):
        if f.name in NOT_PAGES:
            continue
        d = json.loads(f.read_text(encoding="utf-8"))
        d["slug"] = f.stem
        pages.append(d)
    if slugs:
        unknown = set(slugs) - {p["slug"] for p in pages}
        if unknown:
            sys.exit(f"no page definition for: {', '.join(sorted(unknown))} (see {DEFS.relative_to(ROOT)})")
        pages = [p for p in pages if p["slug"] in slugs]
    pages.sort(key=lambda p: (p.get("order", 99), p["slug"]))
    for p in pages:
        check_def(p)
    return pages


def check_def(p: dict) -> None:
    where = f"{p['slug']}.json"
    for key in ("referenceName", "promotionalText", "slides"):
        if not p.get(key):
            sys.exit(f"{where}: `{key}` is missing")
    if len(p["promotionalText"]) > PROMO_LIMIT:
        sys.exit(f"{where}: promotional text is {len(p['promotionalText'])} characters (limit {PROMO_LIMIT})")
    if len(p["referenceName"]) > 64:
        sys.exit(f"{where}: reference name is longer than 64 characters")
    link = p.get("deepLink")
    if link and not (link.startswith("https://play.carden.page/") or link.startswith("carden://")):
        sys.exit(f"{where}: deep link must be a https://play.carden.page/ universal link or a carden:// link")
    if not 1 <= len(p["slides"]) <= 10:
        sys.exit(f"{where}: Apple takes 1 to 10 screenshots per set")


def load_apple() -> dict:
    if APPLE_FILE.exists():
        return json.loads(APPLE_FILE.read_text(encoding="utf-8"))
    return {}


def save_apple(data: dict) -> None:
    APPLE_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def short_url(page_id: str) -> str:
    """The page's link without the name slug Apple puts in `url` (that slug still reads the app's first
    name). Both forms open the same page."""
    return f"https://apps.apple.com/app/id{ap.APP_ID}?ppid={page_id}"


# ---------------------------------------------------------------------------------------------
# Compose (the glass look of tools/store/compose_glass.py)
# ---------------------------------------------------------------------------------------------

def _glass():
    import compose_glass as cg  # imported late: it needs Pillow and the raw captures only for `compose`
    return cg


def resolve_box(cg, capture: str, box):
    if box == "board" or (isinstance(box, str) and box.startswith("rect:")):
        return box  # compose_glass.crop_box reads these per capture
    if isinstance(box, str):
        if box in BOXES:
            return BOXES[box]
        if box.startswith("STARRED_"):
            return cg.STARRED[int(box.split("_")[1])]
        if hasattr(cg, box):
            return getattr(cg, box)
        sys.exit(f"unknown crop box name {box!r} (BOXES in custom_pages.py, or a constant of compose_glass.py)")
    if isinstance(box, dict):
        if "cell" in box:
            return cg.cell(capture, *box["cell"])
        if "part" in box:
            return cg.board_part(capture, *box["part"])
    return tuple(box)


def resolve_slide(cg, spec: dict, defaults: list[dict]) -> dict:
    """A slide of the definition as compose_glass expects it (tuples, resolved crop boxes). `default`
    names a slide of the default set by its key ("daily"; also compose_glass.EXTRA_SLIDES), or by its
    number in the set."""
    spec = {k: v for k, v in spec.items() if k != "note"}
    if "default" in spec:
        n = spec.pop("default")
        if isinstance(n, str):
            named = {s["key"]: s for s in defaults + getattr(cg, "EXTRA_SLIDES", []) if "key" in s}
            if n not in named:
                sys.exit(f"there is no default slide {n!r} (keys: {', '.join(named)})")
            out = copy.deepcopy(named[n])
        else:
            if not 1 <= n <= len(defaults):
                sys.exit(f"there is no default slide {n} (the default set has {len(defaults)})")
            out = copy.deepcopy(defaults[n - 1])
        out.pop("key", None)
        out.update(copy.deepcopy(spec))
    else:
        out = copy.deepcopy(spec)
    out["text"] = tuple(out["text"])
    for ph in out.get("phones", []):
        for o in ph.get("out", []):
            cap, box = o["crop"]
            o["crop"] = (cap, resolve_box(cg, cap, box))
    for g in out.get("pics", []):
        if "crops" in g:
            g["crops"] = [(cap, resolve_box(cg, cap, box)) for cap, box in g["crops"]]
        if "spots" in g:
            g["spots"] = [tuple(s) for s in g["spots"]]
    return out


def compose(page: dict, contrast_only: bool, font: str) -> list[tuple]:
    cg = _glass()
    slide_list = [resolve_slide(cg, s, cg.slides()) for s in page["slides"]]
    build = BUILD / page["slug"]
    parts = build / "parts"
    parts.mkdir(parents=True, exist_ok=True)
    for f in parts.glob("*.png"):
        f.unlink()
    font_file, weight, track = cg.FONTS[font]
    from PIL import Image
    data = {"W": cg.W, "H": cg.H, "slides": cg.export_parts(parts, slide_list), "panes": cg.panes(len(slide_list)),
            "glass": cg.glass_tones(), "body": cg.BODY_OPACITY, "shadow": cg.SHADOW_OPACITY,
            "parts": str(parts), "icon": str(cg.ICON), "phone_w": cg.PHONE_W,
            "phone_h": Image.open(next(parts.glob("phone-*.png"))).height,
            "head_size": cg.HEAD_SIZE, "measure": cg.MEASURE, "font": {"weight": weight, "track": track}}
    html = build / "slides.html"
    html.write_text(cg.TEMPLATE.read_text().replace("__DATA__", json.dumps(data)).replace("__FONT__", font_file))
    rows = cg.contrast_report(html, slide_list, weight, track, font_file)
    if contrast_only:
        return rows
    out = OUT / page["slug"]
    out.mkdir(parents=True, exist_ok=True)
    for n in range(1, len(slide_list) + 1):
        cg.render(html, n, out / f"{n:02d}.png")
    for f in out.glob("[0-9][0-9].png"):  # a shorter set: drop slides past the end
        if int(f.stem) > len(slide_list):
            f.unlink()
    return rows


def cmd_compose(pages: list[dict], contrast_only: bool, font: str, sheet: Path | None) -> int:
    cg = _glass()
    low = 0
    for p in pages:
        log(f"== {p['slug']}: {p['referenceName']}")
        rows = compose(p, contrast_only, font)
        for n, head, c in rows:
            ok = c >= cg.MIN_CONTRAST
            low += not ok
            log(f"  {n:02d}  {c:5.2f}  {'ok ' if ok else 'LOW'}  {head}")
        if not contrast_only:
            log(f"  -> {(OUT / p['slug']).relative_to(ROOT)}/01.png ... {len(p['slides']):02d}.png")
            if sheet:
                sheet.mkdir(parents=True, exist_ok=True)
                cg.cs.contact_sheet(sorted((OUT / p["slug"]).glob("[0-9][0-9].png")), sheet / f"{p['slug']}.png")
    if low:
        log(f"{low} headline(s) below {cg.MIN_CONTRAST}:1; move a pane or the headline (see the store-screenshots skill)")
    return 1 if low else 0


# ---------------------------------------------------------------------------------------------
# App Store Connect
# ---------------------------------------------------------------------------------------------

class PlanClient(ap.Client):
    """Reads Apple for real, prints every write instead of sending it."""

    def request(self, method, path, body=None, params=None, raw=None, headers=None, allow_404=False):
        if method == "GET":
            return super().request(method, path, body, params, raw, headers, allow_404)
        self._dry_counter += 1
        url = path if path.startswith("http") else ap.API + path
        if raw is not None:
            log(f"  [plan] {method} <upload> ({len(raw)} bytes)")
            return {}
        log(f"  [plan] {method} {url}")
        if body is not None and not path.endswith("/relationships/appScreenshots"):
            log("         " + json.dumps(body)[:600])
        return self._dry_response(method, path, body)


class Pages:
    def __init__(self, client: ap.Client, args: argparse.Namespace):
        self.c = client
        self.s = ap.Store(client, args)
        self.args = args
        self.plan = isinstance(client, PlanClient)
        self.locale = ap.LOCALE

    # -- lookups ---------------------------------------------------------------------------

    def pages(self) -> list[dict]:
        return self.c.get_list(f"/v1/apps/{ap.APP_ID}/appCustomProductPages", limit=50)

    def versions(self, page_id: str) -> list[dict]:
        vs = self.c.get_list(f"/v1/appCustomProductPages/{page_id}/appCustomProductPageVersions", limit=50)
        return sorted(vs, key=lambda v: int(attr(v, "version") or 0))

    def localizations(self, version_id: str) -> list[dict]:
        return self.c.get_list(f"/v1/appCustomProductPageVersions/{version_id}/appCustomProductPageLocalizations", limit=50)

    def screenshot_sets(self, loc_id: str) -> list[dict]:
        return self.c.get_list(f"/v1/appCustomProductPageLocalizations/{loc_id}/appScreenshotSets", limit=50)

    def app_keywords(self) -> list[dict]:
        return self.s.cached("keywords", lambda: self.c.get_list(
            f"/v1/apps/{ap.APP_ID}/searchKeywords", {"filter[locale]": self.locale, "filter[platform]": ap.PLATFORM}, limit=200))

    def assigned_keywords(self, loc_id: str) -> list[dict]:
        try:
            return self.c.get_list(f"/v1/appCustomProductPageLocalizations/{loc_id}/searchKeywords", limit=200)
        except ApiError as e:
            log(f"    keywords: could not read ({e.status})")
            return []

    # -- sync ------------------------------------------------------------------------------

    def find(self, d: dict, existing: list[dict], apple: dict) -> dict | None:
        known = (apple.get(d["slug"]) or {}).get("id")
        for p in existing:
            if p["id"] == known:
                return p
        return next((p for p in existing if attr(p, "name") == d["referenceName"]), None)

    def sync(self, d: dict, existing: list[dict], apple: dict) -> None:
        log(f"== {d['slug']}: {d['referenceName']}")
        shots = sorted((OUT / d["slug"]).glob("[0-9][0-9].png"))
        if not shots:
            log(f"  no screenshots in {(OUT / d['slug']).relative_to(ROOT)}; run `custom_pages.py compose {d['slug']}` first")
            return
        page = self.find(d, existing, apple)
        link = d.get("deepLink") or None
        if page is None:
            log(f"  appCustomProductPage: creating (version 1, {self.locale})")
            body = {"data": {"type": "appCustomProductPages", "attributes": {"name": d["referenceName"]},
                             "relationships": {"app": rel("apps", ap.APP_ID),
                                               "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": "${v1}"}]}}},
                    "included": [
                        {"type": "appCustomProductPageVersions", "id": "${v1}", "attributes": {"deepLink": link},
                         "relationships": {"appCustomProductPageLocalizations": {"data": [{"type": "appCustomProductPageLocalizations", "id": "${l1}"}]}}},
                        {"type": "appCustomProductPageLocalizations", "id": "${l1}",
                         "attributes": {"locale": self.locale, "promotionalText": d["promotionalText"]}}]}
            try:
                resp = self.c.request("POST", "/v1/appCustomProductPages", body) or {}
            except ApiError as e:
                if not e.mentions("deepLink"):
                    raise
                log("  deep link refused on create; creating without it and setting it afterwards")
                body["included"][0].pop("attributes")
                resp = self.c.request("POST", "/v1/appCustomProductPages", body) or {}
            page = resp.get("data") or {"id": "DRY-page", "attributes": {"name": d["referenceName"]}}
        elif attr(page, "name") != d["referenceName"]:
            log(f"  appCustomProductPage: renaming {attr(page, 'name')!r} -> {d['referenceName']!r}")
            self.c.update("appCustomProductPages", page["id"], {"name": d["referenceName"]})
        if not self.plan and not page["id"].startswith("DRY"):
            apple[d["slug"]] = {"id": page["id"], "name": d["referenceName"], "url": attr(page, "url"), "shortUrl": short_url(page["id"])}

        version = self.editable_version(page)
        if version is None:
            return
        vid = version["id"]
        if (attr(version, "deepLink") or None) != link and not vid.startswith("DRY"):
            log(f"  deep link: {attr(version, 'deepLink')} -> {link}")
            try:
                self.c.update("appCustomProductPageVersions", vid, {"deepLink": link})
            except ApiError as e:
                log(f"  deep link: Apple refused it ({e}); set it in App Store Connect")

        locs = self.localizations(vid) if not vid.startswith("DRY") else []
        loc = next((l for l in locs if attr(l, "locale") == self.locale), None)
        if loc is None and not vid.startswith("DRY"):
            log(f"  localization {self.locale}: creating")
            loc = self.c.create("appCustomProductPageLocalizations", {"locale": self.locale, "promotionalText": d["promotionalText"]},
                                {"appCustomProductPageVersion": rel("appCustomProductPageVersions", vid)})
        elif loc is not None and attr(loc, "promotionalText") != d["promotionalText"]:
            log(f"  localization {self.locale}: updating promotional text")
            self.c.update("appCustomProductPageLocalizations", loc["id"], {"promotionalText": d["promotionalText"]})
        elif loc is not None:
            log(f"  localization {self.locale}: promotional text up to date")
        if loc is None or not loc.get("id") or str(loc["id"]).startswith("DRY"):
            log(f"  screenshots: {len(shots)} to upload once the page exists")
            return
        self.upload_screenshots(loc, shots, d["slug"])
        self.sync_keywords(loc, d)

    def editable_version(self, page: dict) -> dict | None:
        if page["id"].startswith("DRY"):
            return {"id": "DRY-version", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}
        versions = self.versions(page["id"])
        latest = versions[-1] if versions else None
        state = attr(latest, "state")
        if latest is not None and state in EDITABLE_STATES:
            log(f"  version {attr(latest, 'version')}: {state} (draft)")
            return latest
        if state in IN_REVIEW_STATES:
            log(f"  version {attr(latest, 'version')}: {state}; left alone until review ends")
            return None
        if latest is not None and not self.args.new_version:
            log(f"  version {attr(latest, 'version')}: {state}; pass --new-version to start a new draft version")
            return None
        log("  appCustomProductPageVersion: creating a new draft version")
        return self.c.create("appCustomProductPageVersions", None, {"appCustomProductPage": rel("appCustomProductPages", page["id"])})

    def upload_screenshots(self, loc: dict, shots: list[Path], slug: str) -> None:
        """The folder is the source of truth: changed files are replaced, missing ones removed, order kept."""
        sets = [s for s in self.screenshot_sets(loc["id"]) if attr(s, "screenshotDisplayType") == SCREENSHOT_TYPE]
        if sets:
            sset = sets[0]
        else:
            log(f"  appScreenshotSet {SCREENSHOT_TYPE}: creating")
            sset = self.c.create("appScreenshotSets", {"screenshotDisplayType": SCREENSHOT_TYPE},
                                 {"appCustomProductPageLocalization": rel("appCustomProductPageLocalizations", loc["id"])})
        existing = self.c.get_list(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots") if not str(sset.get("id", "")).startswith("DRY") else []
        local = {p.name: p for p in shots}
        kept = []
        for res in existing:
            name, png = attr(res, "fileName"), local.get(attr(res, "fileName"))
            checksum = attr(res, "sourceFileChecksum")
            if png is None:
                log(f"  appScreenshots: {name} is not in store/custom/{slug}, deleting")
                self.c.request("DELETE", f"/v1/appScreenshots/{res['id']}")
            elif checksum and checksum != md5_of(png):
                log(f"  appScreenshots: {name} changed, replacing")
                self.c.request("DELETE", f"/v1/appScreenshots/{res['id']}")
            else:
                kept.append(res)
        uploaded = []
        for png in shots:
            res = self.s.upload_asset("appScreenshots", {"appScreenshotSet": rel("appScreenshotSets", sset["id"])}, png, kept)
            if res and res.get("id"):
                uploaded.append(res["id"])
        if uploaded and uploaded != [e["id"] for e in kept]:
            log("  appScreenshotSet: setting order")
            self.c.request("PATCH", f"/v1/appScreenshotSets/{sset['id']}/relationships/appScreenshots", rel_many("appScreenshots", uploaded))

    def sync_keywords(self, loc: dict, d: dict) -> None:
        wanted = [k.lower() for k in d.get("keywords") or []]
        if not wanted:
            return
        app_kw = self.app_keywords()
        if not app_kw:
            log(f"  keywords: the app has no approved keywords yet; {', '.join(wanted)} can be assigned after the first App Store approval")
            return
        by_word = {str(k["id"]).lower(): k["id"] for k in app_kw}
        missing = [w for w in wanted if w not in by_word]
        if missing:
            log(f"  keywords: not in the app's approved keywords: {', '.join(missing)}")
        have = {str(k["id"]).lower() for k in self.assigned_keywords(loc["id"])}
        add = [by_word[w] for w in wanted if w in by_word and w not in have]
        if add:
            log(f"  keywords: assigning {', '.join(add)}")
            try:
                self.c.request("POST", f"/v1/appCustomProductPageLocalizations/{loc['id']}/relationships/searchKeywords", rel_many("appKeywords", add))
            except ApiError as e:
                log(f"  keywords: Apple refused ({e}); assign them in App Store Connect")
        else:
            log("  keywords: up to date")

    # -- list ------------------------------------------------------------------------------

    def describe(self, defs: list[dict], apple: dict, only: list[str] | None = None) -> None:
        existing = self.pages()
        by_slug = {d["slug"]: self.find(d, existing, apple) for d in defs}
        matched = {p["id"] for p in by_slug.values() if p}
        log(f"{len(existing)} custom product page(s) on Apple for app {ap.APP_ID} (limit 70)")
        for d in defs:
            if only and d["slug"] not in only:
                continue
            p = by_slug[d["slug"]]
            if p is None:
                log(f"\n{d['slug']}: {d['referenceName']}  (not on Apple yet)")
                continue
            self._describe_page(p, d["slug"])
        for p in existing:
            if p["id"] not in matched and not only:
                self._describe_page(p, "(no local definition)")

    def _describe_page(self, p: dict, slug: str) -> None:
        log(f"\n{slug}: {attr(p, 'name')}")
        log(f"  id {p['id']}  visible={attr(p, 'visible')}")
        log(f"  url   {attr(p, 'url')}")
        log(f"  short {short_url(p['id'])}")
        for v in self.versions(p["id"]):
            log(f"  version {attr(v, 'version')}: {attr(v, 'state')}  deep link: {attr(v, 'deepLink') or '-'}")
            for l in self.localizations(v["id"]):
                promo = attr(l, "promotionalText") or ""
                counts = []
                for sset in self.screenshot_sets(l["id"]):
                    n = len(self.c.get_list(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots"))
                    counts.append(f"{attr(sset, 'screenshotDisplayType')}={n}")
                kws = [str(k["id"]) for k in self.assigned_keywords(l["id"])]
                log(f"    {attr(l, 'locale')}: promo {len(promo)} chars; screenshots {', '.join(counts) or 'none'}; keywords {', '.join(kws) or '-'}")


def main(argv: list[str] | None = None) -> int:
    ap_ = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap_.add_argument("command", choices=["compose", "list", "plan", "sync"])
    ap_.add_argument("slugs", nargs="*", help="page slugs (file names in store/metadata/custom_pages); default: all")
    ap_.add_argument("--contrast", action="store_true", help="with compose: only measure the headlines")
    ap_.add_argument("--font", default="rounded", help="with compose: rounded (default) | display | newyork")
    ap_.add_argument("--sheet", type=Path, help="with compose: also write a contact sheet per page into this folder")
    ap_.add_argument("--new-version", action="store_true", help="with sync: start a new draft version of a page whose latest version is approved")
    ap_.add_argument("--verbose", "-v", action="store_true")
    args = ap_.parse_args(argv)
    defs = load_defs(args.slugs or None)

    if args.command == "compose":
        return cmd_compose(defs, args.contrast, args.font, args.sheet)

    client = PlanClient(dry_run=False, verbose=args.verbose) if args.command == "plan" else ap.Client(dry_run=False, verbose=args.verbose)
    store = ap.Store(client, args)
    app = store.app()
    if not app:
        sys.exit(f"could not read app {ap.APP_ID}; check the key and the Issuer ID")
    ap.LOCALE = attr(app, "primaryLocale") or ap.LOCALE
    pages = Pages(client, args)
    pages.locale = ap.LOCALE
    apple = load_apple()
    try:
        if args.command == "list":
            pages.describe(load_defs(None), apple, args.slugs or None)
            return 0
        if args.command == "plan":
            log("plan: reads App Store Connect, sends no changes")
        existing = pages.pages()
        for d in defs:
            pages.sync(d, existing, apple)
        if args.command == "sync":
            save_apple(apple)
            log(f"\nids and URLs: {APPLE_FILE.relative_to(ROOT)}. Nothing was submitted for review.")
    except ApiError as err:
        log(f"error: {err}")
        if args.command == "sync":
            save_apple(apple)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
