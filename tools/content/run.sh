#!/bin/zsh
# Wrapper: runs the content CLI with the right python and cache dir.
# Usage: tools/content/run.sh <command> [args]      (see cli.py for commands)
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/.local-env" ] && source "$DIR/.local-env"
export CJW_CONTENT_CACHE="${CJW_CONTENT_CACHE:-$HOME/.cache/cjw-content}"
PY="${CJW_PY:-python3}"
exec "$PY" "$DIR/cli.py" "$@"
