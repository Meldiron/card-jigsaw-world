#!/usr/bin/env python3
"""Player feedback (Settings > Send feedback in the app, table `feedback`): read and close it.

    python3 tools/dev/feedback.py                 newest first, with the player's current name
    python3 tools/dev/feedback.py --player ID     everything one player sent
    python3 tools/dev/feedback.py --close ROWID   delete a message you have handled

Feedback has no reply channel: the sheet tells players to use Contact support (contact@almostapps.eu)
for an answer. Messages are deleted with the player's account (function `delete-account`) and with
QA players (tools/dev/purge_test_players.py).
Key: secrets/appwrite-users-key.txt (rows read/write); values are never printed.
"""
import argparse
import sys
import textwrap

import cjw_admin as aw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--player', help='only messages from this user id')
    ap.add_argument('--close', metavar='ROWID', help='delete this feedback row')
    args = ap.parse_args()
    c = aw.Client()
    if args.close:
        c.delete_row('feedback', args.close)
        print(f'closed {args.close}')
        return
    queries = [aw.q('orderDesc', '$createdAt')]
    if args.player:
        queries.append(aw.q('equal', 'userId', [args.player]))
    rows = c.rows('feedback', queries)
    if not rows:
        print('no feedback')
        return
    names = {}
    for r in rows:
        pid = r.get('userId')
        if pid not in names:
            try:
                profile = c.row('profiles', pid) or {}
                names[pid] = profile.get('displayName', '(no profile)') + (' [QA]' if profile.get('isTest') else '')
            except aw.AppwriteError:
                names[pid] = '(no profile)'
    for r in rows:
        print(f"{r['$createdAt'][:16]}  {r['$id']}  {names[r.get('userId')]!r} ({r.get('userId')})  {r.get('platform') or '?'} {r.get('appVersion') or ''}")
        print(textwrap.indent(r.get('message', ''), '    '))
        print()


if __name__ == '__main__':
    sys.exit(main())
