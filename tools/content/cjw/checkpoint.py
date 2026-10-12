"""Durable progress: reports/state.json (one entry per pack), per-pack logs, git checkpoints of our own paths."""
import json, subprocess, time
from .paths import REPORTS, ROOT, STATE as STATE_DIR
from .lock import locked

STATE_FILE = REPORTS / 'state.json'
PACK_LOGS = REPORTS / 'packs'
PACK_LOGS.mkdir(exist_ok=True)
OWN_PATHS = ['tools/content', '.claude/skills/pack-making', 'docs/content-rules.md', 'docs/content-sources.md']
ORDER = ['pending', 'audited', 'fixed', 'verified']

def load():
    if STATE_FILE.exists():
        try: return json.loads(STATE_FILE.read_text())
        except Exception: pass
    return {'meta': {}, 'packs': {}}

def _save(st):
    STATE_FILE.write_text(json.dumps(st, indent=0, sort_keys=True))

def update(pack_id, status=None, step=None, **counts):
    """Merge fields into a pack's entry. Counts given as removed=/added= are accumulated; puzzles= is set."""
    with locked('state'):
        st = load()
        e = st['packs'].setdefault(pack_id, {'status': 'pending', 'removed': 0, 'added': 0, 'puzzles': None})
        if status: e['status'] = status
        if step: e['last_step'] = step
        for k, v in counts.items():
            if k in ('removed', 'added') and v is not None: e[k] = (e.get(k) or 0) + v
            elif v is not None: e[k] = v
        e['at'] = time.strftime('%Y-%m-%dT%H:%M:%S')
        _save(st)
        return e

def pack_log(pack_id, text):
    with (PACK_LOGS / f'{pack_id}.log').open('a') as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {text}\n")

def plan(snap):
    """Ensure every catalogue pack has an entry (pending unless already known)."""
    with locked('state'):
        st = load()
        for p in snap['packs']:
            st['packs'].setdefault(p['$id'], {'status': 'pending', 'removed': 0, 'added': 0, 'puzzles': None,
                                             'kind': 'daily' if p['category'] == 'Daily' else ('event' if p['category'] == 'Event' else 'library'),
                                             'name': p['name'], 'category': p['category'], 'at': time.strftime('%Y-%m-%dT%H:%M:%S')})
        _save(st)
    return st

def board(st):
    c = {}
    for e in st['packs'].values():
        c[e['status']] = c.get(e['status'], 0) + 1
    return c

def git_checkpoint(message=None):
    """Commit and push only our own paths. Safe to re-run; never touches other files."""
    st = load()
    b = board(st)
    msg = message or f"Content: checkpoint ({b.get('verified', 0)} verified, {b.get('fixed', 0)} fixed, {b.get('audited', 0)} audited, {b.get('pending', 0)} pending)"
    def run(*args, check=False):
        return subprocess.run(['git', '-C', str(ROOT)] + list(args), capture_output=True, text=True)
    r = run('add', '--', *OWN_PATHS)
    if r.returncode != 0:
        return {'ok': False, 'stage': 'add', 'err': r.stderr[-300:]}
    r = run('diff', '--cached', '--quiet', '--', *OWN_PATHS)
    if r.returncode == 0:
        res = {'ok': True, 'stage': 'nothing-to-commit'}
    else:
        r = run('-c', 'user.name=Matej Bačo', '-c', 'user.email=matej@appwrite.io', 'commit', '-q', '--only', '-m', msg, '--', *OWN_PATHS)
        if r.returncode != 0:
            return {'ok': False, 'stage': 'commit', 'err': (r.stderr or r.stdout)[-300:]}
        res = {'ok': True, 'stage': 'committed', 'msg': msg}
    r = run('push', '-q', 'origin', 'main')
    res['pushed'] = r.returncode == 0
    if r.returncode != 0:
        res['push_err'] = r.stderr[-300:]
    with locked('state'):
        st = load(); st['meta']['last_checkpoint'] = dict(res, at=time.strftime('%Y-%m-%dT%H:%M:%S')); _save(st)
    return res
