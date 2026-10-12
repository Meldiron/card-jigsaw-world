"""Cross-process file lock so several workers can share the state files safely."""
import fcntl, contextlib
from .paths import CACHE

@contextlib.contextmanager
def locked(name):
    p = CACHE / f'.{name}.lock'
    with p.open('w') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
