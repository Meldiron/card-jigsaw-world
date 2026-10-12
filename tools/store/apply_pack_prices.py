#!/usr/bin/env python3
"""Apply the pack price policy from docs/economy.md to the `packs` table.

Dry run by default: reads every pack, prints the price each one should have
and what would change. Nothing is written without --apply.

    python3 tools/store/apply_pack_prices.py              # dry run, changed rows only
    python3 tools/store/apply_pack_prices.py --verbose    # dry run, every row
    python3 tools/store/apply_pack_prices.py --apply      # write the changes
    python3 tools/store/apply_pack_prices.py --all        # also re-derive rows already on the new scale
    python3 tools/store/apply_pack_prices.py --only pack-owls,pack-kittens

The policy (docs/economy.md, "Pack prices"):

* Free packs (isFree), event packs (category Event or a start/end window) and
  rows without any price stay as they are.
* Coin packs are priced by how long a regular player (1 hour a day) plays to
  earn them: price = pictures x coins per picture of the pack's tier, rounded
  to 100, never below 1,000 and never above 5,000. The tier comes from the
  price the pack was created with (the content tool's 300-900 scale, new packs
  arrive at 400), so a pack keeps its place relative to the others. Daily
  (past monthly) albums use the standard tier.
* Ticket packs cost a share of a week of free tickets: 8, 10 or 12 tickets,
  two fewer for small packs (under 18 pictures).
* Rows that are already on the new scale (1,000+ coins, 5+ tickets) are left
  alone, so hand-tuned prices survive a re-run. --all re-derives them too
  (the tier is read back from the price per picture).

Re-run it whenever the content session has added packs: they arrive at
400 coins or 3 tickets (the old scale) and get repriced here.

Credentials: secrets/appwrite-api-key.txt (rows.read, rows.write) or the
APPWRITE_API_KEY environment variable. Standard library plus requests.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover
    sys.exit("missing dependency: requests (pip install requests)")

ROOT = Path(__file__).resolve().parents[2]
KEY_FILE = ROOT / "secrets" / "appwrite-api-key.txt"
ENDPOINT = "https://fra.cloud.appwrite.io/v1"
PROJECT = "6acb4de5003e38d5ebd9"
DB = "cjw"
TABLE = "packs"

# ---------------------------------------------------------------------------
# Policy (keep in sync with docs/economy.md)
# ---------------------------------------------------------------------------

# Economy model, steady state of the regular player (1 hour a day, 5x5
# boards): coins earned per hour of play, all sources included, and free
# tickets per week. See docs/economy.md, "Model results". 6000 until
# 2026-10-13, when the owner lowered the coins for finishing a puzzle.
REGULAR_COINS_PER_HOUR = 3500
REGULAR_TICKETS_PER_WEEK = 16
REFERENCE_PICTURES = 24  # a full library pack

# Price of a 24-picture pack per tier, in coins (set 2026-10-12 and kept when
# earnings were lowered, so a pack now costs more play time).
TIER_PACK_COINS = {"standard": 2400, "plus": 3300, "special": 4200, "showcase": 5100}
# Coins per picture -> 100, 137.5, 175, 212.5.
COINS_PER_PICTURE = {t: c / REFERENCE_PICTURES for t, c in TIER_PACK_COINS.items()}
# Hours of regular play a 24-picture pack of each tier costs (for reports only).
TIER_HOURS = {t: round(c / REGULAR_COINS_PER_HOUR, 2) for t, c in TIER_PACK_COINS.items()}
MIN_COINS = 1000  # owner: no coin pack below 1,000
MAX_COINS = 5000  # owner: nice packs up to 5,000
ROUND_COINS = 100

# Share of a regular player's weekly free tickets a ticket pack costs.
TICKET_TIER_WEEKS = {"standard": 0.5, "plus": 0.625, "special": 0.75}  # 8, 10, 12 tickets
TICKETS = {t: round(w * REGULAR_TICKETS_PER_WEEK) for t, w in TICKET_TIER_WEEKS.items()}
SMALL_PACK_PICTURES = 18  # ticket packs below this cost 2 fewer tickets
SMALL_PACK_DISCOUNT = 2
MIN_TICKETS = 6

# Old scale: the content tool creates packs at 300-900 coins or 2-4 tickets.
LEGACY_COIN_LIMIT = MIN_COINS  # anything below 1,000 coins is on the old scale
LEGACY_TICKET_LIMIT = 5  # anything below 5 tickets is on the old scale


def legacy_coin_tier(price: int) -> str:
    if price <= 400:
        return "standard"
    if price <= 600:
        return "plus"
    if price <= 800:
        return "special"
    return "showcase"


def legacy_ticket_tier(price: int) -> str:
    if price <= 2:
        return "standard"
    if price == 3:
        return "plus"
    return "special"


def pictures_of(pack: dict) -> int:
    n = int(pack.get("imageCount") or 0)
    # A pack still being filled by the content tool (0 pictures) is priced as a full pack.
    return n if n > 0 else REFERENCE_PICTURES


def coin_price(tier: str, pictures: int) -> int:
    raw = pictures * COINS_PER_PICTURE[tier]
    rounded = int(raw / ROUND_COINS + 0.5) * ROUND_COINS
    return max(MIN_COINS, min(MAX_COINS, rounded))


def ticket_price(tier: str, pictures: int) -> int:
    price = TICKETS[tier]
    if pictures < SMALL_PACK_PICTURES:
        price -= SMALL_PACK_DISCOUNT
    return max(MIN_TICKETS, price)


def decode_coin_tier(price: int, pictures: int) -> str:
    """Tier of a row already on the new scale: the nearest coins-per-picture
    rate (ties go to the cheaper tier). Prices at the 5,000 cap read as showcase."""
    if price >= MAX_COINS:
        return "showcase"
    per = price / pictures
    return min(COINS_PER_PICTURE, key=lambda t: (abs(COINS_PER_PICTURE[t] - per), COINS_PER_PICTURE[t]))


def decode_ticket_tier(price: int, pictures: int) -> str:
    return min(TICKETS, key=lambda t: (abs(ticket_price(t, pictures) - price), TICKETS[t]))


def plan(pack: dict, rederive: bool) -> dict:
    """What the policy says about one row. Keys: kind, tier, field, old, new, note."""
    coins = int(pack.get("priceCoins") or 0)
    tickets = int(pack.get("priceTickets") or 0)
    pictures = pictures_of(pack)
    category = pack.get("category") or ""
    base = {"kind": "", "tier": "", "field": None, "old": None, "new": None, "note": ""}
    if category == "Event" or pack.get("startAt") or pack.get("endAt") or pack.get("eventId"):
        return {**base, "kind": "event", "note": "event pack: free while live, unchanged"}
    if pack.get("isFree"):
        return {**base, "kind": "free", "note": "free pack, unchanged"}
    if tickets > 0:
        if tickets < LEGACY_TICKET_LIMIT:
            tier, note = legacy_ticket_tier(tickets), f"old scale ({tickets} tickets)"
        elif rederive:
            tier, note = decode_ticket_tier(tickets, pictures), "re-derived"
        else:
            return {**base, "kind": "tickets", "field": "priceTickets", "old": tickets, "new": tickets,
                    "tier": decode_ticket_tier(tickets, pictures), "note": "already on the new scale, kept"}
        return {**base, "kind": "tickets", "tier": tier, "field": "priceTickets", "old": tickets,
                "new": ticket_price(tier, pictures), "note": note}
    if coins > 0:
        kind = "daily" if category == "Daily" else "coins"
        if kind == "daily":
            tier, note = "standard", "past monthly album: standard tier"
            if coins >= LEGACY_COIN_LIMIT and not rederive:
                return {**base, "kind": kind, "tier": tier, "field": "priceCoins", "old": coins, "new": coins,
                        "note": "already on the new scale, kept"}
        elif pack.get("isPremium") and coins < LEGACY_COIN_LIMIT:
            tier, note = "showcase", "premium coin pack"
        elif coins < LEGACY_COIN_LIMIT:
            tier, note = legacy_coin_tier(coins), f"old scale ({coins} coins)"
        elif rederive:
            tier, note = decode_coin_tier(coins, pictures), "re-derived"
        else:
            return {**base, "kind": kind, "field": "priceCoins", "old": coins, "new": coins,
                    "tier": decode_coin_tier(coins, pictures), "note": "already on the new scale, kept"}
        return {**base, "kind": kind, "tier": tier, "field": "priceCoins", "old": coins,
                "new": coin_price(tier, pictures), "note": note}
    return {**base, "kind": "unpriced", "note": "no price and not free: plays as free, check it"}


# ---------------------------------------------------------------------------
# Appwrite REST
# ---------------------------------------------------------------------------


def api_key() -> str:
    key = os.environ.get("APPWRITE_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text(encoding="utf-8").strip()
    if not key:
        sys.exit(f"no Appwrite API key: set APPWRITE_API_KEY or write it to {KEY_FILE.relative_to(ROOT)}")
    return key


class Api:
    def __init__(self, key: str):
        self.s = requests.Session()
        self.s.headers.update({"X-Appwrite-Project": PROJECT, "X-Appwrite-Key": key, "Content-Type": "application/json"})

    def call(self, method: str, path: str, **kw) -> dict:
        for attempt in range(5):
            r = self.s.request(method, ENDPOINT + path, timeout=60, **kw)
            if r.status_code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(2 * (attempt + 1))
                continue
            if r.status_code >= 400:
                raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:300]}")
            return r.json() if r.content else {}
        raise RuntimeError(f"{method} {path}: retries exhausted")

    def packs(self) -> list[dict]:
        rows, cursor = [], None
        while True:
            queries = [json.dumps({"method": "limit", "values": [500]})]
            if cursor:
                queries.append(json.dumps({"method": "cursorAfter", "values": [cursor]}))
            page = self.call("GET", f"/tablesdb/{DB}/tables/{TABLE}/rows", params={"queries[]": queries})["rows"]
            rows += page
            if len(page) < 500:
                return rows
            cursor = page[-1]["$id"]

    def update(self, row_id: str, data: dict) -> None:
        self.call("PATCH", f"/tablesdb/{DB}/tables/{TABLE}/rows/{row_id}", data=json.dumps({"data": data}))


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


def fmt(n: int | None) -> str:
    return "-" if n is None else f"{n:,}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the new prices (default: dry run)")
    ap.add_argument("--all", action="store_true", help="also re-derive rows already on the new scale")
    ap.add_argument("--only", metavar="ID[,ID]", help="limit to these pack ids")
    ap.add_argument("--verbose", "-v", action="store_true", help="list every pack, not only changes")
    args = ap.parse_args(argv)

    api = Api(api_key())
    packs = api.packs()
    if args.only:
        wanted = {p.strip() for p in args.only.split(",") if p.strip()}
        packs = [p for p in packs if p["$id"] in wanted]
        missing = wanted - {p["$id"] for p in packs}
        if missing:
            print(f"not found: {', '.join(sorted(missing))}", file=sys.stderr)
    packs.sort(key=lambda p: (p.get("category") or "", p.get("sortOrder") or 0, p["$id"]))

    plans = [(p, plan(p, args.all)) for p in packs]
    changes = [(p, x) for p, x in plans if x["field"] and x["new"] != x["old"]]

    print(f"{'pack':34} {'category':12} {'pics':>4}  {'currency':8} {'tier':9} {'old':>6} {'new':>6}  note")
    for p, x in plans:
        changed = x["field"] and x["new"] != x["old"]
        if not (changed or args.verbose):
            continue
        cur = {"priceCoins": "coins", "priceTickets": "tickets"}.get(x["field"], "")
        print(f"{p['$id'][:34]:34} {(p.get('category') or '')[:12]:12} {int(p.get('imageCount') or 0):>4}  {cur:8} "
              f"{x['tier']:9} {fmt(x['old']):>6} {fmt(x['new']):>6}  {x['note']}")

    # Summary
    kinds = Counter(x["kind"] for _, x in plans)
    print()
    print(f"packs read: {len(packs)}  ({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))})")
    for field, label in (("priceCoins", "coin"), ("priceTickets", "ticket")):
        priced = [x for _, x in plans if x["field"] == field]
        if not priced:
            continue
        for kind in sorted({x["kind"] for x in priced}):
            rows = [x for x in priced if x["kind"] == kind]
            old = [x["old"] for x in rows]
            new = [x["new"] for x in rows]
            print(f"{kind:8} {label} packs: {len(rows):3}  before {fmt(min(old))}-{fmt(max(old))} (total {fmt(sum(old))}, "
                  f"mean {fmt(round(sum(old) / len(old)))})  after {fmt(min(new))}-{fmt(max(new))} "
                  f"(total {fmt(sum(new))}, mean {fmt(round(sum(new) / len(new)))})")
            by_tier = Counter(x["tier"] for x in rows)
            dist = ", ".join(f"{fmt(n)} x{c}" for n, c in sorted(Counter(x["new"] for x in rows).items()))
            print(f"  tiers: {', '.join(f'{t} {by_tier[t]}' for t in TIER_HOURS if by_tier[t])}")
            print(f"  new prices: {dist}")
    unpriced = [p["$id"] for p, x in plans if x["kind"] == "unpriced"]
    if unpriced:
        print(f"warning: {len(unpriced)} packs have no price and are not free: {', '.join(unpriced)}")
    print(f"changes: {len(changes)}")

    if not changes:
        return 0
    if not args.apply:
        print("dry run: nothing written. Re-run with --apply to write these prices.")
        return 0
    failed = 0
    for p, x in changes:
        try:
            api.update(p["$id"], {x["field"]: x["new"]})
            print(f"  {p['$id']}: {x['field']} {x['old']} -> {x['new']}")
        except RuntimeError as e:
            failed += 1
            print(f"  {p['$id']}: FAILED {e}", file=sys.stderr)
        time.sleep(0.08)
    print(f"written: {len(changes) - failed}, failed: {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
