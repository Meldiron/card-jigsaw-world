import argparse, json, sys
from . import api, catalog, imagecache, audit as audit_mod, specs, pool as pool_mod, writer, sheet, state, filters, sources, checkpoint
from .paths import CACHE

def cmd_dump(a):
    s = catalog.dump(); print(len(s['packs']), 'packs', len(s['puzzles']), 'puzzles', len(s['events']), 'events')

def cmd_scan(a):
    snap = catalog.load()
    urls = [p['imageUrl'] for p in snap['puzzles'] if not a.pack or p['packId'] == a.pack]
    todo = [u for u in urls if a.force or not (imagecache.load_meta(u) or {}).get('ok')]
    print(f'{len(urls)} images, {len(todo)} to fetch')
    imagecache.fetch_many(todo, workers=a.workers, progress=100)
    bad = [u for u in urls if not (imagecache.load_meta(u) or {}).get('ok')]
    print('unreadable:', len(bad))

def cmd_audit(a):
    snap = catalog.load(refresh=a.refresh)
    summary, report = audit_mod.audit(snap, only=set(a.pack) if a.pack else None)
    print(json.dumps(summary, indent=1))
    if a.pack:
        for pid in a.pack:
            r = report.get(pid)
            if r: print(pid, r['count'], *['\n  ' + i for i in r['issues']])

def cmd_pool(a):
    snap = catalog.load()
    spec = specs.load(a.pack)
    topics = a.topic or None
    if a.more and not topics:
        topics = spec.get('more_topics') or spec['topics']
    pool, added = pool_mod.build(spec, snap, topics=topics, fetch_per_topic=a.fetch)
    ok = [c for c in pool['candidates'] if c.get('status') == 'ok']
    checkpoint.update(a.pack, step=f"pool {len(ok)} usable")
    print(f"pool {spec['pool']}: {len(pool['candidates'])} candidates (+{added}), {len(ok)} usable")

def cmd_recover(a):
    snap = catalog.load()
    import glob, os
    names = a.pool or [os.path.basename(f)[:-5] for f in glob.glob(str(CACHE / 'pools' / '*.json'))]
    for name in names:
        try:
            spec = specs.load(name) if specs.spec_path(name).exists() else dict(specs.DEFAULTS, id=name, pool=name)
        except SystemExit:
            spec = dict(specs.DEFAULTS, id=name, pool=name)
        spec['pool'] = name
        pool_mod.recover(spec, snap)

def cmd_sheet(a):
    snap = catalog.load()
    spec = specs.load(a.pack) if specs.spec_path(a.pack).exists() else {'id': a.pack, 'pool': a.pack}
    items = []
    rejected = state.rejects()
    if not a.candidates_only:
        snap = catalog.refresh_pack(snap, a.pack)
        puzzles = catalog.by_pack(snap).get(a.pack, [])
        imagecache.fetch_many([p['imageUrl'] for p in puzzles], workers=6)
        for i, p in enumerate(puzzles):
            m = imagecache.load_meta(p['imageUrl']) or {}
            note = f"{(p.get('author') or '')[:18]} {m.get('w', '?')}x{m.get('h', '?')}"
            items.append({'label': f"p{i + 1:02d} {(p.get('title') or '')[:12]}", 'url': p['imageUrl'], 'note': note, 'bad': state.is_rejected(p['imageUrl'], a.pack, rejected) or (m.get('w', 0) > m.get('h', 1))})
        if a.pack.startswith('daily-'):
            for it, p in zip(items, puzzles):
                it['label'] = f"p{puzzles.index(p) + 1:02d} {(p.get('date') or '')[5:10]}"
    if not a.puzzles_only:
        pool = pool_mod.load_pool(spec['pool'])
        for c in pool['candidates']:
            if c.get('status') != 'ok' or state.is_rejected(c['url'], a.pack, rejected): continue
            items.append({'label': f"{c['key']} {(c.get('topic') or '')[:12]}", 'url': c['url'], 'note': f"{c['author'][:16]} {c['w']}x{c['h']}"})
    out = CACHE / 'sheets' / f'{a.pack}.png'
    paths = sheet.render(items, out, title=a.pack)
    for p in paths: print(p)

