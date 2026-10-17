#!/usr/bin/env python3
"""A second QA player for checking friend gifts (docs/friend-gifts.md) against a QA run.

The app on the simulator plays one QA guest; gifts need a friend. This makes a QA friend ("Bob QA")
in the same QA run (prefs qa/qaRun, profile isTest), so tools/dev/qa-run.sh purges both at the end,
and acts as that friend through the real server (`/gift/send` on function `api`) with the friend's own session.

  gift_qa.py friend --to <userId> --run <qa run id> [--name "Bob QA"]   make the friend (both lists)
  gift_qa.py befriend-run --run <qa run id>                             wait for that run's guest, then befriend it
  gift_qa.py send [--kind tickets|coins]                                the friend sends the player a gift
  gift_qa.py inbox                                                      what the friend received
  gift_qa.py targets                                                    the player's push targets (provider, expired)
  gift_qa.py end                                                        ends the friend's session, so the purge takes it

The friend signs in with a server-made session, which the purge tool counts as a linked account:
run `end` before the run's purge (qa-run.sh purges when the test ends; with QA_KEEP=1, purge with
`purge_test_players.py purge --run <run id> --apply` after `end`).

State (the friend's id and session secret) lives in secrets/gift_qa.json (git-ignored). Uses
secrets/appwrite-users-key.txt. Key values and the session secret are never printed.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(__file__))
import cjw_admin as aw  # noqa: E402

STATE = os.path.join(aw.ROOT, 'secrets', 'gift_qa.json')
ROWS = '/tablesdb/{db}/tables/{t}/rows'


def rows(table):
    return ROWS.format(db=aw.DB, t=table)


def load():
    if not os.path.exists(STATE):
        raise SystemExit('no QA friend yet: run `gift_qa.py friend --to <userId> --run <run id>` first')
    return json.load(open(STATE))


def as_friend(state, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(aw.ENDPOINT + path, data=data, method=method,
                                 headers={'X-Appwrite-Project': aw.PROJECT, 'X-Appwrite-Session': state['secret'], 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = r.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f'{method} {path}: {e.code} {e.read().decode(errors="replace")[:300]}')


def friend_row(c, owner, friend, friend_profile):
    rid = hashlib.md5(f'{owner}:{friend}'.encode()).hexdigest()
    c.call('PUT', f'{rows("friends")}/{rid}', body={'data': {
        'userId': owner, 'friendId': friend, 'friendName': friend_profile.get('displayName') or 'Player',
        'friendAvatar': friend_profile.get('avatar') or 'fox', 'status': 'accepted'},
        'permissions': [f'read("user:{owner}")', f'update("user:{owner}")', f'delete("user:{owner}")']})


def cmd_friend(c, a):
    player = c.row('profiles', a.to)
    if not player:
        raise SystemExit(f'no profile {a.to}')
    if not player.get('isTest'):
        raise SystemExit(f'{a.to} is not a QA player: gift_qa.py only befriends QA guests')
    uid = 'qagift' + uuid.uuid4().hex[:14]
    c.call('POST', '/users', body={'userId': uid, 'name': a.name})
    c.set_prefs(uid, {'qa': True, 'qaRun': a.run})
    profile = {'userId': uid, 'displayName': a.name, 'avatar': 'owl', 'isTest': True, 'level': 3, 'xp': 420, 'puzzlesCompleted': 12}
    c.call('POST', rows('profiles'), body={'rowId': uid, 'data': profile, 'permissions': ['read("any")', f'update("user:{uid}")', f'delete("user:{uid}")']})
    friend_row(c, uid, a.to, player)
    friend_row(c, a.to, uid, profile)
    session = c.call('POST', f'/users/{uid}/sessions')
    with open(STATE, 'w') as fh:
        json.dump({'friendId': uid, 'playerId': a.to, 'run': a.run, 'secret': session['secret']}, fh)
    os.chmod(STATE, 0o600)
    print(f'friend {uid} ({a.name!r}, run {a.run}) and {a.to} are in each other\'s friends lists')


def cmd_befriend_run(c, a):
    """tools/dev/notification_check.sh: the guest a fresh QA launch makes gets a friend."""
    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)).isoformat()
    deadline = time.time() + a.wait
    while time.time() < deadline:
        try:
            for p in c.rows('profiles', [aw.q('equal', 'isTest', [True]), aw.q('greaterThan', '$createdAt', [since])]):
                u = c.user(p['$id'])
                if u and (u.get('prefs') or {}).get('qaRun') == a.run:
                    a.to = p['$id']
                    return cmd_friend(c, a)
        except aw.AppwriteError as e:
            print(f'waiting: {e.code}')
        time.sleep(3)
    raise SystemExit(f'no guest of run {a.run} within {a.wait} s')


def cmd_send(c, a):
    state = load()
    ex = as_friend(state, 'POST', '/functions/api/executions',
                   {'path': '/gift/send', 'method': 'POST', 'body': json.dumps({'friendId': state['playerId'], 'kind': a.kind, 'utcOffset': a.offset}), 'async': False})
    print(ex.get('responseStatusCode'), ex.get('responseBody'))


def cmd_inbox(c, a):
    state = load()
    for r in c.rows('messages', [aw.q('equal', 'userId', [state['friendId']])]):
        print(r['$id'], r['subject'], r.get('rewardCoins'), r.get('rewardTickets'), r.get('fromName'), r['sentAt'], r.get('expiresAt'))


def cmd_targets(c, a):
    state = load()
    for t in c.call('GET', f'/users/{state["playerId"]}/targets').get('targets', []):
        print(t['$id'], t['providerType'], t.get('providerId'), 'expired' if t.get('expired') else 'ok', t['identifier'][:8] + '...')


def cmd_end(c, a):
    state = load()
    c.call('DELETE', f'/users/{state["friendId"]}/sessions')
    os.remove(STATE)
    print(f'ended the session of {state["friendId"]}; purge with: purge_test_players.py purge --run {state["run"]} --apply')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('friend')
    s.add_argument('--to', required=True)
    s.add_argument('--run', required=True)
    s.add_argument('--name', default='Bob QA')
    s = sub.add_parser('befriend-run')
    s.add_argument('--run', required=True)
    s.add_argument('--name', default='Carol QA')
    s.add_argument('--wait', type=int, default=600)
    s = sub.add_parser('send')
    s.add_argument('--kind', choices=['tickets', 'coins'], default='tickets')
    s.add_argument('--offset', type=int, default=120)
    sub.add_parser('inbox')
    sub.add_parser('targets')
    sub.add_parser('end')
    a = p.parse_args()
    c = aw.Client()
    {'friend': cmd_friend, 'befriend-run': cmd_befriend_run, 'send': cmd_send, 'inbox': cmd_inbox, 'targets': cmd_targets, 'end': cmd_end}[a.cmd](c, a)


if __name__ == '__main__':
    main()
