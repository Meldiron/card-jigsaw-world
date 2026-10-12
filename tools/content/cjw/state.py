"""Git-tracked state: rejections (by URL), provenance per puzzle, change log."""
import json, time
from .paths import STATE, REPORTS
from .lock import locked

REJECTS = STATE / 'rejects.json'
PROV = STATE / 'provenance.json'
LOG = REPORTS / 'changes.jsonl'

def _load(p):
    return json.loads(p.read_text()) if p.exists() else {}

def rejects(): return _load(REJECTS)
def provenance(): return _load(PROV)

def add_reject(url, reason, pack, label=''):
    with locked('rejects'):
        r = rejects()
        r[url] = {'reason': reason, 'pack': pack, 'label': label, 'at': time.strftime('%Y-%m-%d')}
        REJECTS.write_text(json.dumps(r, indent=0, sort_keys=True))

def add_provenance(puzzle_id, rec):
    with locked('provenance'):
        p = provenance()
        p[puzzle_id] = rec
        PROV.write_text(json.dumps(p, indent=0, sort_keys=True))

def log(event, **kw):
    kw.update(event=event, at=time.strftime('%Y-%m-%dT%H:%M:%S'))
    with LOG.open('a') as f:
        f.write(json.dumps(kw) + '\n')
    pack = kw.get('pack') or kw.get('dst')
    if pack:
        from . import checkpoint
        checkpoint.pack_log(pack, json.dumps({k: v for k, v in kw.items() if k not in ('at', 'pack')}))

PACK_SCOPED = ('off-theme', 'weak', 'similar')   # reasons that only apply inside the pack where they were given

def is_rejected(url, pack, rejected=None):
    rec = (rejected if rejected is not None else rejects()).get(url)
    if not rec: return False
    if rec['reason'].split(':')[0] in PACK_SCOPED and rec.get('pack') != pack: return False
    return True