def cmd_reject(a):
    snap = catalog.load()
    spec = specs.load(a.pack) if specs.spec_path(a.pack).exists() else {'id': a.pack, 'pool': a.pack}
    puzzles = catalog.by_pack(snap).get(a.pack, [])
    pool = pool_mod.load_pool(spec['pool'])
    by_key = {c['key']: c for c in pool['candidates']}
    n = 0
    for lab in a.ids:
        lab = lab.strip().rstrip(',')
        if not lab: continue
        if lab.startswith('p') and lab[1:].isdigit():
            i = int(lab[1:]) - 1
            if i >= len(puzzles): print('no puzzle', lab); continue
            state.add_reject(puzzles[i]['imageUrl'], a.reason, a.pack, puzzles[i]['$id']); n += 1
        elif lab in by_key:
            by_key[lab]['status'] = 'rejected'; by_key[lab]['why'] = a.reason
            state.add_reject(by_key[lab]['url'], a.reason, a.pack, lab); n += 1
        else:
            # allow raw puzzle ids too
            m = [p for p in puzzles if p['$id'] == lab]
            if m: state.add_reject(m[0]['imageUrl'], a.reason, a.pack, lab); n += 1
            else: print('unknown id', lab)
    pool_mod.save_pool(pool)
    if n: checkpoint.update(a.pack, status='audited', step=f'reject {n} {a.reason}')
    print(f'rejected {n} ({a.reason})')

def cmd_apply(a):
    snap = catalog.load()
    spec = specs.load(a.pack)
    daily = a.pack.startswith('daily-')
    writer.apply(spec, snap, target=a.target, picks=a.pick or (), auto=not a.no_auto, dry=a.dry, daily=daily)

def cmd_newpack(a):
    snap = catalog.load()
    spec = specs.load(a.pack)
    writer.new_pack(spec, snap)
    print('pack row ready:', spec['id'])

def cmd_newdaily(a):
    snap = catalog.load()
    for month in a.month:
        writer.new_daily(specs.load(f'daily-{month}'), snap, month, picks=a.pick or (), dry=a.dry)

def cmd_finalize(a):
    snap = catalog.load()
    spec = specs.load(a.pack) if specs.spec_path(a.pack).exists() else {'id': a.pack, 'pool': a.pack}
    snap = catalog.refresh_pack(snap, a.pack)
    writer.finalize_pack(spec, snap)
    print('finalized', a.pack)

def cmd_clone(a):
    snap = catalog.load()
    writer.clone(a.src, a.dst, snap)

def cmd_summary(a):
    """Totals from reports/changes.jsonl: packs touched, images removed/added/replaced, packs created."""
    import collections
    from .paths import REPORTS
    ev = collections.Counter(); packs = collections.defaultdict(collections.Counter); reasons = collections.Counter()
    for line in (REPORTS / 'changes.jsonl').read_text().splitlines():
        try: r = json.loads(line)
        except Exception: continue
        ev[r['event']] += 1
        if r['event'] in ('create', 'delete', 'replace'):
            packs[r['pack']][r['event']] += 1
            if r['event'] in ('delete', 'replace'): reasons[r.get('reason', '').split(':')[0]] += 1
        if r['event'] == 'clone': packs[r['dst']]['create'] += r.get('count', 0)
    print('events:', dict(ev))
    print('packs touched:', len(packs))
    print('removal reasons:', dict(reasons.most_common()))
    if a.verbose:
        for pid, c in sorted(packs.items()): print(f'  {pid}: {dict(c)}')

def cmd_plan(a):
    snap = catalog.load()
    st = checkpoint.plan(snap)
    print('state entries:', len(st['packs']), checkpoint.board(st))

