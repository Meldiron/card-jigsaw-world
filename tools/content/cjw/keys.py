"""API keys for optional picture sources.

Keys live in secrets/content-keys.env (git-ignored): KEY=VALUE lines, '#' comments, empty values mean
"not configured". An environment variable of the same name overrides the file. Never print values.
"""
import os
from .paths import ROOT

KEYS_FILE = ROOT / 'secrets' / 'content-keys.env'
_cache = None

def _load():
    global _cache
    if _cache is None:
        out = {}
        try:
            text = KEYS_FILE.read_text()
        except OSError:
            text = ''
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line: continue
            k, v = line.split('=', 1)
            k = k.strip().removeprefix('export ').strip()
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
                v = v[1:-1].strip()
            if k and v:
                out[k] = v
        _cache = out
    return _cache

def get(name):
    """The key's value, or None when it is not configured."""
    v = (os.environ.get(name) or '').strip()
    return v or _load().get(name)

def has(name):
    return bool(get(name))
