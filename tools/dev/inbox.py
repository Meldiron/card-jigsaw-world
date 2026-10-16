#!/usr/bin/env python3
"""Messages to players: Social > Inbox (owner, 2026-10-16). Skill: .claude/skills/inbox-messages.

A message is a row of the `messages` table that only its audience can read (row-level permissions):
one player (`user:<id>`, a row each), everyone with a label (`label:early`, one shared row), or
every player (`users`, one shared row, which players who join later see too). What each player did
with it (opened, claimed, deleted) lives in their `profiles.inbox` list, so a gift cannot be edited
and is paid once per player. Nothing is written without --yes.

  python3 tools/dev/inbox.py send --to <userId> --subject "..." --body "..." [options] [--yes]
  python3 tools/dev/inbox.py send --name "Brave Otter" ...      one player by display name
  python3 tools/dev/inbox.py send --label early [--label girlfriend] ...   players with any of these labels
  python3 tools/dev/inbox.py send --all ...                     every player, now and later
  python3 tools/dev/inbox.py send --qa ...                      the newest QA guest (for checking)
      --coins N --tickets N --hints N --peeks N --magics N      a gift (optional)
      --cta-label "Open the pack" --cta-link /library/pack/pack-owls
      --expires 7d | 48h | 2026-12-31T23:59:00Z               leaves the inbox after this
      --at 2026-12-24T08:00:00Z                               shown from this time (default now)
  python3 tools/dev/inbox.py list                              every message and its audience
  python3 tools/dev/inbox.py list --to <userId>                 what that player sees, and its state
  python3 tools/dev/inbox.py labels <userId> [--add early] [--remove early] [--yes]   a player's labels
  python3 tools/dev/inbox.py expire <messageId> [--yes]        ends a message now
  python3 tools/dev/inbox.py delete <messageId> [<messageId> ...] [--yes]   removes rows

Uses secrets/appwrite-users-key.txt (rows read/write). Key values are never printed.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import uuid

sys.path.insert(0, os.path.dirname(__file__))
import cjw_admin as aw  # noqa: E402

TABLE = 'messages'
ROWS = f'/tablesdb/{aw.DB}/tables/{TABLE}/rows'
PROFILES = f'/tablesdb/{aw.DB}/tables/profiles/rows'

# Links the app opens (AppLink.parse): a path, carden://<path> or https://play.carden.page/<path>.
LINK = re.compile(
    r'^(?:(?:carden|cardjigsaw)://|https://play\.carden\.page)?/?'
    r'(library(?:/pack/[\w.-]+)?|pack/[\w.-]+|play/[\w.-]+|picture/[\w.-]+|events|quests|social|leaderboard|friends|inbox|messages|'
    r'feedback|profile(?:/(?:settings|my-puzzles|account))?|settings|my-puzzles|account|store|shop|vip|wheel|lucky-wheel|daily|today|'
    r'quick|quick-play|gift|daily-gift|piggy|piggy-bank|player/[\w.-]+|add-friend)(?:\?[\w=&.%-]*)?$')

# A gift bigger than these needs --force (a typo should not hand out a fortune).
LIMITS = {'coins': 10000, 'tickets': 30, 'hints': 30, 'peeks': 50, 'magics': 20}


def utc(s):
    m = re.fullmatch(r'(\d+)([dh])', s or '')
    if m:
        n, unit = int(m.group(1)), m.group(2)
        return dt.datetime.now(dt.timezone.utc) + (dt.timedelta(days=n) if unit == 'd' else dt.timedelta(hours=n))
    t = dt.datetime.fromisoformat(s.replace('Z', '+00:00'))
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def iso(t):
    # Milliseconds, so messages sent one after another keep their order.
    u = t.astimezone(dt.timezone.utc)
    return u.strftime('%Y-%m-%dT%H:%M:%S.') + f'{u.microsecond // 1000:03d}+00:00'


LABEL = re.compile(r'^[A-Za-z0-9]{1,36}$')


def audience(c, a):
    """Who reads the row(s): a list of (userId or '', [permissions])."""
    if a.label:
        bad = [x for x in a.label if not LABEL.match(x)]
        if bad:
            raise SystemExit(f'labels are letters and digits only (up to 36): {bad}')
        return [('', [f'read("label:{x}")' for x in dict.fromkeys(a.label)])]
    if a.all:
        return [('', ['read("users")'])]
    return [(uid, [f'read("user:{uid}")']) for uid in recipients(c, a)]


def recipients(c, a):
    if a.to:
        return list(dict.fromkeys(a.to))
    rows = c.list_all(PROFILES, 'rows', [aw.q('select', values=['$id', 'displayName', 'isTest', '$createdAt'])])
    if a.name:
        hits = [r['$id'] for r in rows if (r.get('displayName') or '').strip().lower() == a.name.strip().lower()]
        if len(hits) != 1:
            raise SystemExit(f'{len(hits)} players are called {a.name!r}; use --to <userId>')
        return hits
    if a.qa:
        qa = sorted((r for r in rows if r.get('isTest')), key=lambda r: r['$createdAt'])
        if not qa:
            raise SystemExit('no QA player right now (start one with tools/dev/qa-run.sh)')
        return [qa[-1]['$id']]
    raise SystemExit('who to? --to, --name, --qa, --label or --all')


def cmd_send(c, a):
    if len(a.subject) > 120:
        raise SystemExit('subject: at most 120 characters')
    body = open(a.body_file).read().strip() if a.body_file else (a.body or '').strip()
    if not body:
        raise SystemExit('--body or --body-file is required')
    if len(body) > 4000:
        raise SystemExit('body: at most 4000 characters')
    if a.cta_link and not LINK.match(a.cta_link):
        raise SystemExit(f'--cta-link {a.cta_link!r} is not a link the app opens (see the skill for the list)')
    if a.cta_label and len(a.cta_label) > 40:
        raise SystemExit('--cta-label: at most 40 characters')
    if a.cta_label and not a.cta_link:
        raise SystemExit('--cta-label needs --cta-link')
    gift = {k: getattr(a, k) or 0 for k in LIMITS}
    over = [f'{k} {v} > {LIMITS[k]}' for k, v in gift.items() if v > LIMITS[k]]
    if over and not a.force:
        raise SystemExit('a big gift: ' + ', '.join(over) + ' (pass --force if you mean it)')
    sent = utc(a.at) if a.at else dt.datetime.now(dt.timezone.utc)
    expires = utc(a.expires) if a.expires else None
    if expires and expires <= sent:
        raise SystemExit('--expires must be after the message is shown')
    rows = audience(c, a)
    data = {
        'subject': a.subject.strip(),
        'body': body,
        'sentAt': iso(sent),
        'expiresAt': iso(expires) if expires else None,
        'rewardCoins': gift['coins'], 'rewardTickets': gift['tickets'], 'rewardHints': gift['hints'],
        'rewardPeeks': gift['peeks'], 'rewardMagics': gift['magics'],
        'ctaLabel': a.cta_label or ((a.cta_link and 'Open') or None),
        'ctaLink': a.cta_link or None,
    }
    gift_text = ', '.join(f'{v} {k}' for k, v in gift.items() if v) or 'no gift'
    who = (f'players with label {" or ".join(a.label)}' if a.label else 'every player' if a.all else f'{len(rows)} player(s)')
    print(f'{who}; "{data["subject"]}" ({gift_text}); shown {data["sentAt"]}'
          + (f', expires {data["expiresAt"]}' if expires else '') + (f'; button {data["ctaLabel"]!r} -> {data["ctaLink"]}' if a.cta_link else ''))
    if not a.yes:
        print('dry run: add --yes to send')
        return
    for i, (uid, perms) in enumerate(rows, 1):
        row_id = uuid.uuid4().hex[:20]
        c.call('POST', ROWS, body={'rowId': row_id, 'data': {'userId': uid, **data}, 'permissions': perms})
        if len(rows) <= 10:
            print(f'  {row_id} -> {uid or ", ".join(perms)}')
        elif i % 100 == 0:
            print(f'  {i}/{len(rows)}')
    print(f'sent {len(rows)} row(s)')


def readers(row):
    """The audience a row names, from its read permissions."""
    out = []
    for p in row.get('$permissions') or []:
        m = re.fullmatch(r'read\("([^"]+)"\)', p)
        if m:
            out.append(m.group(1))
    return out


def user_labels(c, uid):
    try:
        return c.call('GET', f'/users/{uid}').get('labels') or []
    except aw.AppwriteError:
        return []


def cmd_list(c, a):
    every = c.list_all(ROWS, 'rows', [aw.q('orderDesc', 'sentAt')])
    if not (a.to or a.name or a.qa):
        print(f'{len(every)} message(s)')
        for r in every:
            print(f'  {r["$id"]}  {r["sentAt"][:16]}  {r["subject"]!r}  to {", ".join(readers(r))}' + (f'  (expires {r["expiresAt"][:16]})' if r.get('expiresAt') else ''))
        return
    for uid in recipients(c, a):
        try:
            state = set(c.call('GET', f'{PROFILES}/{uid}').get('inbox') or [])
        except aw.AppwriteError:
            state = set()
        mine = {f'user:{uid}', 'users', 'any', *[f'label:{x}' for x in user_labels(c, uid)]}
        rows = [r for r in every if mine & set(readers(r))]
        print(f'{uid} (labels: {", ".join(user_labels(c, uid)) or "none"}): {len(rows)} message(s)')
        now = dt.datetime.now(dt.timezone.utc)
        for r in rows:
            flags = [s for s in ('seen', 'claimed', 'deleted') if f'{s}:{r["$id"]}' in state]
            exp = r.get('expiresAt')
            if exp and utc(exp) <= now:
                flags.append('expired')
            gift = ', '.join(f'{r[k]} {k[6:].lower()}' for k in ('rewardCoins', 'rewardTickets', 'rewardHints', 'rewardPeeks', 'rewardMagics') if r.get(k))
            print(f'  {r["$id"]}  {r["sentAt"][:16]}  {r["subject"]!r}' + (f'  [{gift}]' if gift else '') + (f'  ({", ".join(flags)})' if flags else ''))


def cmd_expire(c, a):
    row = c.call('GET', f'{ROWS}/{a.id}')
    print(f'{a.id}: "{row["subject"]}" to {", ".join(readers(row))}')
    if not a.yes:
        print('dry run: add --yes to end it now')
        return
    c.call('PATCH', f'{ROWS}/{a.id}', body={'data': {'expiresAt': iso(dt.datetime.now(dt.timezone.utc))}})
    print('expired')


def cmd_delete(c, a):
    for rid in a.ids:
        row = c.call('GET', f'{ROWS}/{rid}')
        print(f'{rid}: "{row["subject"]}" to {", ".join(readers(row))}')
        if a.yes:
            c.call('DELETE', f'{ROWS}/{rid}')
            print('  deleted')
    if not a.yes:
        print('dry run: add --yes to delete')


def cmd_labels(c, a):
    now = user_labels(c, a.user)
    want = [x for x in now if x not in (a.remove or [])] + [x for x in (a.add or []) if x not in now]
    bad = [x for x in want if not LABEL.match(x)]
    if bad:
        raise SystemExit(f'labels are letters and digits only (up to 36): {bad}')
    print(f'{a.user}: {", ".join(now) or "no labels"}' + (f' -> {", ".join(want) or "no labels"}' if want != now else ''))
    if want == now:
        return
    if not a.yes:
        print('dry run: add --yes to change them')
        return
    c.call('PUT', f'/users/{a.user}/labels', body={'labels': want})
    print('labels updated')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('send', 'list'):
        s = sub.add_parser(name)
        s.add_argument('--to', action='append', help='a player user id (repeatable)')
        s.add_argument('--name', help='one player by display name')
        s.add_argument('--qa', action='store_true', help='the newest QA guest')
        s.add_argument('--all', action='store_true', help='every player, including those who join later (one shared row)')
        s.add_argument('--label', action='append', help='players with this Appwrite label (repeatable; one shared row)')
        if name == 'send':
            s.add_argument('--subject', required=True)
            s.add_argument('--body')
            s.add_argument('--body-file')
            for k in LIMITS:
                s.add_argument(f'--{k}', type=int, default=0)
            s.add_argument('--cta-label')
            s.add_argument('--cta-link')
            s.add_argument('--expires')
            s.add_argument('--at')
            s.add_argument('--force', action='store_true')
            s.add_argument('--yes', action='store_true')
    s = sub.add_parser('expire')
    s.add_argument('id')
    s.add_argument('--yes', action='store_true')
    s = sub.add_parser('delete')
    s.add_argument('ids', nargs='+')
    s.add_argument('--yes', action='store_true')
    s = sub.add_parser('labels')
    s.add_argument('user')
    s.add_argument('--add', action='append')
    s.add_argument('--remove', action='append')
    s.add_argument('--yes', action='store_true')
    a = p.parse_args()
    c = aw.Client()
    {'send': cmd_send, 'list': cmd_list, 'expire': cmd_expire, 'delete': cmd_delete, 'labels': cmd_labels}[a.cmd](c, a)


if __name__ == '__main__':
    main()
