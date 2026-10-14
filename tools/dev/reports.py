#!/usr/bin/env python3
"""Player reports (Player > Report in the app, table `reports`): read and close them.

    python3 tools/dev/reports.py                 newest reports first, with the reported player's current name
    python3 tools/dev/reports.py --player ID     every report about one player
    python3 tools/dev/reports.py --close ROWID   delete a report you have handled

Apple's guideline 1.2 asks for timely responses: look at new reports regularly. To act on an
offensive name, rename the player (their `profiles.displayName`) in the Appwrite console; for
cheating, look at their `ledger` rows. Reports are deleted with either player's account.
Key: secrets/appwrite-users-key.txt (rows read/write); values are never printed.
"""
import argparse
import sys

import cjw_admin as aw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--player', help='only reports about this user id')
    ap.add_argument('--close', metavar='ROWID', help='delete this report row')
    args = ap.parse_args()
    c = aw.Client()
    if args.close:
        c.delete_row('reports', args.close)
        print(f'closed {args.close}')
        return
    queries = [aw.q('orderDesc', '$createdAt')]
    if args.player:
        queries.append(aw.q('equal', 'reportedId', [args.player]))
    rows = c.rows('reports', queries)
    if not rows:
        print('no reports')
        return
    names = {}
    for r in rows:
        pid = r.get('reportedId')
        if pid not in names:
            try:
                names[pid] = (c.row('profiles', pid) or {}).get('displayName', '(no profile)')
            except aw.AppwriteError:
                names[pid] = '(no profile)'
    counts = {}
    for r in rows:
        counts[r.get('reportedId')] = counts.get(r.get('reportedId'), 0) + 1
    for r in rows:
        pid = r.get('reportedId')
        print(f"{r['$createdAt'][:16]}  {r['$id']}  {r.get('reason', ''):9}  {pid}  "
              f"named {r.get('reportedName')!r} then, {names[pid]!r} now  "
              f"({counts[pid]} report{'s' if counts[pid] != 1 else ''})  by {r.get('reporterId')}")


if __name__ == '__main__':
    sys.exit(main())
