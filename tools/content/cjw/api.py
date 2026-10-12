"""Minimal Appwrite TablesDB REST client (rows.read / rows.write / tables.read)."""
import json, time, urllib.request, urllib.parse, urllib.error
from .paths import SECRET_KEY

ENDPOINT = 'https://fra.cloud.appwrite.io/v1'
PROJECT = '6acb4de5003e38d5ebd9'
DB = 'cjw'
_key = None
WRITE_DELAY = 0.08   # seconds between write calls (gentle on rate limits)

def _headers():
    global _key
    if _key is None:
        _key = SECRET_KEY.read_text().strip()
    return {'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': _key, 'Content-Type': 'application/json'}

def call(method, path, body=None, params=None, retries=4):
    url = ENDPOINT + path
    if params:
        url += '?' + urllib.parse.urlencode(params, doseq=True)
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers=_headers(), method=method, data=data)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors='replace')
            if e.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                time.sleep(2 * (attempt + 1)); continue
            raise RuntimeError(f'{method} {path} -> {e.code}: {text[:300]}')
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < retries - 1:
                time.sleep(2 * (attempt + 1)); continue
            raise

def q(method, *values, attribute=None):
    d = {'method': method, 'values': list(values)}
    if attribute: d['attribute'] = attribute
    return json.dumps(d)

def list_rows(table, queries=(), select=None, page=500):
    rows, cursor = [], None
    while True:
        qs = [q('limit', page)] + list(queries)
        if select: qs.append(q('select', *select))
        if cursor: qs.append(q('cursorAfter', cursor))
        r = call('GET', f'/tablesdb/{DB}/tables/{table}/rows', params={'queries[]': qs})
        rows += r['rows']
        if len(r['rows']) < page: break
        cursor = r['rows'][-1]['$id']
    return rows

def get_row(table, row_id):
    return call('GET', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}')

def create_row(table, data, row_id='unique()'):
    time.sleep(WRITE_DELAY)
    return call('POST', f'/tablesdb/{DB}/tables/{table}/rows',
                {'rowId': row_id, 'data': data, 'permissions': ['read("any")']})

def update_row(table, row_id, data):
    time.sleep(WRITE_DELAY)
    return call('PATCH', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}', {'data': data})

def delete_row(table, row_id):
    time.sleep(WRITE_DELAY)
    return call('DELETE', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}')
