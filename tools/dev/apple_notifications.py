#!/usr/bin/env python3
"""App Store Server Notifications: ask Apple for a test notification and see what Apple sent.

    .venv/bin/python tools/dev/apple_notifications.py test [--production]
    .venv/bin/python tools/dev/apple_notifications.py history [--days N] [--production]

`test` asks Apple to send a TEST notification to the URL set in App Store Connect (Sandbox unless
--production), waits for Apple's delivery result, then reads the notification's row in the server-only
table `apple_notifications` (docs/functions.md): `result: test` and `via` (the function that took it)
mean it arrived and was verified. `history` lists every notification of the last N days (at most 180)
with Apple's delivery attempts (SUCCESS, TIMED_OUT, ...) and the row it left.

App Store Server API (api.storekit[-sandbox].itunes.apple.com). The App Store Connect key in
secrets/ (AuthKey_9QC72A5QMN.p8) is accepted for Sandbox; Production answers 401 with it and needs an
In-App Purchase key (App Store Connect > Users and Access > Integrations > In-App Purchase): save it as
secrets/SubscriptionKey_<KEY ID>.p8 and run with ASN_KEY_ID=<KEY ID>. Key values are never printed.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

import jwt  # pyjwt
import requests

ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ID = "com.matejbaco.cardjigsawworld"
KEY_ID = os.environ.get("ASN_KEY_ID", "").strip() or "9QC72A5QMN"
KEY_PATH = next((p for p in (ROOT / "secrets" / f"SubscriptionKey_{KEY_ID}.p8", ROOT / "secrets" / f"AuthKey_{KEY_ID}.p8") if p.exists()), None)
ISSUER = (ROOT / "secrets" / "app-store-connect-issuer-id.txt").read_text().strip()
APPWRITE = "https://fra.cloud.appwrite.io/v1"
PROJECT = "6acb4de5003e38d5ebd9"
HOSTS = {False: "https://api.storekit-sandbox.itunes.apple.com", True: "https://api.storekit.itunes.apple.com"}


def token() -> str:
    if KEY_PATH is None:
        sys.exit(f"no key secrets/SubscriptionKey_{KEY_ID}.p8 or secrets/AuthKey_{KEY_ID}.p8")
    now = int(time.time())
    claims = {"iss": ISSUER, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1", "bid": BUNDLE_ID}
    return jwt.encode(claims, KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def apple(method: str, path: str, production: bool, body: dict | None = None) -> dict:
    r = requests.request(method, HOSTS[production] + path, headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
                         data=json.dumps(body) if body is not None else None, timeout=30)
    if r.status_code >= 300:
        hint = " (this key is not accepted here; see the In-App Purchase key in the docstring)" if r.status_code == 401 else ""
        sys.exit(f"{method} {path}: {r.status_code} {r.text[:200]}{hint}")
    return r.json() if r.text else {}


def claims_of(jws: str) -> dict:
    """The payload of a JWS, unverified (Apple signed it; the functions verify it)."""
    part = jws.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))


def record(uuid: str | None) -> dict | None:
    """The notification's row in apple_notifications, or None."""
    if not uuid:
        return None
    key = (ROOT / "secrets" / "appwrite-api-key.txt").read_text().strip()
    r = requests.get(f"{APPWRITE}/tablesdb/cjw/tables/apple_notifications/rows/{uuid}",
                     headers={"X-Appwrite-Project": PROJECT, "X-Appwrite-Key": key}, timeout=30)
    return r.json() if r.status_code == 200 else None


def describe(row: dict | None) -> str:
    if not row:
        return "no row"
    return f"row: {row.get('result')} via {row.get('via')}" + (f", {row.get('profiles')} profile(s)" if row.get("profiles") else "")


def cmd_test(production: bool) -> int:
    env = "Production" if production else "Sandbox"
    t = apple("POST", "/inApps/v1/notifications/test", production)["testNotificationToken"]
    print(f"{env}: Apple is sending a TEST notification")
    for _ in range(30):
        time.sleep(4)
        status = apple("GET", f"/inApps/v1/notifications/test/{t}", production)
        attempts = status.get("sendAttempts") or []
        if attempts:
            uuid = claims_of(status["signedPayload"]).get("notificationUUID")
            results = [a.get("sendAttemptResult") for a in attempts]
            print(f"  {uuid}: delivery {', '.join(results)}")
            time.sleep(2)
            row = record(uuid)
            print(f"  {describe(row)}")
            return 0 if results[-1] == "SUCCESS" and row and row.get("result") == "test" else 1
    print("  no delivery attempt after 2 minutes")
    return 1


def cmd_history(days: int, production: bool) -> int:
    now = int(time.time() * 1000)
    body = {"startDate": now - min(days, 180) * 86400000, "endDate": now}
    items, page = [], None
    while True:
        d = apple("POST", "/inApps/v1/notifications/history" + (f"?paginationToken={page}" if page else ""), production, body)
        items += d.get("notificationHistory") or []
        if not d.get("hasMore"):
            break
        page = d.get("paginationToken")
    for it in items:
        c = claims_of(it["signedPayload"])
        tx = claims_of(c["data"]["signedTransactionInfo"]) if (c.get("data") or {}).get("signedTransactionInfo") else {}
        when = time.strftime("%Y-%m-%d %H:%M", time.gmtime(c.get("signedDate", 0) / 1000))
        attempts = ", ".join(a.get("sendAttemptResult", "?") for a in it.get("sendAttempts") or [])
        print(f"{when}  {c.get('notificationType')} {c.get('subtype') or ''}  {tx.get('productId', '')}  {c.get('notificationUUID')}  delivery {attempts or '-'}  {describe(record(c.get('notificationUUID')))}")
    print(f"{len(items)} notification(s) in {days} days ({'Production' if production else 'Sandbox'})")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["test", "history"])
    p.add_argument("--production", action="store_true", help="Production instead of Sandbox")
    p.add_argument("--days", type=int, default=30)
    a = p.parse_args()
    return cmd_test(a.production) if a.command == "test" else cmd_history(a.days, a.production)


if __name__ == "__main__":
    sys.exit(main())
