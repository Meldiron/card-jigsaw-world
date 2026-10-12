"""Build and maintain per-pack candidate pools (cache/pools/<pool>.json)."""
import json, re, time
import numpy as np
from .paths import CACHE
from . import sources, filters, imagecache, catalog, state

def pool_path(name): return CACHE / 'pools' / f'{name}.json'

def load_pool(name):
    p = pool_path(name)
    return json.loads(p.read_text()) if p.exists() else {'pool': name, 'candidates': []}

def save_pool(pool):
    pool_path(pool['pool']).write_text(json.dumps(pool))

class HashIndex:
    """Vectorised near-duplicate lookup over catalogue metas."""
    def __init__(self, entries):
        # entries: list of (id, packId, meta)
        self.ids = [e[0] for e in entries]; self.packs = [e[1] for e in entries]
        self.ph = np.array([int(e[2]['phash'], 16) for e in entries], dtype=np.uint64)
        self.dh = np.array([int(e[2]['dhash'], 16) for e in entries], dtype=np.uint64)
        self.mini = np.array([e[2]['mini'] for e in entries], dtype=np.float32) if entries else np.zeros((0, 48), np.float32)
    @staticmethod
    def _pop(x):
        return np.unpackbits(x.view(np.uint8).reshape(-1, 8), axis=1).sum(axis=1)
    def near(self, meta, pack_filter=None):
        if not len(self.ids) or not meta or not meta.get('ok'): return []
        ph = self._pop(self.ph ^ np.uint64(int(meta['phash'], 16)))
        dh = self._pop(self.dh ^ np.uint64(int(meta['dhash'], 16)))
        md = np.sqrt(((self.mini - np.array(meta['mini'], np.float32)) ** 2).mean(axis=1))
        hit = (ph <= 8) | (dh <= 6) | ((ph <= 14) & (md < 22)) | (md < 9)
        out = []
        for i in np.nonzero(hit)[0]:
            if pack_filter and self.packs[i] not in pack_filter: continue
            out.append((self.ids[i], self.packs[i], int(ph[i]), int(dh[i]), float(md[i])))
        return out

def catalogue_index(snap, only_packs=None):
    entries = []
    for p in snap['puzzles']:
        if only_packs and p['packId'] not in only_packs: continue
        m = imagecache.load_meta(p['imageUrl'])
        if m and m.get('ok'):
            entries.append((p['$id'], p['packId'], m))
    return HashIndex(entries)

def _passes_prefilter(c, spec, catalogue_urls, rejected):
    if c['url'] in catalogue_urls: return 'in-catalogue'
    if state.is_rejected(c['url'], spec['id'], rejected): return 'rejected-before'
    if not filters.licence_ok(c['licence']): return 'licence'
    fl = filters.keyword_flags(c['text'] + ' ' + c['title'], allow=spec.get('allow_words', []))
    if fl: return ';'.join(sorted(fl))
    if c['w'] and c['h']:
        sf = filters.size_flags(c['w'], c['h'], spec['min_short'])
        if 'landscape' in sf: return 'landscape'
        if 'too-small' in sf or 'small' in sf: return 'small'
    return ''

def search_topic(topic, spec):
    """Run the spec's sources for one topic. Returns candidates in preference order."""
    found = []
    if topic.startswith('cat:'):
        return sources.commons_category_deep(topic[4:], limit=spec.get('category_limit', 300), depth=spec.get('category_depth', 2))
    for src in spec['sources']:
        if src == 'commons':
            if spec['commons_quality']:
                found += [dict(c, quality=True) for c in sources.commons_search(topic, limit=40, extra=spec['commons_extra'], quality_cat=spec.get('quality_deepcat'))]
            found += sources.commons_search(topic, limit=40, quality=False, extra=spec['commons_extra'])
        elif src == 'openverse':
            found += sources.openverse_search(topic, category=spec['openverse_category'])
        elif src == 'cma':
            found += sources.cma_search(topic)
        elif src == 'nasa':
            found += sources.nasa_search(topic)
    # de-dup by url, keep first
    seen, out = set(), []
    for c in found:
        if c['url'] in seen: continue
        seen.add(c['url']); out.append(c)
    return out

def classify(c, m, spec, index, pindex):
    """Set c['status'] / c['why'] from the fetched meta: readability, orientation, size, duplicates, flatness."""
    c['status'] = 'ok'; c['why'] = ''
    if not m or not m.get('ok'):
        c['status'] = 'bad'; c['why'] = (m or {}).get('err', 'fetch failed'); return c
    c['w'], c['h'] = m['w'], m['h']
    sf = filters.size_flags(m['w'], m['h'], spec['min_short'])
    if 'landscape' in sf: c['status'] = 'bad'; c['why'] = 'landscape'
    elif 'too-small' in sf or 'small' in sf: c['status'] = 'bad'; c['why'] = f"small {m['w']}x{m['h']}"
    else:
        near = index.near(m)
        if near:
            c['status'] = 'dup'; c['why'] = f'dup of {near[0][0]} ({near[0][1]})'
        else:
            nearp = pindex.near(m)
            if nearp:
                c['status'] = 'dup'; c['why'] = f'dup of candidate {nearp[0][0]}'
            else:
                c['flat'] = m['flat']; c['entropy'] = m['entropy']
                if m['flat'] > 0.55: c['status'] = 'bad'; c['why'] = f"flat {m['flat']}"
    return c