def cmd_verify(a):
    """Audit the given packs; clean packs with >= 20 puzzles become 'verified'."""
    snap = catalog.load()
    for pid in a.pack:
        snap = catalog.refresh_pack(snap, pid)
    summary, report = audit_mod.audit(snap, only=set(a.pack), write=False)
    for pid in a.pack:
        r = report.get(pid)
        if not r:
            print(pid, 'not in catalogue'); continue
        issues = [i for i in r['issues']]
        if not issues and r['count'] >= filters.MIN_COUNT:
            checkpoint.update(pid, status='verified', step='verify', puzzles=r['count'], issues=0)
            print(f'{pid}: verified ({r["count"]} puzzles)')
        else:
            checkpoint.update(pid, step='verify failed', puzzles=r['count'], issues=len(issues))
            print(f'{pid}: NOT verified, {len(issues)} issues' + ''.join('\n  ' + i for i in issues[:12]))

def cmd_resume(a):
    """Show the durable state board and the next packs to work on; --auto builds missing pools."""
    st = checkpoint.load()
    if not st['packs']:
        st = checkpoint.plan(catalog.load())
    print('board:', checkpoint.board(st), '| last checkpoint:', st['meta'].get('last_checkpoint', {}).get('at', 'never'))
    from .paths import REPORTS
    batch = None
    if a.batch:
        batches = json.loads((REPORTS / 'batches.json').read_text())
        batch = batches.get(a.batch)
        if not batch: raise SystemExit(f'unknown batch {a.batch}; see reports/batches.json')
        if batch.get('note'): print('batch note:', batch['note'])
        print('batch report file: reports/' + batch['report'])
    def in_scope(pid):
        if batch:
            if 'packs' in batch: return pid in batch['packs']
            return pid.startswith(batch['prefix'])
        return not a.prefix or pid.startswith(a.prefix)
    if batch and 'packs' in batch:
        done = [pid for pid in batch['packs'] if st['packs'].get(pid, {}).get('status') in ('fixed', 'verified')]
        print(f"batch {a.batch}: {len(done)} of {len(batch['packs'])} packs fixed/verified")
    todo = [(pid, e) for pid, e in sorted(st['packs'].items()) if e['status'] in ('pending', 'audited') and in_scope(pid)]
    print(f'{len(todo)} packs still to finish; next {min(a.next, len(todo))}:')
    for pid, e in todo[:a.next]:
        has_spec = specs.spec_path(pid).exists()
        pool = pool_mod.load_pool(specs.load(pid)['pool']) if has_spec else {'candidates': []}
        ok = sum(1 for c in pool['candidates'] if c.get('status') == 'ok')
        print(f"  {pid}: {e['status']}, last step: {e.get('last_step', '-')}, spec: {'yes' if has_spec else 'NO'}, usable candidates: {ok}")
    if a.auto:
        snap = catalog.load()
        for pid, e in todo[:a.next]:
            if specs.spec_path(pid).exists():
                spec = specs.load(pid)
                pool = pool_mod.load_pool(spec['pool'])
                if not pool['candidates']:
                    print('building pool for', pid)
                    pool_mod.build(spec, snap)
                    checkpoint.update(pid, step='pool (resume --auto)')

def cmd_checkpoint(a):
    res = checkpoint.git_checkpoint(a.message)
    print(json.dumps(res))

def cmd_status(a):
    snap = catalog.load()
    for pid in a.pack:
        snap = catalog.refresh_pack(snap, pid)
        puzzles = catalog.by_pack(snap).get(pid, [])
        pool = pool_mod.load_pool(specs.load(pid)['pool'] if specs.spec_path(pid).exists() else pid)
        ok = sum(1 for c in pool['candidates'] if c.get('status') == 'ok')
        rej = sum(1 for p in puzzles if state.is_rejected(p['imageUrl'], pid))
        print(f'{pid}: {len(puzzles)} puzzles ({rej} rejected pending), pool {len(pool["candidates"])} / {ok} usable; openverse budget {sources.openverse_budget_left()}')

def cmd_sources(a):
    """Every picture provider: active or not (key present / keyless), licence policy, one live health check."""
    rows = sources.health(names=a.name or None, refresh=a.refresh, live=not a.offline)
    w = max([len(r[0]) for r in rows] + [8]) + 2
    print(f"{'provider':<{w}}{'status':<42}{'licence policy':<54}health")
    for name, active, status, policy, text in rows:
        print(f'{name:<{w}}{status[:40]:<42}{policy[:52]:<54}{text}')
    print('\nA spec opts in by listing providers in "sources" (default ["commons"]). Keys: secrets/content-keys.env. '
          'Stock licences (Pexels, Pixabay, Unsplash, Flickr Commons) also need owner review and "allow_licences"; '
          'see docs/content-sources.md.')


