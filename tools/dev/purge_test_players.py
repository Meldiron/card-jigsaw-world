#!/usr/bin/env python3
"""Find and delete QA test players on the live Appwrite backend.

Every QA run (tools/dev/qa-run.sh, which passes --dart-define=CJW_QA=true) marks the anonymous
player it creates as a test player: the profile row gets `isTest: true` (kept out of the league)
and the Appwrite user gets the prefs `{"qa": true, "qaRun": "<run id>"}`. This tool lists and
purges them: the Appwrite user and every row they own (profiles, progress, ledger, event_progress,
friends in both directions, my_puzzles and their photos in the user-uploads bucket, friend gifts
sent and received and the inbox messages of gifts they sent; aw.PLAYER_TABLES has the full list). A JSON backup
of each purged player is written to secrets/purged/<date>/ first (git-ignored).

  purge_test_players.py list                       flagged test players
  purge_test_players.py purge                      dry run: what would be deleted
  purge_test_players.py purge --apply              delete every test player idle for 30+ minutes
  purge_test_players.py purge --run ID --apply     delete the players of one QA run (qa-run.sh does this)
  purge_test_players.py audit                      every player with evidence and a suggested verdict

"Test player" means flagged by a QA build, or (for players created before the flag existed, see
LEGACY_CUTOFF) a guest whose every session is the app on the simulator's iOS version from the
owner's own networks (QA_NETWORKS).

Safety: a player is never purged when the user has an email or phone, a non-anonymous
session, a purchase row, VIP (flag, expiry or Apple transaction id) or a real player who added them
as a friend. `--idle` (default 30 minutes) skips players still in use, so a run in progress in another
session keeps its player; `--run` purges that run's players regardless of idle time.
Key: secrets/appwrite-users-key.txt (users.read/write, rows.read/write, files.read/write).
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cjw_admin as aw  # noqa: E402

BACKUP_ROOT = os.path.join(aw.ROOT, 'secrets', 'purged')
SECRET_FIELDS = {'password', 'hash', 'hashOptions', 'secret', 'providerAccessToken', 'providerRefreshToken'}

# QA builds flag their players from this day on (CJW_QA). Guests created before it were never
# flagged; they count as test players only with the simulator evidence below. The window is
# closed, so a real player on the same iOS version later can never match.
LEGACY_CUTOFF = '2026-10-13T20:00:00+00:00'

# Where the owner's Mac reaches Appwrite from: the home line (shared with the owner's iPhone) and
# Cloudflare WARP egress (shared with the Mac's browser sessions). Simulator sessions came from these.
QA_NETWORKS = ('86.49.252.121', '104.28.', '2a09:bac5:')


def now():
    return dt.datetime.now(dt.timezone.utc)


def parse_time(s):
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace('Z', '+00:00'))
    except ValueError:
        return None


def clean(d):
    return {k: v for k, v in d.items() if k not in SECRET_FIELDS}


class World:
    """Everything the decisions need, read once."""

    def __init__(self, client):
        self.c = client
        self.users = {u['$id']: u for u in client.users()}
        self.profiles = {p['$id']: p for p in client.rows('profiles')}
        self.purchases = client.rows('purchases', [aw.q('select', values=['$id', 'userId'])])
        self.friends = client.rows('friends')
        self._sessions = {}
        self._files = None

    def sessions(self, uid):
        if uid not in self._sessions:
            self._sessions[uid] = self.c.sessions(uid) if uid in self.users else []
        return self._sessions[uid]

    def bucket_files(self):
        if self._files is None:
            self._files = self.c.files(aw.UPLOADS_BUCKET)
        return self._files

    def prefs(self, uid):
        return (self.users.get(uid) or {}).get('prefs') or {}

    def flagged(self, uid):
        p = self.profiles.get(uid) or {}
        return p.get('isTest') is True or self.prefs(uid).get('qa') is True

    def run_id(self, uid):
        return self.prefs(uid).get('qaRun')

    def simulator_evidence(self, uid, sim_majors):
        """Why this unflagged guest is a pre-flag simulator player, or None."""
        u = self.users.get(uid)
        if not u or not sim_majors:
            return None
        created = parse_time(u.get('$createdAt'))
        if not created or created >= parse_time(LEGACY_CUTOFF):
            return None
        sessions = self.sessions(uid)
        if not sessions:
            return None
        for s in sessions:
            if s.get('provider') != 'anonymous' or s.get('osName') != 'iOS' or s.get('clientType') != 'mobile app':
                return None
            if str(s.get('osVersion', '')).split('.')[0] not in sim_majors:
                return None
            if not str(s.get('ip', '')).startswith(QA_NETWORKS):
                return None
        return f"created before the QA flag; every session is the app on iOS {'/'.join(sorted(sim_majors))} (the simulator runtime) from the owner's network"

    def all_ids(self):
        return sorted(set(self.users) | set(self.profiles), key=lambda i: (self.users.get(i) or self.profiles.get(i))['$createdAt'])

    # -- guards ---------------------------------------------------------------------------------
    def blockers(self, uid, include_linked=False, strict_friends=False):
        """Reasons this player must be kept. Empty when it is safe to delete."""
        out = []
        u = self.users.get(uid)
        p = self.profiles.get(uid) or {}
        if u and not include_linked:
            if u.get('email'):
                out.append('has an email')
            if u.get('phone'):
                out.append('has a phone')
            if any(s.get('provider') != 'anonymous' for s in self.sessions(uid)):
                out.append('signed in with ' + ','.join(sorted({s.get('provider') for s in self.sessions(uid)} - {'anonymous'})))
        if any(r.get('userId') == uid for r in self.purchases):
            out.append('has purchases')
        if p.get('isVip') or p.get('vipExpiresAt') or p.get('appleOriginalTransactionId'):
            out.append('VIP')
        for f in self.friends:
            other = f['userId'] if f.get('friendId') == uid else (f.get('friendId') if f.get('userId') == uid and strict_friends else None)
            if other and other != uid and not self.flagged(other):
                out.append(f"friends with {(self.profiles.get(other) or {}).get('displayName', other)}")
        return out

    def last_active(self, uid, rows=None):
        times = []
        u = self.users.get(uid) or {}
        times += [parse_time(u.get('accessedAt')), parse_time(u.get('$updatedAt')), parse_time(u.get('$createdAt'))]
        times += [parse_time(s.get('$updatedAt')) for s in self.sessions(uid)]
        times.append(parse_time((self.profiles.get(uid) or {}).get('$updatedAt')))
        for table_rows in (rows or {}).values():
            times += [parse_time(r.get('$updatedAt')) for r in table_rows]
        times = [t for t in times if t]
        return max(times) if times else None

    # -- evidence -------------------------------------------------------------------------------
    def describe_sessions(self, uid):
        out = set()
        for s in self.sessions(uid):
            out.add(f"{s.get('provider')} {s.get('osName')} {s.get('osVersion')} {s.get('deviceModel') or ''} {s.get('clientName')} {s.get('clientVersion')} {s.get('countryCode')} {s.get('ip')}".replace('  ', ' '))
        return sorted(out)


def simulator_majors():
    """Major iOS versions of the simulator runtimes installed on this Mac."""
    try:
        raw = subprocess.run(['xcrun', 'simctl', 'list', 'runtimes', '-j'], capture_output=True, text=True, timeout=30).stdout
        return {r['version'].split('.')[0] for r in json.loads(raw).get('runtimes', []) if r.get('platform', 'iOS') == 'iOS'}
    except Exception:
        return set()


def verdict(w, uid, sim):
    """Suggested verdict for the audit: keep, test or unsure, with the evidence."""
    p = w.profiles.get(uid) or {}
    if w.flagged(uid):
        return 'test', 'flagged by a QA build' + (f" (run {w.run_id(uid)})" if w.run_id(uid) else '')
    block = w.blockers(uid, strict_friends=True)
    if block:
        return 'keep', '; '.join(block)
    sessions = w.sessions(uid)
    if uid not in w.users:
        return 'unsure', 'profile without an Appwrite user'
    if not sessions:
        return 'unsure', 'no sessions left (signed out), device unknown'
    evidence = w.simulator_evidence(uid, sim)
    if evidence:
        return 'test', evidence
    if any(s.get('osName') == 'iOS' for s in sessions):
        return 'keep', 'session from a real iPhone'
    return 'unsure', 'browser session (' + ', '.join(sorted({f"{s.get('osName')} {s.get('clientName')}" for s in sessions})) + ')'


def player_rows(w, uid):
    rows = {}
    for t in aw.PLAYER_TABLES:
        if t == 'profiles':
            rows[t] = [w.profiles[uid]] if uid in w.profiles else []
        elif t == 'friends':
            rows[t] = [f for f in w.friends if f.get('userId') == uid or f.get('friendId') == uid]
        elif t in aw.PAIR_TABLES:
            found = {}
            for col in aw.PAIR_TABLES[t]:
                for r in w.c.rows(t, [aw.q('equal', col, [uid])]):
                    found[r['$id']] = r
            rows[t] = list(found.values())
        else:
            rows[t] = w.c.rows(t, [aw.q('equal', 'userId', [uid])])
    return rows


def player_files(w, uid, rows):
    ids = {r.get('fileId') for r in rows.get('my_puzzles', []) if r.get('fileId')}
    mine = f'user:{uid}'
    return [f for f in w.bucket_files() if f['$id'] in ids or any(mine in perm for perm in f.get('$permissions', []))]


def backup(w, uid, rows, files, folder):
    os.makedirs(folder, exist_ok=True)
    os.chmod(BACKUP_ROOT, 0o700)
    saved = []
    for f in files:
        try:
            data = w.c.file_bytes(aw.UPLOADS_BUCKET, f['$id'])
            ext = os.path.splitext(f.get('name') or '')[1] or '.bin'
            path = os.path.join(folder, f'{uid}-{f["$id"]}{ext}')
            with open(path, 'wb') as fh:
                fh.write(data)
            saved.append(os.path.basename(path))
        except aw.AppwriteError as e:
            saved.append(f'{f["$id"]}: not downloaded ({e.code})')
    doc = {
        'purgedAt': now().isoformat(),
        'userId': uid,
        'user': clean(w.users[uid]) if uid in w.users else None,
        'sessions': [clean(s) for s in w.sessions(uid)],
        'rows': rows,
        'files': [{'meta': f, 'saved': s} for f, s in zip(files, saved)],
    }
    with open(os.path.join(folder, f'{uid}.json'), 'w') as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)


def delete_player(w, uid, rows, files):
    for f in files:
        try:
            w.c.delete_file(aw.UPLOADS_BUCKET, f['$id'])
        except aw.AppwriteError as e:
            if e.code != 404:
                raise
    for t in aw.PLAYER_TABLES:
        if t == 'profiles':
            continue
        for r in rows[t]:
            try:
                w.c.delete_row(t, r['$id'])
            except aw.AppwriteError as e:
                if e.code != 404:
                    raise
    if rows['profiles']:
        try:
            w.c.delete_row('profiles', uid)
        except aw.AppwriteError as e:
            if e.code != 404:
                raise
    if uid in w.users:
        try:
            w.c.delete_user(uid)
        except aw.AppwriteError as e:
            if e.code != 404:
                raise


def label(w, uid):
    p = w.profiles.get(uid) or {}
    u = w.users.get(uid) or {}
    return f"{uid}  {(u or p).get('$createdAt', '')[:16]}  {p.get('displayName', '-')!r:24} xp {p.get('xp', 0):>5} solved {p.get('puzzlesCompleted', 0):>3}"


def cmd_list(w, args):
    ids = [i for i in w.all_ids() if w.flagged(i)]
    for uid in ids:
        print(label(w, uid), f"run {w.run_id(uid) or '-'}")
    print(f'{len(ids)} flagged test player(s)')


def cmd_audit(w, args):
    sim = simulator_majors()
    print(f"simulator runtimes on this Mac: iOS {', '.join(sorted(sim)) or 'none found'}")
    report = []
    counts = {}
    for uid in w.all_ids():
        v, why = verdict(w, uid, sim)
        counts[v] = counts.get(v, 0) + 1
        report.append({'id': uid, 'verdict': v, 'why': why, 'name': (w.profiles.get(uid) or {}).get('displayName'), 'sessions': w.describe_sessions(uid)})
        if args.only and v != args.only:
            continue
        print(f'{v:6} {label(w, uid)}  {why}')
        for s in w.describe_sessions(uid):
            print(f'         {s}')
    print(' '.join(f'{k}: {n}' for k, n in sorted(counts.items())))
    if args.json:
        with open(args.json, 'w') as fh:
            json.dump(report, fh, indent=1, ensure_ascii=False)


def cmd_purge(w, args):
    why = {}
    if args.run:
        ids = [i for i in w.all_ids() if w.run_id(i) == args.run]
    else:
        sim = simulator_majors()
        ids = []
        for i in w.all_ids():
            if w.flagged(i):
                ids.append(i)
            else:
                evidence = w.simulator_evidence(i, sim)
                if evidence:
                    ids.append(i)
                    why[i] = 'legacy'
    stamp = now().strftime('%Y-%m-%d')
    folder = os.path.join(BACKUP_ROOT, stamp)
    purged = kept = 0
    for uid in ids:
        block = w.blockers(uid, include_linked=args.include_linked, strict_friends=uid in why)
        if block:
            kept += 1
            print(f'keep  {label(w, uid)}: {"; ".join(block)}')
            continue
        rows = player_rows(w, uid)
        if not args.run:
            last = w.last_active(uid, rows)
            if last and now() - last < dt.timedelta(minutes=args.idle):
                kept += 1
                if not args.quiet:
                    print(f'keep  {label(w, uid)}: active {int((now() - last).total_seconds() // 60)} min ago (still in use?)')
                continue
        files = player_files(w, uid, rows)
        n_rows = sum(len(v) for v in rows.values())
        if not args.apply:
            print(f'would purge {label(w, uid)}  ({n_rows} rows, {len(files)} photos)')
            purged += 1
            continue
        backup(w, uid, rows, files, folder)
        delete_player(w, uid, rows, files)
        purged += 1
        if not args.quiet:
            print(f'purged {label(w, uid)}  ({n_rows} rows, {len(files)} photos)')
    if args.apply:
        where = os.path.relpath(folder, aw.ROOT)
        print(f'{purged} test player(s) purged, {kept} kept' + (f'; backup in {where}/' if purged else ''))
    else:
        print(f'dry run: {purged} would be purged, {kept} kept; add --apply to delete')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('list')
    a = sub.add_parser('audit')
    a.add_argument('--only', choices=['keep', 'test', 'unsure'])
    a.add_argument('--json', help='write the verdicts to this file')
    p = sub.add_parser('purge')
    p.add_argument('--run', help='only the players of this QA run (prefs.qaRun)')
    p.add_argument('--idle', type=int, default=30, help='minutes without activity before a flagged player is purged (default 30)')
    p.add_argument('--include-linked', action='store_true', help='also purge flagged players who linked an email or Apple ID')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--quiet', action='store_true')
    args = ap.parse_args()
    if args.cmd == 'purge' and args.run and not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', args.run):
        raise SystemExit('bad run id')
    w = World(aw.Client())
    {'list': cmd_list, 'audit': cmd_audit, 'purge': cmd_purge}[args.cmd](w, args)


if __name__ == '__main__':
    main()