def recover(spec, snap, verbose=True):
    """Re-fetch candidates that failed with a throttle (429/503) and classify them."""
    pool = load_pool(spec['pool'])
    todo = [c for c in pool['candidates'] if c.get('status') == 'bad' and str(c.get('why', '')).startswith(('http 429', 'http 503'))]
    if not todo: return pool, 0
    index = catalogue_index(snap)
    n = 0
    for c in todo:
        m = imagecache.fetch(c['url'])
        pindex = HashIndex([(cc['key'], spec['pool'], imagecache.load_meta(cc['url'])) for cc in pool['candidates'] if cc.get('status') == 'ok' and cc is not c and imagecache.load_meta(cc['url'])])
        classify(c, m, spec, index, pindex)
        if c['status'] == 'ok': n += 1
        save_pool(pool)
    if verbose: print(f"  recovered {n} of {len(todo)} throttled candidates in pool {spec['pool']}")
    return pool, n

def build(spec, snap, topics=None, fetch_per_topic=None, verbose=True):
    pool = load_pool(spec['pool'])
    have = {c['url'] for c in pool['candidates']}
    catalogue_urls = {p['imageUrl'] for p in snap['puzzles']}
    rejected = state.rejects()
    topics = topics or spec['topics'] or spec['queries']
    fetch_per_topic = fetch_per_topic or spec['fetch_per_topic']
    index = catalogue_index(snap)
    pool_index_entries = [(c['key'], spec['pool'], imagecache.load_meta(c['url'])) for c in pool['candidates'] if c.get('status') == 'ok' and imagecache.load_meta(c['url'])]
    pindex = HashIndex([e for e in pool_index_entries if e[2] and e[2].get('ok')])
    n0 = len(pool['candidates'])
    for topic in topics:
        cands = search_topic(topic, spec)
        kept = []
        for c in cands:
            if c['url'] in have: continue
            why = _passes_prefilter(c, spec, catalogue_urls, rejected)
            if why:
                continue
            kept.append(c)
        # commons quality first, then larger originals
        kept.sort(key=lambda c: (not c.get('quality'), -(c.get('orig_h') or c['h'] or 0)))
        to_fetch = kept[:fetch_per_topic]
        metas = imagecache.fetch_many([c['url'] for c in to_fetch], workers=2)
        added = 0
        for c in to_fetch:
            c['topic'] = topic
            c['key'] = f"c{len(pool['candidates']) + 1:02d}"
            classify(c, metas.get(c['url']), spec, index, pindex)
            pool['candidates'].append(c); have.add(c['url'])
            if c['status'] == 'ok':
                added += 1
                pindex = HashIndex([(cc['key'], spec['pool'], imagecache.load_meta(cc['url'])) for cc in pool['candidates'] if cc.get('status') == 'ok' and imagecache.load_meta(cc['url'])])
        if verbose:
            print(f"  topic '{topic}': {len(cands)} found, {len(kept)} passed prefilter, {added} usable", flush=True)
        save_pool(pool)
    pool['built'] = time.strftime('%Y-%m-%dT%H:%M:%S')
    save_pool(pool)
    return pool, len(pool['candidates']) - n0

def nice_title(c, fallback, taken=()):
    """Curated topic name when there is one (e.g. 'Lake Louise'); otherwise a cleaned file title.
    Duplicate titles inside a pack get a roman suffix."""
    topic = c.get('topic') or ''
    base = None
    if topic.startswith('cat:'):
        base = _clean(c.get('title') or '') or fallback
    elif topic and c.get('provider', '').startswith(('commons', 'openverse')):
        base = topic[0].upper() + topic[1:]
    elif c.get('provider') in ('cma', 'nasa') and c.get('title'):
        base = _clean(c['title'])
    if not base:
        base = _clean(c.get('title') or '') or (fallback[0].upper() + fallback[1:] if fallback else 'Picture')
    base = base[:80]
    t, n = base, 1
    while t in taken:
        n += 1; t = f"{base} {'I' * n if n < 4 else n}"
    return t[:90]

def _clean(t):
    t = re.sub(r'\b(IMG|DSC|DSCN|DSCF|P\d{6,}|\d{4,}|JPG|jpg|RAW|HDR|Pano|panorama|crop|edit|\(\d+\)|4K|8K)\b', ' ', t)
    t = re.sub(r'[-_]+', ' ', t)
    t = re.sub(r'\s+', ' ', t).strip(' -,.')
    words = [w for w in t.split() if re.search(r'[A-Za-z]', w)]
    if len(words) < 2 or len(t) > 60:
        return ''
    return t[0].upper() + t[1:]

def _old_nice_title(c, fallback):
    t = c.get('title') or ''
    t = re.sub(r'\b(IMG|DSC|DSCN|DSCF|P\d{6,}|\d{4,}|JPG|jpg|RAW|HDR|Pano|panorama|crop|edit|\(\d+\)|4K|8K|by [^,]+$)\b', ' ', t)
    t = re.sub(r'[-_]+', ' ', t)
    t = re.sub(r'\s+', ' ', t).strip(' -,.')
    words = [w for w in t.split() if re.search(r'[A-Za-z]', w)]
    if len(words) < 2 or len(t) > 60:
        return fallback[:90]
    return t[:90]