def cmd_host(a):
    """Copy every catalogue picture and cover into Appwrite Storage and point the rows at it."""
    from . import host
    from .paths import REPORTS
    snap = catalog.load(refresh=True)
    done, failures = host.migrate(snap, pack=a.pack, workers=a.workers, dry=a.dry)
    if failures:
        import json as _j
        (REPORTS / 'host-failures.json').write_text(_j.dumps([{'table': t, 'id': i, 'src': s, 'kind': k, 'error': e} for (t, i, s, k), e in failures], indent=1))
        print('  failures written to reports/host-failures.json')


def cmd_giantcheck(a):
    """Giant packs: source size, sharpness at 100%, flat / dark / look-alike cards at a 300-card cut, and a
    100% crop sheet per item (cjw/giant.py)."""
    from . import giant
    from concurrent.futures import ThreadPoolExecutor
    snap = catalog.load()
    spec = specs.load(a.pack)
    px = int(spec.get('host_max_px') or 4096)
    items = []
    if not a.candidates_only:
        snap = catalog.refresh_pack(snap, a.pack)
        for i, p in enumerate(catalog.by_pack(snap).get(a.pack, [])):
            items.append((f'p{i + 1:02d}', p['imageUrl'], p.get('title') or ''))
    if not a.puzzles_only:
        rejected = state.rejects()
        for c in pool_mod.load_pool(spec['pool'])['candidates']:
            if c.get('status') != 'ok' or state.is_rejected(c['url'], a.pack, rejected): continue
            if a.keys and c['key'] not in a.keys: continue
            items.append((c['key'], c['url'], c.get('title') or c.get('topic') or ''))
    out_dir = CACHE / 'sheets' / 'giant' / a.pack
    if a.thumbs:          # quick prescreen on cached thumbnails, nothing downloaded
        rows = []
        for key, url, title in items:
            tp = imagecache.thumb_path(url)
            if tp.exists():
                st = giant.prescreen(tp)
                rows.append((st['flat'] + st['dark'] + st['alike'], key, title, st))
        for _, key, title, st in sorted(rows):
            print(f"{key:5} flat {st['flat']:4.0%} dark {st['dark']:4.0%} alike {st['alike']:4.0%}  {title[:50]}")
        print(f'{len(rows)} prescreened on thumbnails (rough: run without --thumbs on the shortlist)')
        return
    if a.review:          # larger sheets for the people / text check
        for p in giant.review_sheets(items, out_dir): print(p)
        return

    def one(it):
        key, url, title = it
        return key, title, giant.check(url, px, force=a.force, crop_path=out_dir / f'{key}.png')

    with ThreadPoolExecutor(max_workers=2) as ex:      # big files: keep the owner's line free
        rows = list(ex.map(one, items))
    passed = 0
    for key, title, st in rows:
        why = giant.verdict(st)
        passed += not why
        if st.get('ok'):
            print(f"{key:5} {'FAIL' if why else 'ok  '} {st['src_w']}x{st['src_h']} sharp {st['sharp']:5.2f} flat {st['flat']:4.0%} "
                  f"dark {st['dark']:4.0%} alike {st['alike']:4.0%}  {title[:42]}{'  -- ' + why if why else ''}")
        else:
            print(f'{key:5} FAIL {why}')
    print(f'{passed} of {len(rows)} pass the measurable giant rules; 100% crop sheets in {out_dir}')


def cmd_retitle(a):
    """Rename one puzzle (titles come from search topics and are sometimes inexact)."""
    title = ' '.join(a.title).strip()
    if not title: raise SystemExit('empty title')
    api.update_row('puzzles', a.puzzle, {'title': title[:90]})
    state.log('retitle', puzzle=a.puzzle, title=title[:90])
    print(f'{a.puzzle}: "{title[:90]}"')

