import os, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[3]          # repo root
TOOLS = ROOT / 'tools' / 'content'
SPECS = TOOLS / 'specs'
REPORTS = TOOLS / 'reports'
STATE = TOOLS / 'state'
# Big derived data (image thumbnails, hashes, candidate pools) lives outside the repo.
CACHE = pathlib.Path(os.environ.get('CJW_CONTENT_CACHE') or
                     (pathlib.Path.home() / '.cache' / 'cjw-content'))
for d in (SPECS, REPORTS, STATE, CACHE, CACHE / 'thumbs', CACHE / 'meta', CACHE / 'pools', CACHE / 'sheets'):
    d.mkdir(parents=True, exist_ok=True)
SECRET_KEY = ROOT / 'secrets' / 'appwrite-api-key.txt'
