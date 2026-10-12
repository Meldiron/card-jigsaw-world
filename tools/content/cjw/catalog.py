"""Local snapshot of the live catalogue (packs, puzzles, events) in the cache dir."""
import json, time
from .paths import CACHE
from . import api
from .lock import locked

SNAP = CACHE / 'catalog.json'

def normalise(rows, kind):
    """Rows point at our Appwrite Storage copies; the tool keys everything (image cache, rejects,
    duplicates, provenance) on the original source URL. Swap it in and keep the hosted URL aside."""
    for r in rows:
        if kind == 'puzzles':
            r['hostedImageUrl'] = r.get('imageUrl')
            if r.get('sourceUrl'): r['imageUrl'] = r['sourceUrl']
        else:
            r['hostedCoverUrl'] = r.get('coverUrl')
            if r.get('coverSourceUrl'): r['coverUrl'] = r['coverSourceUrl']
    return rows

def dump():
    packs = normalise(api.list_rows('packs'), 'packs')
    puzzles = normalise(api.list_rows('puzzles'), 'puzzles')
    events = normalise(api.list_rows('events'), 'events')
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
        pack = normalise([api.get_row('packs', pack_id)], 'packs')[0]
    except RuntimeError:
        pack = None
    puzzles = normalise(api.list_rows('puzzles', [api.q('equal', pack_id, attribute='packId')]), 'puzzles')
    with locked('catalog'):
        snap = json.loads(SNAP.read_text()) if SNAP.exists() else snap
        snap['packs'] = [p for p in snap['packs'] if p['$id'] != pack_id]
        if pack: snap['packs'].append(pack)
        snap['puzzles'] = [p for p in snap['puzzles'] if p['packId'] != pack_id]
        snap['puzzles'] += puzzles
        SNAP.write_text(json.dumps(snap))
    return snap
