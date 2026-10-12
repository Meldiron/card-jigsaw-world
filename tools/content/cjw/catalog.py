"""Local snapshot of the live catalogue (packs, puzzles, events) in the cache dir."""
import json, time
from .paths import CACHE
from . import api
from .lock import locked

SNAP = CACHE / 'catalog.json'

def dump():
    packs = api.list_rows('packs')
    puzzles = api.list_rows('puzzles')
    events = api.list_rows('events')
    snap = {'at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'packs': packs, 'puzzles': puzzles, 'events': events}
    with locked('catalog'):
        SNAP.write_text(json.dumps(snap))
    return snap

def load(refresh=False):
    if refresh or not SNAP.exists():
        return dump()
    return json.loads(SNAP.read_text())

def by_pack(snap):
    out = {}
    for p in snap['puzzles']:
        out.setdefault(p['packId'], []).append(p)
    for v in out.values():
        v.sort(key=lambda r: (r.get('sortOrder') or 0, r['$id']))
    return out

def pack_index(snap):
    return {p['$id']: p for p in snap['packs']}

def refresh_pack(snap, pack_id):
    """Re-read one pack and its puzzles from the server into the snapshot (and save, merge-safe)."""
    try:
        pack = api.get_row('packs', pack_id)
    except RuntimeError:
        pack = None
    puzzles = api.list_rows('puzzles', [api.q('equal', pack_id, attribute='packId')])
    with locked('catalog'):
        snap = json.loads(SNAP.read_text()) if SNAP.exists() else snap
        snap['packs'] = [p for p in snap['packs'] if p['$id'] != pack_id]
        if pack: snap['packs'].append(pack)
        snap['puzzles'] = [p for p in snap['puzzles'] if p['packId'] != pack_id]
        snap['puzzles'] += puzzles
        SNAP.write_text(json.dumps(snap))
    return snap
