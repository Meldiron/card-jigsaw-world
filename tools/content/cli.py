#!/usr/bin/env python
"""Card Jigsaw World content CLI. Run with the venv python that has Pillow, numpy, requests.

  cli.py dump                         snapshot the live catalogue into the cache
  cli.py scan [--pack ID] [--all]     download + hash + measure images of catalogue puzzles
  cli.py audit [--pack ID]            report rule violations per pack (writes reports/audit-<date>.md)
  cli.py pool PACK [--topics N]       source candidates for a pack from its spec
  cli.py sheet PACK [--candidates]    contact sheet PNG(s) for visual review
  cli.py reject PACK ID... --reason R persist rejections (puzzle ids or candidate keys)
  cli.py apply PACK [--target N]      remove rejected puzzles, add candidates, write blurhash/accent
  cli.py newpack SPEC                 create a pack row from a spec (idempotent)
  cli.py status PACK                  one-line state of a pack
  cli.py verify PACK...               audit the packs; clean ones become 'verified' in reports/state.json
  cli.py resume [--prefix P] [--auto] durable board + next packs to work on (--auto builds missing pools)
  cli.py checkpoint [-m MSG]          git commit + push of tools/content, the skill and the content docs only
  cli.py clone SRC DST                copy all puzzles of SRC into DST (same world day, other year)
  cli.py recover [POOL...]            re-fetch candidates lost to HTTP 429 throttling
  cli.py summary [-v]                 totals from reports/changes.jsonl
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cjw import commands
if __name__ == '__main__':
    commands.main(sys.argv[1:])
