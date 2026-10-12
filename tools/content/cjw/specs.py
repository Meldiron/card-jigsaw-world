"""Pack specs: tools/content/specs/<packId>.json (daily packs share specs/daily.json)."""
import json
from .paths import SPECS

DEFAULTS = dict(kind='library', sources=['commons'], commons_quality=True, per_topic=2, fetch_per_topic=6,
                target=24, min_short=900, author_cap=2, openverse_category='photograph', topics=[], queries=[],
                commons_extra='', allow_words=[], pool=None, quality_deepcat=None)

def spec_path(pack_id):
    p = SPECS / f'{pack_id}.json'
    if not p.exists() and pack_id.startswith('daily-'):
        year = pack_id.split('-')[1]
        p = SPECS / f'daily-{year}.json'          # per-year pool so two workers can run in parallel
        if not p.exists():
            p = SPECS / 'daily.json'
    return p

def load(pack_id):
    p = spec_path(pack_id)
    if not p.exists():
        raise SystemExit(f'no spec for {pack_id}: create {p}')
    s = dict(DEFAULTS); s.update(json.loads(p.read_text()))
    s.setdefault('id', pack_id)
    s['pool'] = s.get('pool') or (p.stem if p.name.startswith('daily') else s['id'])
    return s

def save(spec):
    (SPECS / f"{spec['id']}.json").write_text(json.dumps(spec, indent=1, ensure_ascii=False))
