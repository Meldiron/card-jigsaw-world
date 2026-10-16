#!/usr/bin/env python3
"""App Store In-App Event metadata and media for the world-day events.

    make_app_events.py                    # write store/metadata/app_events.json from the live catalogue
    make_app_events.py --media-next 10    # also build the images of the events `asc_publish.py events` drafts:
                                          # the next 10 (starting 2+ days from now) and the next 5 major holidays after them
    make_app_events.py --media ev-halloween-2026 ev-diwali-2026

Every world-day event (table `events`, with its free event pack) becomes one In-App Event: the event's
own name, a short and a long description written from the pack, the event window as the event dates,
publishing 3 days before it opens (the day the app lists the event pack: Pack.isReleasedAt, soonWindow),
and a deep link to the pack (carden://library/pack/<packId>).
`asc_publish.py events` turns the next few into drafts in App Store Connect; nothing is ever submitted
from here (see tools/store/README.md, "In-App Events").

Major holidays (PRIMARY: Christmas, New Year's Eve, Lunar New Year, Valentine's Day, Easter, ...) are marked
"primary": true. Apple keeps 15 approved events but publishes only 10 at a time, so the drafts are the next
10 events plus the next 5 major holidays after them (`pick`, shared with asc_publish.py): the big days get
their slot months ahead instead of waiting for the date window to reach them.

Media (Apple's sizes, JPEG, no text on the art):
  event card    1920x1080 (16:9): three of the pack's pictures side by side, the pack cover in the middle
  details page  1080x1920 (9:16): the pack cover
built from our hosted pictures into ~/.local/share/card-jigsaw-world/app-events/<eventId>/ (outside
git, about 1 MB per event; override with CJW_APP_EVENT_MEDIA).

The catalogue comes from the daily snapshot (pointer row meta/catalog, read with
secrets/appwrite-api-key.txt; the file itself is public), so a run costs one billed read.
Entries with "locked": true in app_events.json are kept as they are (hand edits survive a re-run).
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import io
import json
import os
import re
import sys
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "metadata" / "app_events.json"
MEDIA = Path(os.environ.get("CJW_APP_EVENT_MEDIA", "~/.local/share/card-jigsaw-world/app-events")).expanduser()
ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT = "6acb4de5003e38d5ebd9"
KEY_FILE = ROOT / "secrets" / "appwrite-api-key.txt"

# Apple's limits (App Store Connect help, In-App Event metadata) and our defaults.
NAME_MAX, SHORT_MAX, LONG_MAX, REF_MAX = 30, 50, 120, 64
PUBLISH_DAYS_BEFORE = 3          # = Pack.soonWindow: the app lists an event pack 3 days before it opens, so
                                 # an earlier App Store card would link to a pack the app does not show yet
                                 # (Apple allows up to 14)
CARD = (1920, 1080)
DETAILS = (1080, 1920)
GAP = 12                         # dark gap between the card's three pictures
BACKDROP = (18, 19, 22)
OPEN_LINE = " Open for one week."

# Major holidays (event id without the year): the extra In-App Event slots go to these. One New Year
# (the Eve: fireworks and champagne; New Year's Day stays an ordinary event). Regional days
# (St Patrick's, Independence Day) and world days (Earth Day, Women's Day) stay in the date window.
PRIMARY = frozenset({
    "ev-christmas", "ev-new-years-eve", "ev-lunar-new-year", "ev-valentines", "ev-easter",
    "ev-mothers-day", "ev-fathers-day", "ev-halloween", "ev-diwali", "ev-thanksgiving",
})
WINDOW = 10                      # Apple publishes at most 10 events at a time
PRIMARY_SLOTS = 5                # and keeps 15 approved: the other 5 go to the next major holidays
LEAD_DAYS = 2                    # events starting sooner are left alone (too late for review)


def snapshot() -> dict:
    key = KEY_FILE.read_text().strip()
    h = {"X-Appwrite-Project": PROJECT, "X-Appwrite-Key": key}
    meta = requests.get(f"{ENDPOINT}/tablesdb/cjw/tables/meta/rows/catalog", headers=h, timeout=60).json()
    raw = requests.get(f"{ENDPOINT}/storage/buckets/catalog/files/{meta['fileId']}/view", params={"project": PROJECT}, timeout=120).content
    try:
        raw = gzip.decompress(raw)
    except OSError:
        pass
    data = json.loads(raw)
    tables = data.get("tables", data)
    return {t: (v["rows"] if isinstance(v, dict) else v) for t, v in tables.items()}


def is_primary(event_id: str) -> bool:
    return re.sub(r"-\d{4}$", "", event_id) in PRIMARY


def pick(events: list[dict], now: dt.datetime, window: int = WINDOW, primary: int = PRIMARY_SLOTS,
         lead_days: int = LEAD_DAYS) -> list[dict]:
    """The events to keep as In-App Event drafts, by start date: the next `window` events starting at
    least `lead_days` from now, then the next `primary` major holidays ("primary": true) after them."""
    soon = now + dt.timedelta(days=lead_days)
    upcoming = sorted((e for e in events if _utc(e["eventStart"]) >= soon), key=lambda e: e["eventStart"])
    extra = [e for e in upcoming[window:] if e.get("primary")][:primary]
    return upcoming[:window] + extra


def _utc(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def _z(t: dt.datetime) -> str:
    return t.isoformat().replace("+00:00", "Z")


def short_text(n: int, name: str) -> str:
    for text in (f"{n} pictures for {name}", f"{n} new pictures for the day", "New pictures for the day"):
        if len(text) <= SHORT_MAX:
            return text
    return text[:SHORT_MAX]


def long_text(pack_description: str) -> str:
    """The pack's subject list (its description after the first sentence) plus "Open for one week."
    when it fits Apple's 120 characters. Too long, it keeps as many whole items as fit and ends
    "x, y and z." (items that only qualify the list, "and other ...", "from ...", "playable for one
    week", are left out; a last item that already has "and" is not given another one)."""
    parts = pack_description.split(". ", 1)
    subjects = (parts[1] if len(parts) > 1 else parts[0]).strip().rstrip(".")
    subjects = re.sub(r",? *playable for (one|a) week$", "", subjects, flags=re.I).strip()
    if len(subjects) + 1 + len(OPEN_LINE) <= LONG_MAX:
        return subjects + "." + OPEN_LINE
    if len(subjects) + 1 <= LONG_MAX:
        return subjects + "."
    items = [i.strip() for i in subjects.split(", ")]
    items = [i for i in items if " and other " not in f" {i} " and not re.match(r"(from|and|playable) ", i)]
    for k in range(len(items), 1, -1):
        last = items[k - 1]
        text = (", ".join(items[:k]) if " and " in last else ", ".join(items[: k - 1]) + " and " + last) + "."
        if len(text) <= LONG_MAX:
            return text[0].upper() + text[1:]
    return (items[0] if items else subjects)[: LONG_MAX - 1] + "."


def entry(ev: dict, pack: dict, puzzles: list[dict]) -> dict:
    start = dt.datetime.fromisoformat(ev["startAt"].replace("Z", "+00:00"))
    end = dt.datetime.fromisoformat(ev["endAt"].replace("Z", "+00:00"))
    name = ev["name"].strip()
    warnings = []
    if len(name) > NAME_MAX:
        warnings.append(f"name is {len(name)} characters (Apple allows {NAME_MAX}); shorten it and set locked")
    if (end - start).days > 31:
        warnings.append("event is longer than 31 days")
    # The pack cover (the content tool's pick) leads: details page and the middle of the card.
    pics = sorted(puzzles, key=lambda p: (p.get("sortOrder") or 0, p["$id"]))
    cover = _file_id(pack.get("coverUrl"))
    lead = [p for p in pics if _file_id(p.get("imageUrl")) == cover][:1]
    pics = lead + [p for p in pics if p not in lead]
    return {
        "eventId": ev["$id"],
        "packId": pack["$id"],
        **({"primary": True} if is_primary(ev["$id"]) else {}),
        "referenceName": ev["$id"][:REF_MAX],
        "badge": "SPECIAL_EVENT",
        "purpose": "APPROPRIATE_FOR_ALL_USERS",
        "priority": "NORMAL",
        "purchaseRequirement": "NO_COST_ASSOCIATED" if pack.get("isFree") else "IN_APP_PURCHASE",
        "deepLink": f"carden://library/pack/{pack['$id']}",
        "publishStart": _z(start - dt.timedelta(days=PUBLISH_DAYS_BEFORE)),
        "eventStart": _z(start),
        "eventEnd": _z(end),
        "localization": {
            "name": name[:NAME_MAX],
            "shortDescription": short_text(len(pics), name),
            "longDescription": long_text(pack.get("description") or ""),
        },
        "pictures": [p["$id"] for p in pics[:3]],
        "media": {"card": f"{ev['$id']}/{ev['$id']}-card.jpg", "details": f"{ev['$id']}/{ev['$id']}-details.jpg"},
        **({"warnings": warnings} if warnings else {}),
    }


def _file_id(url: str | None) -> str | None:
    m = re.search(r"/files/([^/]+)/", url or "")
    return m.group(1) if m else None


def fit(img, size):
    """Centre-crop `img` to the aspect of `size`, then resize to it."""
    from PIL import Image
    w, h = img.size
    tw, th = size
    if w / h > tw / th:
        nw = round(h * tw / th)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = round(w * th / tw)
        img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return img.resize(size, Image.LANCZOS)


def build_media(e: dict, by_id: dict[str, dict]) -> None:
    from PIL import Image
    folder = MEDIA / e["eventId"]
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for pid in e["pictures"]:
        src = folder / f"src-{pid}.jpg"
        if not src.exists():
            r = requests.get(by_id[pid]["imageUrl"], timeout=120)
            r.raise_for_status()
            src.write_bytes(r.content)
        images.append(Image.open(src).convert("RGB"))
    if not images:
        print(f"  {e['eventId']}: no pictures, skipped")
        return
    while len(images) < 3:
        images.append(images[len(images) % len(images)])
    card = Image.new("RGB", CARD, BACKDROP)
    panel_w = (CARD[0] - 2 * GAP) // 3
    for i, img in enumerate([images[1], images[0], images[2]]):
        x = i * (panel_w + GAP)
        width = CARD[0] - x if i == 2 else panel_w
        card.paste(fit(img, (width, CARD[1])), (x, 0))
    card.save(MEDIA / e["media"]["card"], "JPEG", quality=90, optimize=True)
    fit(images[0], DETAILS).save(MEDIA / e["media"]["details"], "JPEG", quality=90, optimize=True)
    print(f"  {e['eventId']}: card and details page built")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--media", nargs="*", metavar="EVENT_ID", default=[], help="build images for these events")
    ap.add_argument("--media-next", type=int, metavar="N", default=0, help="build images for the next N events starting at least 2 days from now, "
                    "plus the next --primary major holidays after them (the events `asc_publish.py events --window N` drafts)")
    ap.add_argument("--primary", type=int, metavar="N", default=PRIMARY_SLOTS, help=f"with --media-next: how many major holidays after the window (default {PRIMARY_SLOTS})")
    args = ap.parse_args(argv)

    tables = snapshot()
    packs = {p["$id"]: p for p in tables["packs"]}
    by_pack: dict[str, list[dict]] = {}
    for z in tables["puzzles"]:
        by_pack.setdefault(z.get("packId"), []).append(z)
    by_id = {z["$id"]: z for z in tables["puzzles"]}

    old = {}
    if OUT.exists():
        old = {e["eventId"]: e for e in json.loads(OUT.read_text()).get("events", [])}
    events = []
    for ev in sorted(tables["events"], key=lambda e: e.get("startAt") or ""):
        pack = packs.get(ev.get("packId") or "")
        if not pack or not ev.get("startAt") or not ev.get("endAt"):
            print(f"  {ev['$id']}: no pack or no dates, skipped")
            continue
        prev = old.get(ev["$id"])
        if prev and prev.get("locked"):
            # A hand-edited entry keeps its text and pictures; its publish date follows PUBLISH_DAYS_BEFORE
            # and its major-holiday mark follows PRIMARY.
            prev = {k: v for k, v in prev.items() if k != "primary"}
            prev["publishStart"] = _z(_utc(prev["eventStart"]) - dt.timedelta(days=PUBLISH_DAYS_BEFORE))
            if is_primary(ev["$id"]):
                prev = {"eventId": prev["eventId"], "packId": prev["packId"], "primary": True, **prev}
            events.append(prev)
        else:
            events.append(entry(ev, pack, by_pack.get(pack["$id"], [])))
    OUT.write_text(json.dumps({
        "about": "In-App Events for the world-day events. Written by tools/store/make_app_events.py; "
                 "set \"locked\": true on an entry to keep hand edits. asc_publish.py events creates drafts.",
        "events": events,
    }, indent=1, ensure_ascii=False) + "\n")
    warn = [e for e in events if e.get("warnings")]
    print(f"{len(events)} events written to {OUT.relative_to(ROOT)}" + (f"; {len(warn)} need a look" if warn else ""))
    for e in warn:
        print(f"  {e['eventId']}: " + "; ".join(e["warnings"]))

    now = dt.datetime.now(dt.timezone.utc)
    wanted = set(args.media)
    if args.media_next:
        # The same events `asc_publish.py events` drafts (see pick).
        wanted |= {e["eventId"] for e in pick(events, now, args.media_next, args.primary)}
    for e in events:
        if e["eventId"] in wanted:
            build_media(e, by_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