def main(argv):
    ap = argparse.ArgumentParser(prog='cli.py')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('dump').set_defaults(f=cmd_dump)
    p = sub.add_parser('host'); p.add_argument('--pack'); p.add_argument('--workers', type=int, default=4); p.add_argument('--dry', action='store_true'); p.set_defaults(f=cmd_host)
    p = sub.add_parser('scan'); p.add_argument('--pack'); p.add_argument('--force', action='store_true'); p.add_argument('--workers', type=int, default=8); p.set_defaults(f=cmd_scan)
    p = sub.add_parser('audit'); p.add_argument('--pack', nargs='*'); p.add_argument('--refresh', action='store_true'); p.set_defaults(f=cmd_audit)
    p = sub.add_parser('pool'); p.add_argument('pack'); p.add_argument('--topic', nargs='*'); p.add_argument('--more', action='store_true'); p.add_argument('--fetch', type=int); p.set_defaults(f=cmd_pool)
    p = sub.add_parser('recover'); p.add_argument('pool', nargs='*'); p.set_defaults(f=cmd_recover)
    p = sub.add_parser('sheet'); p.add_argument('pack'); p.add_argument('--candidates-only', action='store_true'); p.add_argument('--puzzles-only', action='store_true'); p.set_defaults(f=cmd_sheet)
    p = sub.add_parser('reject'); p.add_argument('pack'); p.add_argument('ids', nargs='+'); p.add_argument('--reason', required=True); p.set_defaults(f=cmd_reject)
    p = sub.add_parser('apply'); p.add_argument('pack'); p.add_argument('--target', type=int); p.add_argument('--pick', nargs='*'); p.add_argument('--no-auto', action='store_true'); p.add_argument('--dry', action='store_true'); p.set_defaults(f=cmd_apply)
    p = sub.add_parser('newpack'); p.add_argument('pack'); p.set_defaults(f=cmd_newpack)
    p = sub.add_parser('newdaily'); p.add_argument('month', nargs='+', help='YYYY-MM'); p.add_argument('--pick', nargs='*'); p.add_argument('--dry', action='store_true'); p.set_defaults(f=cmd_newdaily)
    p = sub.add_parser('finalize'); p.add_argument('pack'); p.set_defaults(f=cmd_finalize)
    p = sub.add_parser('clone'); p.add_argument('src'); p.add_argument('dst'); p.set_defaults(f=cmd_clone)
    p = sub.add_parser('summary'); p.add_argument('-v', '--verbose', action='store_true'); p.set_defaults(f=cmd_summary)
    p = sub.add_parser('plan'); p.set_defaults(f=cmd_plan)
    p = sub.add_parser('verify'); p.add_argument('pack', nargs='+'); p.set_defaults(f=cmd_verify)
    p = sub.add_parser('giantcheck'); p.add_argument('pack'); p.add_argument('--keys', nargs='*'); p.add_argument('--candidates-only', action='store_true'); p.add_argument('--puzzles-only', action='store_true'); p.add_argument('--force', action='store_true'); p.add_argument('--thumbs', action='store_true'); p.add_argument('--review', action='store_true'); p.set_defaults(f=cmd_giantcheck)
    p = sub.add_parser('retitle'); p.add_argument('puzzle'); p.add_argument('title', nargs='+'); p.set_defaults(f=cmd_retitle)
    p = sub.add_parser('resume'); p.add_argument('--prefix'); p.add_argument('--batch'); p.add_argument('--next', type=int, default=10); p.add_argument('--auto', action='store_true'); p.set_defaults(f=cmd_resume)
    p = sub.add_parser('checkpoint'); p.add_argument('-m', '--message'); p.set_defaults(f=cmd_checkpoint)
    p = sub.add_parser('status'); p.add_argument('pack', nargs='+'); p.set_defaults(f=cmd_status)
    p = sub.add_parser('sources'); p.add_argument('name', nargs='*'); p.add_argument('--refresh', action='store_true'); p.add_argument('--offline', action='store_true'); p.set_defaults(f=cmd_sources)
    a = ap.parse_args(argv)
    a.f(a)
