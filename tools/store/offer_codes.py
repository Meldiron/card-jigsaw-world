#!/usr/bin/env python3
"""Subscription offer codes (gift codes) for Card Jigsaw World VIP.

Apple's native mechanism: a subscription "offer code" (free, 1 month or 1 year)
plus custom codes attached to it. Each custom code gets a redemption limit of 1,
which makes it single-use, and no expiration date, so it stays valid until it is
redeemed or deactivated. One-time-use codes were not used because Apple requires
batches of at least 500, caps their validity at six months and only allows them
once the app is Ready for Sale.

Usage:
  offer_codes.py create-offers            create "VIP Monthly gift" and "VIP Yearly gift" (idempotent)
  offer_codes.py codes monthly 10         create 10 single-use codes for the monthly offer
  offer_codes.py codes yearly 10
  offer_codes.py list                     print offers and their codes
Options: --expires YYYY-MM-DD (max 6 months ahead; default none), --prefix XXXX
"""
import argparse, json, os, secrets, string, sys, time
import jwt, requests

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
API = "https://api.appstoreconnect.apple.com"
APP_ID = "6821644423"
KEY_ID = os.environ.get("ASC_KEY_ID", "9QC72A5QMN")
KEY_PATH = os.environ.get("ASC_KEY_PATH", os.path.join(ROOT, "secrets", f"AuthKey_{KEY_ID}.p8"))
ISSUER = os.environ.get("ASC_ISSUER_ID") or open(os.path.join(ROOT, "secrets", "app-store-connect-issuer-id.txt")).read().strip()
SUBS = {
    "monthly": {"id": "6821645754", "offer": "VIP Monthly gift", "duration": "ONE_MONTH", "prefix": "VIPM"},
    "yearly": {"id": "6821646642", "offer": "VIP Yearly gift", "duration": "ONE_YEAR", "prefix": "VIPY"},
}
CODES_FILE = os.path.join(ROOT, "secrets", "vip-offer-codes.json")


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(method, path, body=None, params=None):
    r = requests.request(method, API + path, json=body, params=params,
                         headers={"Authorization": "Bearer " + token()}, timeout=60)
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:600]}")
    return r.json() if r.content else {}


def offers_for(sub_id):
    return call("GET", f"/v1/subscriptions/{sub_id}/offerCodes", {"limit": 200}).get("data", [])


def ensure_offer(key):
    sub = SUBS[key]
    for o in offers_for(sub["id"]):
        if o["attributes"]["name"] == sub["offer"] and o["attributes"].get("active", True):
            print(f"offer '{sub['offer']}' exists ({o['id']})")
            return o
    # Apple requires one price entry per territory even for a free offer.
    territories = [t["id"] for t in call("GET", "/v1/territories", params={"limit": 200}).get("data", [])]
    included, refs = [], []
    for i, t in enumerate(territories):
        pid = f"${{price-{i}}}"
        included.append({"type": "subscriptionOfferCodePrices", "id": pid,
                         "relationships": {"territory": {"data": {"type": "territories", "id": t}}}})
        refs.append({"type": "subscriptionOfferCodePrices", "id": pid})
    body = {"data": {"type": "subscriptionOfferCodes", "attributes": {
        "name": sub["offer"], "customerEligibilities": ["NEW", "EXISTING", "EXPIRED"],
        "offerEligibility": "STACK_WITH_INTRO_OFFERS", "duration": sub["duration"],
        "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}},
                          "prices": {"data": refs}}},
        "included": included}
    o = call("POST", "/v1/subscriptionOfferCodes", body)["data"]
    print(f"created offer '{sub['offer']}' ({o['id']})")
    return o


def new_code(prefix):
    alphabet = string.ascii_uppercase + string.digits
    alphabet = "".join(c for c in alphabet if c not in "0O1I")
    return prefix + "".join(secrets.choice(alphabet) for _ in range(8))


def create_codes(key, count, expires=None, prefix=None):
    offer = ensure_offer(key)
    store = json.load(open(CODES_FILE)) if os.path.exists(CODES_FILE) else {}
    made = []
    for _ in range(count):
        code = new_code(prefix or SUBS[key]["prefix"])
        attrs = {"customCode": code, "numberOfCodes": 1}
        if expires:
            attrs["expirationDate"] = expires
        body = {"data": {"type": "subscriptionOfferCodeCustomCodes", "attributes": attrs,
                "relationships": {"offerCode": {"data": {"type": "subscriptionOfferCodes", "id": offer["id"]}}}}}
        r = call("POST", "/v1/subscriptionOfferCodeCustomCodes", body)["data"]
        made.append({"code": code, "id": r["id"], "created": r["attributes"].get("createdDate"),
                     "expires": r["attributes"].get("expirationDate"), "redeem_url": redeem_url(code)})
        print("created", code)
    store.setdefault(key, []).extend(made)
    os.makedirs(os.path.dirname(CODES_FILE), exist_ok=True)
    json.dump(store, open(CODES_FILE, "w"), indent=2)
    print(f"saved to {os.path.relpath(CODES_FILE, ROOT)}")


def redeem_url(code):
    return f"https://apps.apple.com/redeem?ctx=offercodes&id={APP_ID}&code={code}"


def list_all():
    for key, sub in SUBS.items():
        print(f"== {key} ({sub['id']})")
        for o in offers_for(sub["id"]):
            a = o["attributes"]
            print(f"  offer {a['name']} id={o['id']} mode={a.get('offerMode')} duration={a.get('duration')} active={a.get('active')}")
            codes = call("GET", f"/v1/subscriptionOfferCodes/{o['id']}/customCodes", {"limit": 200}).get("data", [])
            for c in codes:
                ca = c["attributes"]
                print(f"    {ca['customCode']}  limit={ca.get('numberOfCodes')} expires={ca.get('expirationDate') or 'never'} active={ca.get('active')}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd", required=True)
    sp.add_parser("create-offers")
    c = sp.add_parser("codes"); c.add_argument("plan", choices=SUBS); c.add_argument("count", type=int)
    c.add_argument("--expires"); c.add_argument("--prefix")
    sp.add_parser("list")
    a = p.parse_args()
    if a.cmd == "create-offers":
        for k in SUBS: ensure_offer(k)
    elif a.cmd == "codes":
        create_codes(a.plan, a.count, a.expires, a.prefix)
    else:
        list_all()
