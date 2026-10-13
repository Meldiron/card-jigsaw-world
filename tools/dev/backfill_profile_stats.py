#!/usr/bin/env python3
"""Backfills the public aggregates on every profile row from the players' history.

  questsCompleted   quests claimed: distinct `goal:<key>` ledger reasons plus the keys still in
                    claimedGoals (the VIP weekly bonus is not a quest)
  picturesSolved    catalogue pictures solved (progress rows, released packs only; no My Puzzles photos)
  picturesPerfect   of those, solved with three stars
  packsCompleted    released packs with every picture solved
  packsPerfect      released packs with three stars on every picture
  isTest            false where the column is still empty (rows from before it existed)

The app keeps these up to date from then on (lib/state/profile.dart). Values only ever go up for
questsCompleted; the completion numbers are recomputed from the current catalogue.
Dry run by default; --apply writes. Key: secrets/appwrite-users-key.txt.
"""
import argparse
import datetime as dt
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cjw_admin as aw  # noqa: E402


def released(pack, now):
    """Pack.isReleasedAt (lib/models/models.dart): daily months from their first day, event packs
    from 3 days before they open."""
    if pack.get('category') == 'Daily':
        m = re.search(r'daily-(\d{4})-(\d{2})', pack['$id'])
        if m:
            return now >= dt.datetime(int(m.group(1)), int(m.group(2)), 1)
    start = pack.get('startAt')
    if start:
        s = dt.datetime.fromisoformat(start.replace('Z', '+00:00')).astimezone().replace(tzinfo=None)
        if now < s:
            return s - now <= dt.timedelta(days=3)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()
    c = aw.Client()
    now = dt.datetime.now()

    packs = [p for p in c.rows('packs', [aw.q('select', values=['$id', 'category', 'startAt'])]) if released(p, now)]
    visible = {p['$id'] for p in packs}
    puzzles = c.rows('puzzles', [aw.q('select', values=['$id', 'packId'])])
    by_pack = defaultdict(list)
    for z in puzzles:
        if z.get('packId') in visible:
            by_pack[z['packId']].append(z['$id'])
    catalogue = {zid for ids in by_pack.values() for zid in ids}
    print(f'catalogue: {len(catalogue)} pictures in {len(by_pack)} released packs with pictures')

    progress = defaultdict(dict)
    for r in c.rows('progress', [aw.q('select', values=['$id', 'userId', 'puzzleId', 'completed', 'stars'])]):
        progress[r['userId']][r['puzzleId']] = r
    quests = defaultdict(set)
    for r in c.rows('ledger', [aw.q('startsWith', 'reason', ['goal:']), aw.q('select', values=['$id', 'userId', 'reason'])]):
        quests[r['userId']].add(r['reason'][len('goal:'):])

    changed = 0
    for p in c.rows('profiles'):
        uid = p['$id']
        rows = progress.get(uid, {})
        claimed = quests[uid] | {k for k in (p.get('claimedGoals') or []) if not k.endswith(':vipbonus')}
        solved = [r for z, r in rows.items() if z in catalogue and r.get('completed')]
        stars = {z: (r.get('stars') or 0) for z, r in rows.items()}
        packs_done = packs_perfect = 0
        for ids in by_pack.values():
            if all(rows.get(z, {}).get('completed') for z in ids):
                packs_done += 1
                if sum(stars.get(z, 0) for z in ids) >= 3 * len(ids):
                    packs_perfect += 1
        want = {
            'questsCompleted': max(len(claimed), p.get('questsCompleted') or 0),
            'picturesSolved': len(solved),
            'picturesPerfect': sum(1 for r in solved if (r.get('stars') or 0) >= 3),
            'packsCompleted': packs_done,
            'packsPerfect': packs_perfect,
        }
        if p.get('isTest') is None:
            want['isTest'] = False
        patch = {k: v for k, v in want.items() if p.get(k) != v}
        if not patch:
            continue
        changed += 1
        shown = {k: v for k, v in patch.items() if k != 'isTest'}
        print(f"{uid} {p.get('displayName', '')!r:24} {shown}")
        if args.apply:
            c.update_row('profiles', uid, patch)
    print(f'{changed} profile(s) ' + ('updated' if args.apply else 'to update (dry run; add --apply)'))


if __name__ == '__main__':
    main()
