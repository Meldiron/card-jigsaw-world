"""Small Appwrite REST client for the Carden admin scripts (standard library only, so
it runs with the system python3 or the repo .venv).

The key comes from secrets/appwrite-users-key.txt (scopes: users.read, users.write, rows.read,
rows.write, files.read, files.write). Key values are never printed.
"""
import json
import os
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ENDPOINT = 'https://fra.cloud.appwrite.io/v1'
PROJECT = '6acb4de5003e38d5ebd9'
DB = 'cjw'
UPLOADS_BUCKET = 'user-uploads'
KEY_FILE = os.path.join(ROOT, 'secrets', 'appwrite-users-key.txt')

# Every table keyed by a player's user id (profiles use the user id as the row id as well).
PLAYER_TABLES = ['profiles', 'progress', 'ledger', 'event_progress', 'friends', 'my_puzzles', 'purchases', 'code_claims', 'reports', 'blocks', 'feedback', 'messages', 'gifts', 'coop_games', 'coop_moves']
# Tables keyed by two player columns instead of `userId` (both directions belong to the player;
# messages: the player's inbox and the friend gifts they sent).
PAIR_TABLES = {'reports': ('reporterId', 'reportedId'), 'blocks': ('blockerId', 'blockedId'), 'messages': ('userId', 'fromUserId'), 'gifts': ('senderId', 'recipientId')}
# Tables keyed by the player as host: their co-op games (Play together). A game goes with every move
# in it (`coop_moves.gameId`); its team is left to the hourly co-op cleanup (function `api`; these keys have no
# teams scope), which deletes teams without a game.
HOST_TABLES = {'coop_games': 'hostId'}


class AppwriteError(Exception):
    def __init__(self, code, body):
        super().__init__(f'{code}: {body[:300]}')
        self.code = code
        self.body = body


def load_key(path=KEY_FILE):
    if not os.path.exists(path):
        raise SystemExit(f'missing {os.path.relpath(path, ROOT)} (an API key with users.read/write, rows.read/write, files.read/write)')
    return open(path).read().strip()


def q(method, attribute=None, values=None):
    d = {'method': method}
    if attribute is not None:
        d['attribute'] = attribute
    if values is not None:
        d['values'] = values
    return json.dumps(d)


class Client:
    def __init__(self, key=None):
        self.key = key or load_key()

    def call(self, method, path, params=None, body=None, raw=False):
        url = ENDPOINT + path
        if params:
            url += '?' + urllib.parse.urlencode(params, doseq=True)
        data = json.dumps(body).encode() if body is not None else None
        headers = {'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': self.key}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                payload = resp.read()
        except urllib.error.HTTPError as e:
            raise AppwriteError(e.code, e.read().decode(errors='replace')) from None
        if raw:
            return payload
        return json.loads(payload) if payload else {}

    def list_all(self, path, key, queries=(), page=100):
        """Every item of a list endpoint, cursor-paginated (never a single page)."""
        out, cursor = [], None
        while True:
            qs = list(queries) + [q('limit', values=[page])]
            if cursor:
                qs.append(q('cursorAfter', values=[cursor]))
            items = self.call('GET', path, {'queries[]': qs})[key]
            out += items
            if len(items) < page:
                return out
            cursor = items[-1]['$id']

    # Users ---------------------------------------------------------------------------------------
    def users(self):
        return self.list_all('/users', 'users')

    def user(self, user_id):
        try:
            return self.call('GET', f'/users/{user_id}')
        except AppwriteError as e:
            if e.code == 404:
                return None
            raise

    def sessions(self, user_id):
        return self.call('GET', f'/users/{user_id}/sessions').get('sessions', [])

    def set_prefs(self, user_id, prefs):
        return self.call('PATCH', f'/users/{user_id}/prefs', body={'prefs': prefs})

    def delete_user(self, user_id):
        return self.call('DELETE', f'/users/{user_id}')

    # Rows ----------------------------------------------------------------------------------------
    def rows(self, table, queries=()):
        return self.list_all(f'/tablesdb/{DB}/tables/{table}/rows', 'rows', queries)

    def row(self, table, row_id):
        try:
            return self.call('GET', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}')
        except AppwriteError as e:
            if e.code == 404:
                return None
            raise

    def update_row(self, table, row_id, data):
        return self.call('PATCH', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}', body={'data': data})

    def delete_row(self, table, row_id):
        return self.call('DELETE', f'/tablesdb/{DB}/tables/{table}/rows/{row_id}')

    # Storage -------------------------------------------------------------------------------------
    def files(self, bucket):
        return self.list_all(f'/storage/buckets/{bucket}/files', 'files')

    def file_bytes(self, bucket, file_id):
        return self.call('GET', f'/storage/buckets/{bucket}/files/{file_id}/download', raw=True)

    def delete_file(self, bucket, file_id):
        return self.call('DELETE', f'/storage/buckets/{bucket}/files/{file_id}')
