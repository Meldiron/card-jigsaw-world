#!/usr/bin/env python3
"""Announce the newest iPhone build to the app's update prompt (lib/state/app_update.dart).

The iPhone app reads one row of the public `releases` table (database cjw) for the way it was
installed: `ios-testflight` (TestFlight, simulator and Xcode installs) or `ios-appstore` (App Store).
When that row names a higher build number than its own, it asks the player to update (every 5
minutes in front, at most once an hour, again after every launch). The web build needs none of
this: tools/dev/deploy-web.sh publishes app-version.json with each deploy.

  .venv/bin/python tools/dev/publish_release.py show
  .venv/bin/python tools/dev/publish_release.py testflight --build 121 [--version 1.7.0] [--no-wait]
      waits until Apple has build 121 out to the public testers, then writes ios-testflight
      (tools/dev/testflight.sh runs this after every build)
  .venv/bin/python tools/dev/publish_release.py appstore --version 1.7.0 [--build N]
      once a version is live on the App Store (tools/dev/tag-store-release.sh runs it)
  .venv/bin/python tools/dev/publish_release.py init
      prints the Appwrite CLI command that created the table (once, 2026-10-14)

A row never goes down: an older build than the one announced is refused.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "store"))

EP = "https://fra.cloud.appwrite.io/v1"
PROJECT = "6acb4de5003e38d5ebd9"
DB = "cjw"
TABLE = "releases"
ROWS = {"testflight": "ios-testflight", "appstore": "ios-appstore"}
# Apple has the build out to the public testers (internal testers get it at VALID already).
OUT_STATES = {"IN_BETA_TESTING", "BETA_APPROVED"}


def _key() -> str:
    return (ROOT / "secrets" / "appwrite-api-key.txt").read_text(encoding="utf-8").strip()


def _call(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(EP + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("X-Appwrite-Project", PROJECT)
    req.add_header("X-Appwrite-Key", _key())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path}: {e.code} {e.read().decode(errors='replace')}") from None


def _row(row_id: str) -> dict | None:
    try:
        return _call("GET", f"/tablesdb/{DB}/tables/{TABLE}/rows/{row_id}")
    except RuntimeError as e:
        if " 404 " in str(e):
            return None
        raise


INIT = (
    "appwrite tablesdb create-table --database-id cjw --table-id releases --name Releases "
    "--permissions 'read(\"any\")' "
    "--columns '{\"key\":\"version\",\"type\":\"varchar\",\"size\":32,\"required\":true}' "
    "--columns '{\"key\":\"build\",\"type\":\"integer\",\"required\":true,\"min\":0}' "
    "--columns '{\"key\":\"publishedAt\",\"type\":\"datetime\",\"required\":true}'"
)


def cmd_init() -> None:
    # The repo's API keys cannot create tables; the owner's Appwrite CLI session can (with an
    # appwrite.config.json naming the project, passed as --config-file).
    print("Create the table with the Appwrite CLI (signed in as the owner):\n  " + INIT)


def cmd_show() -> None:
    for row_id in ROWS.values():
        r = _row(row_id)
        print(f"{row_id}: " + (f"version {r.get('version')} build {r.get('build')} (published {r.get('publishedAt')})" if r else "none"))


def _publish(channel: str, version: str, build: int) -> None:
    row_id = ROWS[channel]
    current = _row(row_id)
    if current and int(current.get("build") or 0) > build:
        sys.exit(f"{row_id} already announces build {current.get('build')}; refusing to go back to {build}")
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    _call("PUT", f"/tablesdb/{DB}/tables/{TABLE}/rows/{row_id}", {"data": {"version": version, "build": build, "publishedAt": now}})
    print(f"{row_id}: version {version} build {build} announced; installs of older builds will be asked to update")


def _asc():
    from asc_publish import Client, Store  # noqa: E402  (needs pyjwt + requests: run with .venv/bin/python)
    return Store(Client(dry_run=False, verbose=False))


def _pubspec_version() -> str:
    for line in (ROOT / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+")[0]
    sys.exit("no version in pubspec.yaml")


def cmd_testflight(build: int, version: str | None, wait: bool, timeout_min: float) -> None:
    from asc_publish import attr
    version = version or _pubspec_version()
    if wait:
        s = _asc()
        deadline = time.time() + timeout_min * 60
        last = None
        while True:
            b = s.build_by_number(str(build))
            detail = s.c.get_one(f"/v1/builds/{b['id']}/buildBetaDetail") if b else None
            state = (attr(b, "processingState"), attr(detail, "externalBuildState") if detail else None)
            if state != last:
                print(f"build {build}: processing {state[0] or 'not visible'}, external testers {state[1] or '-'}")
                last = state
            if state[0] == "VALID" and state[1] in OUT_STATES:
                break
            if state[0] in ("INVALID", "FAILED"):
                sys.exit(f"build {build} is {state[0]}; nothing announced")
            if time.time() >= deadline:
                sys.exit(f"build {build} is not out to testers after {timeout_min:g} min; rerun this later (nothing announced)")
            time.sleep(30)
    _publish("testflight", version, build)


def cmd_appstore(version: str, build: int | None) -> None:
    from asc_publish import APP_ID, attr
    if build is None:
        s = _asc()
        versions = s.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[versionString]": version, "limit": 5}, limit=5)
        v = versions[0] if versions else None
        if not v:
            sys.exit(f"no App Store version {version}; pass --build")
        if attr(v, "appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION"):
            sys.exit(f"version {version} is {attr(v, 'appStoreState')}, not live; nothing announced")
        b = s.c.get_one(f"/v1/appStoreVersions/{v['id']}/build")
        if not b:
            sys.exit(f"version {version} has no build attached; pass --build")
        build = int(attr(b, "version"))
    _publish("appstore", version, build)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["show", "init", "testflight", "appstore"])
    p.add_argument("--build", type=int)
    p.add_argument("--version")
    p.add_argument("--no-wait", action="store_true", help="testflight: announce now, without waiting for Apple")
    p.add_argument("--timeout", type=float, default=60, metavar="MIN", help="testflight: minutes to wait (default 60)")
    a = p.parse_args()
    if a.command == "show":
        cmd_show()
    elif a.command == "init":
        cmd_init()
    elif a.command == "testflight":
        if a.build is None:
            p.error("testflight needs --build")
        cmd_testflight(a.build, a.version, not a.no_wait, a.timeout)
    else:
        if not a.version:
            p.error("appstore needs --version")
        cmd_appstore(a.version, a.build)
    return 0


if __name__ == "__main__":
    sys.exit(main())
