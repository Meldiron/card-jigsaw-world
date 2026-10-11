#!/usr/bin/env python3
"""App Store Connect publisher for Card Jigsaw World.

Idempotent: every subcommand looks up what already exists and creates or
updates only what differs, so it is safe to run again after a partial failure.

    asc_publish.py all --dry-run          # print every request, send nothing
    asc_publish.py status                 # what exists in App Store Connect
    asc_publish.py audit                  # submission checklist, no writes

Reads metadata from store/metadata (see tools/store/README.md). Credentials:
the team API key secrets/AuthKey_9QC72A5QMN.p8 and the Issuer ID from the
environment variable ASC_ISSUER_ID or secrets/app-store-connect-issuer-id.txt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Callable, Iterable

try:
    import jwt  # pyjwt
    import requests
except ImportError as exc:  # pragma: no cover
    sys.exit(f"missing dependency: {exc}. Install pyjwt, cryptography and requests.")

# ---------------------------------------------------------------------------
# Fixed facts
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]
META = ROOT / "store" / "metadata"
EN = META / "en-US"
SUBS_DIR = META / "subscriptions"
SCREENSHOT_DIR = ROOT / "store" / "screenshots" / "iphone-6.9"

APP_ID = "6821644423"
BUNDLE_ID = "com.matejbaco.cardjigsawworld"
KEY_ID = "9QC72A5QMN"
KEY_PATH = ROOT / "secrets" / f"AuthKey_{KEY_ID}.p8"
ISSUER_FILE = ROOT / "secrets" / "app-store-connect-issuer-id.txt"
VERSION_STRING = "1.7.0"
PLATFORM = "IOS"
LOCALE = "en-US"  # replaced at startup by the app's primaryLocale (en-GB for this app); metadata stays in store/metadata/en-US
BASE_TERRITORY = "USA"
SCREENSHOT_TYPE = "APP_IPHONE_67"
BETA_GROUP_NAME = "Public testers"
NOTIFICATIONS_URL = "https://cjw-verify-purchase.fra.appwrite.run/notifications"  # verify-purchase Appwrite Function
EDITABLE_VERSION_STATES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")

API = "https://api.appstoreconnect.apple.com"

ALL_ORDER = [
    "app-info",
    "version",
    "age-rating",
    "price-free",
    "screenshots",
    "iap",
    "subscriptions",
    "review-info",
    "testflight",
]

# Limits App Store Connect enforces; checked before anything is sent.
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "description": 4000,
    "keywords": 100,
    "release_notes": 4000,
    "iap_name": 30,
    "iap_description": 45,
}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def read_text(name: str, required: bool = True) -> str:
    path = EN / name
    if not path.exists():
        if required:
            sys.exit(f"missing metadata file: {path}")
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_json(path: Path) -> dict:
    if not path.exists():
        sys.exit(f"missing metadata file: {path}")
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    return {k: v for k, v in data.items() if not k.startswith("_")}


def is_placeholder(value: Any) -> bool:
    return not isinstance(value, str) or not value or value.startswith("[")


def check_limit(field: str, value: str) -> None:
    limit = LIMITS.get(field)
    if limit and len(value) > limit:
        sys.exit(f"{field} is {len(value)} characters; App Store Connect allows {limit}")


def md5_of(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def same_price(a: Any, b: Any) -> bool:
    try:
        return abs(float(a) - float(b)) < 0.0005
    except (TypeError, ValueError):
        return False


def log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# API client
# ---------------------------------------------------------------------------


class ApiError(RuntimeError):
    def __init__(self, status: int, errors: list[dict], method: str, url: str):
        self.status = status
        self.errors = errors
        super().__init__(f"{method} {url} -> {status}: " + "; ".join(
            f"{e.get('code', '')} {e.get('title', '')}: {e.get('detail', '')}" for e in errors) or str(status))

    def mentions(self, *words: str) -> bool:
        text = json.dumps(self.errors).lower()
        return any(w.lower() in text for w in words)

    @property
    def already_exists(self) -> bool:
        return self.status == 409 and self.mentions("already exists", "already been", "duplicate", "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE")


class Client:
    """Thin JSON:API client with JWT auth, pagination and a dry-run mode."""

    def __init__(self, dry_run: bool, verbose: bool):
        self.dry_run = dry_run
        self.verbose = verbose
        self.session = requests.Session()
        self._token: str | None = None
        self._token_exp = 0.0
        self._dry_counter = 0
        self.issuer_id = self._load_issuer()
        if not dry_run and not KEY_PATH.exists():
            sys.exit(f"private key not found: {KEY_PATH}")

    # -- auth ---------------------------------------------------------------

    @staticmethod
    def _load_issuer() -> str:
        issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
        if not issuer and ISSUER_FILE.exists():
            issuer = ISSUER_FILE.read_text(encoding="utf-8").strip()
        if not issuer:
            sys.exit(
                "App Store Connect Issuer ID is missing.\n"
                "Find it in App Store Connect > Users and Access > Integrations > App Store Connect API\n"
                "(\"Issuer ID\" at the top of the page), then either\n"
                "  export ASC_ISSUER_ID=<issuer id>\n"
                f"or write it to {ISSUER_FILE.relative_to(ROOT)}"
            )
        return issuer

    def token(self) -> str:
        now = time.time()
        if self._token and now < self._token_exp - 60:
            return self._token
        if self.dry_run and not KEY_PATH.exists():
            self._token, self._token_exp = "dry-run-token", now + 1200
            return self._token
        key = KEY_PATH.read_text(encoding="utf-8")
        payload = {"iss": self.issuer_id, "iat": int(now), "exp": int(now) + 19 * 60, "aud": "appstoreconnect-v1"}
        self._token = jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
        self._token_exp = now + 19 * 60
        return self._token

    # -- core request -------------------------------------------------------

    def request(self, method: str, path: str, body: dict | None = None, params: dict | None = None,
                raw: bytes | None = None, headers: dict | None = None, allow_404: bool = False) -> dict | None:
        url = path if path.startswith("http") else API + path
        if self.dry_run and method != "GET":
            self._dry_counter += 1
            log(f"[dry-run] {method} {url}" + (f" params={json.dumps(params)}" if params else ""))
            if body is not None:
                log("          " + json.dumps(body, indent=2).replace("\n", "\n          "))
            if raw is not None:
                log(f"          <{len(raw)} bytes>")
            return self._dry_response(method, path, body)
        if self.dry_run and method == "GET":
            if self.verbose:
                log(f"[dry-run] GET {url}" + (f" params={json.dumps(params)}" if params else ""))
            return self._dry_get(path, params)

        # Asset upload operations go to presigned object-storage URLs, which
        # reject requests that also carry an Authorization header.
        hdrs = {} if (path.startswith("http") and not path.startswith(API)) else {"Authorization": f"Bearer {self.token()}"}
        if headers:
            hdrs.update(headers)
        if self.verbose:
            log(f"{method} {url}" + (f" params={json.dumps(params)}" if params else ""))
            if body is not None:
                log("  " + json.dumps(body))
        for attempt in range(5):
            resp = self.session.request(method, url, json=body, params=params, data=raw, headers=hdrs, timeout=120)
            if resp.status_code == 429 or resp.status_code >= 500:
                wait = 2 ** attempt
                log(f"  {resp.status_code} from Apple, retrying in {wait}s")
                time.sleep(wait)
                continue
            break
        if resp.status_code == 404 and allow_404:
            return None
        if resp.status_code >= 400:
            try:
                errors = resp.json().get("errors", [])
            except ValueError:
                errors = [{"title": resp.text[:300]}]
            raise ApiError(resp.status_code, errors, method, url)
        if resp.status_code == 204 or not resp.content:
            return {}
        return resp.json()

    # -- dry-run stand-ins --------------------------------------------------

    def _dry_response(self, method: str, path: str, body: dict | None) -> dict:
        if body and isinstance(body.get("data"), dict):
            data = dict(body["data"])
            data.setdefault("id", f"DRY-{data.get('type', 'resource')}-{self._dry_counter}")
            return {"data": data}
        return {"data": None}

    def _dry_get(self, path: str, params: dict | None) -> dict:
        """Synthetic empty answers so every flow takes its 'create' branch and
        the printed requests show the full shape. Territories and
        equalizations return a short list so per-territory requests show up."""
        p = path.split("?")[0]
        if p.endswith("/territories"):
            return self._dry_list([self._territory(t) for t in ("USA", "GBR", "DEU")])
        if p.endswith("/equalizations"):
            return self._dry_list([
                {"id": f"DRY-pricePoint-{t}", "type": "pricePoints", "attributes": {"customerPrice": "?"},
                 "relationships": {"territory": {"data": {"type": "territories", "id": t}}}}
                for t in ("GBR", "DEU")
            ])
        if p.endswith("/appCategories"):
            return self._dry_list([])
        if p.endswith("/v1/builds"):
            return self._dry_list([{"id": "DRY-build", "type": "builds",
                                    "attributes": {"version": "0", "processingState": "VALID", "uploadedDate": "dry-run",
                                                   "usesNonExemptEncryption": None}}])
        # Single resources answered by to-one relationship endpoints.
        single = ("ageRatingDeclaration", "appStoreReviewDetail", "appPriceSchedule", "appAvailabilityV2",
                  "iapPriceSchedule", "inAppPurchaseAvailability", "appStoreReviewScreenshot",
                  "subscriptionAvailability", "betaAppReviewDetail", "betaLicenseAgreement")
        if p.rsplit("/", 1)[-1] in single:
            return {"data": None}
        return self._dry_list([])

    @staticmethod
    def _territory(code: str) -> dict:
        return {"id": code, "type": "territories", "attributes": {"currency": "USD"}}

    @staticmethod
    def _dry_list(items: list) -> dict:
        return {"data": items, "links": {}}

    # -- convenience --------------------------------------------------------

    def get_list(self, path: str, params: dict | None = None, limit: int = 200) -> list[dict]:
        """GET a collection, following `links.next` until exhausted."""
        params = dict(params or {})
        params.setdefault("limit", limit)
        out: list[dict] = []
        resp = self.request("GET", path, params=params)
        while resp is not None:
            out.extend(resp.get("data") or [])
            nxt = (resp.get("links") or {}).get("next")
            if not nxt:
                break
            resp = self.request("GET", nxt)
        return out

    def get_one(self, path: str, params: dict | None = None) -> dict | None:
        resp = self.request("GET", path, params=params, allow_404=True)
        if not resp:
            return None
        data = resp.get("data")
        return data if isinstance(data, dict) else None

    def create(self, type_: str, attributes: dict | None = None, relationships: dict | None = None,
               included: list | None = None, path: str | None = None) -> dict:
        data: dict[str, Any] = {"type": type_}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        body: dict[str, Any] = {"data": data}
        if included:
            body["included"] = included
        resp = self.request("POST", path or f"/v1/{type_}", body)
        return (resp or {}).get("data") or {}

    def update(self, type_: str, id_: str, attributes: dict | None = None, relationships: dict | None = None,
               path: str | None = None) -> dict:
        data: dict[str, Any] = {"type": type_, "id": id_}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        resp = self.request("PATCH", path or f"/v1/{type_}/{id_}", {"data": data})
        return (resp or {}).get("data") or {}

    def upsert(self, type_: str, existing: dict | None, attributes: dict, relationships: dict | None = None,
               create_path: str | None = None, patch_path: str | None = None, label: str = "",
               refetch: Callable[[], dict | None] | None = None) -> dict:
        """Create when `existing` is None, else PATCH only the attributes that differ.
        A 409 'already exists' on create is retried as a PATCH after `refetch`
        (or a GET of the create path) finds the resource."""
        label = label or type_
        if existing:
            current = existing.get("attributes") or {}
            diff = {k: v for k, v in attributes.items() if current.get(k) != v}
            if not diff:
                log(f"  {label}: up to date")
                return existing
            log(f"  {label}: updating {', '.join(sorted(diff))}")
            return self.update(type_, existing["id"], diff, path=patch_path)
        log(f"  {label}: creating")
        try:
            return self.create(type_, attributes, relationships, path=create_path)
        except ApiError as err:
            if not err.already_exists or refetch is None:
                raise
            log(f"  {label}: Apple says it already exists (409); refetching and updating instead")
            found = refetch()
            if found is None:
                raise
            attrs = {k: v for k, v in attributes.items() if k != "locale"}
            return self.upsert(type_, found, attrs, patch_path=patch_path, label=label)


# ---------------------------------------------------------------------------
# Shared lookups
# ---------------------------------------------------------------------------


def localized(cfg: dict) -> dict:
    """The localization block for the app's primary locale, falling back to en-US text."""
    locs = cfg["localizations"]
    return locs.get(LOCALE) or locs["en-US"]


def rel(type_: str, id_: str) -> dict:
    return {"data": {"type": type_, "id": id_}}


def rel_many(type_: str, ids: Iterable[str]) -> dict:
    return {"data": [{"type": type_, "id": i} for i in ids]}


def attr(res: dict | None, key: str, default: Any = None) -> Any:
    return ((res or {}).get("attributes") or {}).get(key, default)


def territory_of(res: dict) -> str | None:
    return (((res.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")


class Store:
    """Everything the subcommands share: client, cached lookups and metadata."""

    def __init__(self, client: Client):
        self.c = client
        self._cache: dict[str, Any] = {}

    def cached(self, key: str, fn: Callable[[], Any]) -> Any:
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    # -- app level ----------------------------------------------------------

    def app(self) -> dict | None:
        return self.cached("app", lambda: self.c.get_one(f"/v1/apps/{APP_ID}"))

    def app_info(self) -> dict:
        def find() -> dict:
            infos = self.c.get_list(f"/v1/apps/{APP_ID}/appInfos")
            editable = [i for i in infos if attr(i, "state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "WAITING_FOR_REVIEW", "READY_FOR_REVIEW")]
            chosen = (editable or infos or [None])[-1]
            if chosen is None:
                if self.c.dry_run:
                    return {"id": "DRY-appInfo", "type": "appInfos", "attributes": {}}
                sys.exit("the app has no appInfos record; create the app in App Store Connect first")
            return chosen
        return self.cached("appInfo", find)

    def territories(self) -> list[str]:
        return self.cached("territories", lambda: [t["id"] for t in self.c.get_list("/v1/territories")])

    def version(self, create: bool = False) -> dict | None:
        def find() -> dict | None:
            found = self.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions",
                                    {"filter[versionString]": VERSION_STRING, "filter[platform]": PLATFORM})
            return found[0] if found else None
        version = self.cached("version", find)
        if version is None and create:
            # Only one editable version can exist per platform. If there is one
            # (for example the "1.0" App Store Connect creates with the app), rename it.
            editable = [v for v in self.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": PLATFORM})
                        if (attr(v, "appVersionState") or attr(v, "appStoreState")) in EDITABLE_VERSION_STATES]
            if editable:
                old = editable[0]
                log(f"  appStoreVersion {attr(old, 'versionString')} ({attr(old, 'appVersionState')}): renaming to {VERSION_STRING}")
                version = self.c.update("appStoreVersions", old["id"], {"versionString": VERSION_STRING})
                if not version.get("attributes"):
                    version = {**old, "attributes": {**(old.get("attributes") or {}), "versionString": VERSION_STRING}}
            else:
                log(f"  appStoreVersion {VERSION_STRING}: creating")
                version = self.c.create("appStoreVersions",
                                        {"platform": PLATFORM, "versionString": VERSION_STRING, "copyright": read_text("copyright.txt")},
                                        {"app": rel("apps", APP_ID)})
            self._cache["version"] = version
        return version

    def version_localization(self, version: dict, create: bool = False) -> dict | None:
        key = f"vloc-{version['id']}"
        def find() -> dict | None:
            found = self.c.get_list(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", {"filter[locale]": LOCALE})
            return found[0] if found else None
        loc = self.cached(key, find)
        if loc is None and create:
            log(f"  appStoreVersionLocalization {LOCALE}: creating")
            loc = self.c.create("appStoreVersionLocalizations", {"locale": LOCALE}, {"appStoreVersion": rel("appStoreVersions", version["id"])})
            self._cache[key] = loc
        return loc

    def latest_build(self) -> dict | None:
        def find() -> dict | None:
            builds = self.c.get_list("/v1/builds", {"filter[app]": APP_ID, "sort": "-uploadedDate", "limit": 5}, limit=5)
            return builds[0] if builds else None
        return self.cached("build", find)

    # -- uploads ------------------------------------------------------------

    def upload_asset(self, type_: str, parent_rel: dict, path: Path, existing: list[dict] | None = None,
                     patch_path: str | None = None) -> dict | None:
        """Reserve, upload, commit. Returns None when an asset with the same file
        name is already there (idempotent by file name)."""
        if not path.exists():
            log(f"  {type_}: {path.relative_to(ROOT)} not found, skipping")
            return None
        for res in existing or []:
            if attr(res, "fileName") == path.name:
                state = ((attr(res, "assetDeliveryState") or {}).get("state")) or "present"
                if state in ("AWAITING_UPLOAD", "FAILED"):
                    # A reservation from an interrupted upload; drop it and start over.
                    log(f"  {type_}: {path.name} stale ({state}), deleting and re-uploading")
                    self.c.request("DELETE", f"/v1/{type_}/{res['id']}")
                    continue
                log(f"  {type_}: {path.name} already uploaded ({state})")
                return res
        size = path.stat().st_size
        log(f"  {type_}: uploading {path.relative_to(ROOT)} ({size} bytes)")
        try:
            reserved = self.c.create(type_, {"fileName": path.name, "fileSize": size}, parent_rel)
        except ApiError as e:
            if e.status == 409:
                # Apple keeps one asset of this kind; it is already there (possibly still processing).
                log(f"  {type_}: already present on Apple's side, keeping it")
                return None
            raise
        ops = attr(reserved, "uploadOperations") or []
        data = path.read_bytes()
        if not ops and self.c.dry_run:
            ops = [{"method": "PUT", "url": f"https://upload.example/{type_}/{path.name}", "offset": 0, "length": size, "requestHeaders": []}]
        for op in ops:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            self.c.request(op.get("method", "PUT"), op["url"], raw=chunk, headers=headers)
        return self.c.update(type_, reserved["id"], {"uploaded": True, "sourceFileChecksum": md5_of(path)}, path=patch_path)

    def describe_price_schedule(self, schedule: dict) -> str:
        resp = self.c.request("GET", f"/v1/appPriceSchedules/{schedule['id']}/manualPrices",
                              params={"include": "appPricePoint,territory", "limit": 200}, allow_404=True) or {}
        points = {i["id"]: attr(i, "customerPrice") for i in resp.get("included") or [] if i.get("type") == "appPricePoints"}
        parts = []
        for price in resp.get("data") or []:
            pp = (((price.get("relationships") or {}).get("appPricePoint") or {}).get("data") or {}).get("id")
            parts.append(f"{territory_of(price)}={points.get(pp, '?')}")
        return ", ".join(parts) or "no manual prices"

    # -- prices -------------------------------------------------------------

    def price_point(self, list_path: str, price: str, label: str) -> dict:
        points = self.c.get_list(list_path, {"filter[territory]": BASE_TERRITORY, "include": "territory"})
        for p in points:
            if same_price(attr(p, "customerPrice"), price):
                return p
        if self.c.dry_run:
            return {"id": f"DRY-pricePoint-USD-{price}", "type": "pricePoints", "attributes": {"customerPrice": price}}
        offered = sorted({attr(p, "customerPrice") for p in points}, key=float)
        sys.exit(f"{label}: no {BASE_TERRITORY} price point for {price}. Available: {', '.join(offered)}")

    def equalized(self, eq_path: str, base_point: dict, extra_params: dict | None = None) -> dict[str, str]:
        """territory code -> price point id, including the base territory."""
        out = {BASE_TERRITORY: base_point["id"]}
        params = {"include": "territory"}
        params.update(extra_params or {})
        for p in self.c.get_list(eq_path, params):
            t = territory_of(p)
            if t:
                out.setdefault(t, p["id"])
        return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_app_info(s: Store) -> None:
    log("== app-info")
    app = s.app() or {"id": APP_ID, "attributes": {}}
    app_attrs = {
        "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT",  # licensed photos and museum images
        "subscriptionStatusUrl": NOTIFICATIONS_URL,
        "subscriptionStatusUrlVersion": "V2",
        "subscriptionStatusUrlForSandbox": NOTIFICATIONS_URL,
        "subscriptionStatusUrlVersionForSandbox": "V2",
    }
    s.c.upsert("apps", app, app_attrs, label="app (content rights, App Store Server Notification URLs)")
    info = s.app_info()
    cats = read_json(EN / "categories.json")
    rels = {k: rel("appCategories", v) for k, v in cats.items() if v}
    current = info.get("relationships") or {}
    changed = {k: v for k, v in rels.items() if ((current.get(k) or {}).get("data") or {}).get("id") != v["data"]["id"]}
    if changed or s.c.dry_run or not current:
        log(f"  appInfo {info['id']}: setting categories {', '.join(f'{k}={v}' for k, v in cats.items())}")
        s.c.update("appInfos", info["id"], relationships=rels)
    else:
        log("  categories: up to date")

    name, subtitle = read_text("name.txt"), read_text("subtitle.txt")
    check_limit("name", name)
    check_limit("subtitle", subtitle)
    attrs = {"name": name, "subtitle": subtitle, "privacyPolicyUrl": read_text("privacy_url.txt")}
    locs = s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"filter[locale]": LOCALE})
    s.c.upsert("appInfoLocalizations", locs[0] if locs else None, {**attrs, "locale": LOCALE} if not locs else attrs,
               {"appInfo": rel("appInfos", info["id"])}, label=f"appInfoLocalization {LOCALE}",
               refetch=lambda: next(iter(s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"filter[locale]": LOCALE})), None))


def version_localization_attrs() -> dict:
    fields = {
        "description": read_text("description.txt"),
        "keywords": read_text("keywords.txt"),
        "promotionalText": read_text("promotional_text.txt"),
        "supportUrl": read_text("support_url.txt"),
        "marketingUrl": read_text("marketing_url.txt"),
        "whatsNew": read_text("release_notes.txt"),
    }
    check_limit("description", fields["description"])
    check_limit("keywords", fields["keywords"])
    check_limit("promotional_text", fields["promotionalText"])
    check_limit("release_notes", fields["whatsNew"])
    name_words = {w.lower() for w in re.findall(r"[a-z]+", read_text("name.txt"), re.I)}
    clash = [k for k in fields["keywords"].split(",") if k.lower() in name_words]
    if clash:
        sys.exit(f"keywords repeat words from the app name: {', '.join(clash)}")
    if ", " in fields["keywords"]:
        sys.exit("keywords.txt: remove the space after commas")
    return fields


def cmd_version(s: Store) -> None:
    log("== version")
    version = s.version(create=True)
    assert version
    copyright_ = read_text("copyright.txt")
    if attr(version, "copyright") != copyright_:
        log(f"  appStoreVersion {version['id']}: setting copyright")
        s.c.update("appStoreVersions", version["id"], {"copyright": copyright_})
    else:
        log("  copyright: up to date")
    loc = s.version_localization(version, create=True)
    assert loc
    fields = version_localization_attrs()
    try:
        s.c.upsert("appStoreVersionLocalizations", loc, fields, label=f"appStoreVersionLocalization {LOCALE}")
    except ApiError as err:
        if err.mentions("whatsNew", "what's new"):
            log("  Apple rejected whatsNew (first version of the app); retrying without it")
            fields.pop("whatsNew")
            s.c.upsert("appStoreVersionLocalizations", loc, fields, label=f"appStoreVersionLocalization {LOCALE}")
        else:
            raise


def cmd_age_rating(s: Store) -> None:
    log("== age-rating")
    info = s.app_info()
    decl = s.c.get_one(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    wanted = read_json(EN / "age_rating.json")
    if decl is None:
        if not s.c.dry_run:
            sys.exit("no ageRatingDeclaration on the appInfo; open the app in App Store Connect once so it is created")
        decl = {"id": "DRY-ageRatingDeclaration", "attributes": {}}
    s.c.upsert("ageRatingDeclarations", decl, wanted, label="ageRatingDeclaration")


def cmd_price_free(s: Store) -> None:
    log("== price-free")
    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    described = s.describe_price_schedule(schedule) if schedule and not s.c.dry_run else ""
    if schedule and described and described != "no manual prices":
        log(f"  appPriceSchedule exists: {described}; leaving it (change it in App Store Connect > Pricing to reset)")
    else:
        # App Store Connect creates an empty placeholder schedule (no manual prices) with the app record.
        point = s.price_point(f"/v1/apps/{APP_ID}/appPricePoints", "0", "app price")
        log(f"  appPriceSchedule: creating, free in {BASE_TERRITORY} (price point {point['id']}), other territories equalised by Apple")
        s.c.create(
            "appPriceSchedules",
            relationships={
                "app": rel("apps", APP_ID),
                "baseTerritory": rel("territories", BASE_TERRITORY),
                "manualPrices": rel_many("appPrices", ["${price-free}"]),
            },
            included=[{
                "type": "appPrices",
                "id": "${price-free}",
                "attributes": {"startDate": None},
                "relationships": {"appPricePoint": rel("appPricePoints", point["id"])},
            }],
        )

    territories = s.territories()
    availability = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    have = set()
    if availability:
        have = {territory_of(t) for t in s.c.get_list(f"/v2/appAvailabilities/{availability['id']}/territoryAvailabilities", {"include": "territory"})
                if attr(t, "available")}
    missing = [t for t in territories if t not in have]
    if availability and not missing and attr(availability, "availableInNewTerritories"):
        log(f"  availability: all {len(territories)} territories, up to date")
        return
    log(f"  appAvailabilityV2: creating with {len(territories)} territories ({len(missing)} newly available)")
    s.c.create(
        "appAvailabilities",
        {"availableInNewTerritories": True},
        {"app": rel("apps", APP_ID), "territoryAvailabilities": rel_many("territoryAvailabilities", [f"${{{t}}}" for t in territories])},
        included=[{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                   "relationships": {"territory": rel("territories", t)}} for t in territories],
        path="/v2/appAvailabilities",
    )


def cmd_screenshots(s: Store) -> None:
    log("== screenshots")
    files = sorted(SCREENSHOT_DIR.glob("*.png"))
    if not files:
        log(f"  no PNGs in {SCREENSHOT_DIR.relative_to(ROOT)}; run tools/store/compose_screenshots.py first")
        return
    version = s.version(create=True)
    loc = s.version_localization(version, create=True)
    sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets", {"filter[screenshotDisplayType]": SCREENSHOT_TYPE})
    if sets:
        sset = sets[0]
        log(f"  appScreenshotSet {SCREENSHOT_TYPE}: exists")
    else:
        log(f"  appScreenshotSet {SCREENSHOT_TYPE}: creating")
        sset = s.c.create("appScreenshotSets", {"screenshotDisplayType": SCREENSHOT_TYPE},
                          {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", loc["id"])})
    existing = s.c.get_list(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
    uploaded: list[str] = []
    for png in files:
        res = s.upload_asset("appScreenshots", {"appScreenshotSet": rel("appScreenshotSets", sset["id"])}, png, existing)
        if res:
            uploaded.append(res["id"])
    # Keep the App Store order equal to the file order.
    current_order = [e["id"] for e in existing]
    if uploaded and uploaded != current_order:
        log("  appScreenshotSet: setting order")
        s.c.request("PATCH", f"/v1/appScreenshotSets/{sset['id']}/relationships/appScreenshots", rel_many("appScreenshots", uploaded))


def cmd_iap(s: Store) -> None:
    log("== iap")
    cfg = read_json(SUBS_DIR / "consumables.json")
    review_png = ROOT / cfg["reviewScreenshot"] if cfg.get("reviewScreenshot") else None
    existing = {attr(p, "productId"): p for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2")}
    for product in cfg["products"]:
        pid = product["productId"]
        check_limit("iap_name", product["name"])
        check_limit("iap_description", product["description"])
        iap = existing.get(pid)
        attrs = {"name": product["referenceName"], "reviewNote": product["reviewNote"]}
        if iap is None:
            log(f"  {pid}: creating consumable")
            iap = s.c.create("inAppPurchases", {**attrs, "productId": pid, "inAppPurchaseType": "CONSUMABLE"},
                             {"app": rel("apps", APP_ID)}, path="/v2/inAppPurchases")
        else:
            s.c.upsert("inAppPurchases", iap, attrs, patch_path=f"/v2/inAppPurchases/{iap['id']}", label=f"{pid} ({attr(iap, 'state')})")
        iid = iap["id"]

        locs = s.c.get_list(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")
        loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
        loc_attrs = {"name": product["name"], "description": product["description"]}
        s.c.upsert("inAppPurchaseLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
                   {"inAppPurchaseV2": rel("inAppPurchases", iid)}, label=f"  {pid} localization {LOCALE}",
                   refetch=lambda: next((l for l in s.c.get_list(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations") if attr(l, "locale") == LOCALE), None))

        schedule = s.c.get_one(f"/v2/inAppPurchases/{iid}/iapPriceSchedule")
        if schedule:
            log(f"    {pid} price schedule: exists (delete it in App Store Connect to re-price)")
        else:
            point = s.price_point(f"/v2/inAppPurchases/{iid}/pricePoints", product["customerPrice"], pid)
            by_territory = s.equalized(f"/v1/inAppPurchasePricePoints/{point['id']}/equalizations", point, {"filter[inAppPurchaseV2]": iid})
            log(f"    {pid} price schedule: creating, USD {product['customerPrice']} equalised to {len(by_territory)} territories")
            s.c.create(
                "inAppPurchasePriceSchedules",
                relationships={
                    "inAppPurchase": rel("inAppPurchases", iid),
                    "baseTerritory": rel("territories", BASE_TERRITORY),
                    "manualPrices": rel_many("inAppPurchasePrices", [f"${{{t}}}" for t in by_territory]),
                },
                included=[{"type": "inAppPurchasePrices", "id": f"${{{t}}}", "attributes": {"startDate": None},
                           "relationships": {"inAppPurchasePricePoint": rel("inAppPurchasePricePoints", pp),
                                             "inAppPurchaseV2": rel("inAppPurchases", iid)}}
                          for t, pp in by_territory.items()],
            )

        avail = s.c.get_one(f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability")
        if avail:
            log(f"    {pid} availability: exists")
        else:
            territories = s.territories()
            log(f"    {pid} availability: creating for {len(territories)} territories")
            s.c.create("inAppPurchaseAvailabilities", {"availableInNewTerritories": True},
                       {"inAppPurchase": rel("inAppPurchases", iid), "availableTerritories": rel_many("territories", territories)})

        if review_png:
            shot = s.c.get_one(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot")
            s.upload_asset("inAppPurchaseAppStoreReviewScreenshots", {"inAppPurchaseV2": rel("inAppPurchases", iid)}, review_png,
                           [shot] if shot else [])


def cmd_subscriptions(s: Store) -> None:
    log("== subscriptions")
    group_cfg = read_json(SUBS_DIR / "group.json")
    groups = s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups", {"filter[referenceName]": group_cfg["referenceName"]})
    if groups:
        group = groups[0]
        log(f"  subscriptionGroup {group_cfg['referenceName']}: exists ({group['id']})")
    else:
        log(f"  subscriptionGroup {group_cfg['referenceName']}: creating")
        group = s.c.create("subscriptionGroups", {"referenceName": group_cfg["referenceName"]}, {"app": rel("apps", APP_ID)})
    gid = group["id"]
    glocs = s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations")
    gloc = next((l for l in glocs if attr(l, "locale") == LOCALE), None)
    g_attrs = dict(localized(group_cfg))
    s.c.upsert("subscriptionGroupLocalizations", gloc, g_attrs if gloc else {**g_attrs, "locale": LOCALE},
               {"subscriptionGroup": rel("subscriptionGroups", gid)}, label=f"group localization {LOCALE}",
               refetch=lambda: next((l for l in s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations") if attr(l, "locale") == LOCALE), None))

    in_group = {attr(x, "productId"): x for x in s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptions")}
    territories = s.territories()
    for name in ("vip_monthly.json", "vip_yearly.json"):
        cfg = read_json(SUBS_DIR / name)
        pid = cfg["productId"]
        log(f"  -- {pid}")
        sub = in_group.get(pid)
        if sub is None and cfg.get("appStoreId"):
            sub = s.c.get_one(f"/v1/subscriptions/{cfg['appStoreId']}")
        attrs = {"name": cfg["referenceName"], "reviewNote": cfg["reviewNote"], "subscriptionPeriod": cfg["subscriptionPeriod"],
                 "groupLevel": cfg["groupLevel"], "familySharable": cfg["familySharable"]}
        if sub is None:
            log(f"    {pid}: creating")
            sub = s.c.create("subscriptions", {**attrs, "productId": pid}, {"group": rel("subscriptionGroups", gid)})
        else:
            sub = s.c.upsert("subscriptions", sub, attrs, label=f"  {pid} ({attr(sub, 'state')})")
        sid = sub["id"]

        locs = s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
        loc_attrs = dict(localized(cfg))
        check_limit("iap_name", loc_attrs["name"])
        check_limit("iap_description", loc_attrs["description"])
        s.c.upsert("subscriptionLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
                   {"subscription": rel("subscriptions", sid)}, label=f"  {pid} localization {LOCALE}",
                   refetch=lambda: next((l for l in s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations") if attr(l, "locale") == LOCALE), None))

        # Prices: one subscriptionPrices record per territory, equalised from the USD price point.
        price = cfg["price"]["customerPrice"]
        priced = {territory_of(p) for p in s.c.get_list(f"/v1/subscriptions/{sid}/prices", {"include": "territory"})}
        point = s.price_point(f"/v1/subscriptions/{sid}/pricePoints", price, pid)
        by_territory = s.equalized(f"/v1/subscriptionPricePoints/{point['id']}/equalizations", point, {"filter[subscription]": sid})
        todo = {t: pp for t, pp in by_territory.items() if t not in priced}
        log(f"    prices: USD {price} -> {len(by_territory)} territories, {len(priced)} already set, creating {len(todo)}")
        for t, pp in todo.items():
            s.c.create("subscriptionPrices", {"preserveCurrentPrice": False},
                       {"subscription": rel("subscriptions", sid), "subscriptionPricePoint": rel("subscriptionPricePoints", pp),
                        "territory": rel("territories", t)})

        # Introductory offer: free trial, one per territory.
        offer = cfg["introductoryOffer"]
        offered = {territory_of(o) for o in s.c.get_list(f"/v1/subscriptions/{sid}/introductoryOffers", {"include": "territory"})}
        todo_t = [t for t in territories if t not in offered]
        log(f"    introductory offer {offer['offerMode']} {offer['duration']}: {len(offered)} territories set, creating {len(todo_t)}")
        for t in todo_t:
            s.c.create("subscriptionIntroductoryOffers",
                       {"offerMode": offer["offerMode"], "duration": offer["duration"], "numberOfPeriods": offer["numberOfPeriods"]},
                       {"subscription": rel("subscriptions", sid), "territory": rel("territories", t)})

        shot = s.c.get_one(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        s.upload_asset("subscriptionAppStoreReviewScreenshots", {"subscription": rel("subscriptions", sid)},
                       ROOT / cfg["reviewScreenshot"], [shot] if shot else [])
        images = s.c.get_list(f"/v1/subscriptions/{sid}/images")
        live = [i for i in images if ((attr(i, "assetDeliveryState") or {}).get("state")) not in ("AWAITING_UPLOAD", "FAILED")]
        if live:
            log(f"  subscriptionImages: image already present ({attr(live[0], 'fileName')}), keeping it")
        else:
            s.upload_asset("subscriptionImages", {"subscription": rel("subscriptions", sid)}, ROOT / cfg["promotionalImage"], images)

        avail = s.c.get_one(f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if avail:
            log("    availability: exists")
        else:
            log(f"    availability: creating for {len(territories)} territories")
            s.c.create("subscriptionAvailabilities", {"availableInNewTerritories": True},
                       {"subscription": rel("subscriptions", sid), "availableTerritories": rel_many("territories", territories)})


def contact_attrs() -> dict:
    contact = read_json(EN / "review_contact.json")
    attrs = {}
    skipped = []
    for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
        if is_placeholder(contact.get(key)):
            skipped.append(key)
        else:
            attrs[key] = contact[key]
    if skipped:
        log(f"  review_contact.json still has placeholders for {', '.join(skipped)}; sending the rest")
    attrs["demoAccountRequired"] = bool(contact.get("demoAccountRequired", False))
    return attrs


def cmd_review_info(s: Store) -> None:
    log("== review-info")
    version = s.version(create=True)
    detail = s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
    attrs = {**contact_attrs(), "notes": read_text("review_notes.txt")}
    s.c.upsert("appStoreReviewDetails", detail, attrs, {"appStoreVersion": rel("appStoreVersions", version["id"])}, label="appStoreReviewDetail",
               refetch=lambda: s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail"))


def cmd_testflight(s: Store) -> None:
    log("== testflight")
    contact = contact_attrs()
    what_to_test = read_text("testflight_what_to_test.txt")
    locs = s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations")
    loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
    loc_attrs = {"description": what_to_test, "marketingUrl": read_text("marketing_url.txt"), "privacyPolicyUrl": read_text("privacy_url.txt")}
    if "contactEmail" in contact:
        loc_attrs["feedbackEmail"] = contact["contactEmail"]
    s.c.upsert("betaAppLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
               {"app": rel("apps", APP_ID)}, label=f"betaAppLocalization {LOCALE}",
               refetch=lambda: next((l for l in s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations") if attr(l, "locale") == LOCALE), None))

    detail = s.c.get_one(f"/v1/apps/{APP_ID}/betaAppReviewDetail")
    detail_attrs = {**contact, "notes": read_text("review_notes.txt")}
    if "contactPhone" not in contact:
        log("  betaAppReviewDetail: skipped, Apple requires contactPhone (fill review_contact.json and rerun)")
        detail = False
    if detail is None:
        if s.c.dry_run:
            detail = {"id": "DRY-betaAppReviewDetail", "attributes": {}}
        else:
            sys.exit("no betaAppReviewDetail on the app; App Store Connect creates it with the app record")
    if detail is not False:
        s.c.upsert("betaAppReviewDetails", detail, detail_attrs, label="betaAppReviewDetail")

    agreement = s.c.get_one(f"/v1/apps/{APP_ID}/betaLicenseAgreement")
    text = read_text("beta_license_agreement.txt")
    if agreement is None:
        if s.c.dry_run:
            agreement = {"id": "DRY-betaLicenseAgreement", "attributes": {}}
        else:
            sys.exit("no betaLicenseAgreement on the app; App Store Connect creates it with the app record")
    s.c.upsert("betaLicenseAgreements", agreement, {"agreementText": text}, label="betaLicenseAgreement")

    groups = s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups")
    group = next((g for g in groups if attr(g, "name") == BETA_GROUP_NAME), None)
    group_attrs = {"publicLinkEnabled": True, "publicLinkLimitEnabled": False, "feedbackEnabled": True}
    group = s.c.upsert("betaGroups", group, group_attrs if group else {**group_attrs, "name": BETA_GROUP_NAME, "isInternalGroup": False},
                       {"app": rel("apps", APP_ID)}, label=f"betaGroup '{BETA_GROUP_NAME}'")
    link = attr(group, "publicLink")
    if link:
        log(f"  public TestFlight link: {link}")

    build = s.latest_build()
    if build is None:
        log("  no build uploaded yet; skipping build metadata (run tools/store/upload_build.sh, then this again)")
        return
    bid = build["id"]
    log(f"  latest build {attr(build, 'version')} ({attr(build, 'processingState')}, uploaded {attr(build, 'uploadedDate')})")
    if attr(build, "usesNonExemptEncryption") is not False:
        log("  build: setting usesNonExemptEncryption=false")
        s.c.update("builds", bid, {"usesNonExemptEncryption": False})
    else:
        log("  build: usesNonExemptEncryption already false")
    blocs = s.c.get_list(f"/v1/builds/{bid}/betaBuildLocalizations")
    bloc = next((l for l in blocs if attr(l, "locale") == LOCALE), None)
    whats_new = {"whatsNew": read_text("release_notes.txt")}
    s.c.upsert("betaBuildLocalizations", bloc, whats_new if bloc else {**whats_new, "locale": LOCALE},
               {"build": rel("builds", bid)}, label=f"betaBuildLocalization {LOCALE}",
               refetch=lambda: next((l for l in s.c.get_list(f"/v1/builds/{bid}/betaBuildLocalizations") if attr(l, "locale") == LOCALE), None))
    in_group = {b["id"] for b in s.c.get_list(f"/v1/betaGroups/{group['id']}/builds")}
    if bid in in_group:
        log("  build already in the public group")
    else:
        log(f"  adding build to '{BETA_GROUP_NAME}'")
        s.c.request("POST", f"/v1/betaGroups/{group['id']}/relationships/builds", rel_many("builds", [bid]))

    # External testers (the public link) can only install a build that has passed
    # Beta App Review. Submit the build unless it already has a submission.
    detail = s.c.get_one(f"/v1/builds/{bid}/buildBetaDetail")
    ext_state = attr(detail, "externalBuildState") if detail else None
    submission = s.c.get_one(f"/v1/builds/{bid}/betaAppReviewSubmission", allow_404=True)
    if submission:
        log(f"  beta app review: {attr(submission, 'betaReviewState')} (external state {ext_state})")
    elif ext_state == "READY_FOR_BETA_SUBMISSION":
        if s.c.dry_run:
            log("  beta app review: would submit the build")
        else:
            r = s.c.create("betaAppReviewSubmissions", None, {"build": rel("builds", bid)})
            log(f"  beta app review: submitted ({attr(r, 'betaReviewState')}); the public link works once Apple approves it")
    else:
        log(f"  beta app review: external state {ext_state}, nothing to submit")


# ---------------------------------------------------------------------------
# Read-only commands
# ---------------------------------------------------------------------------


def cmd_status(s: Store, categories: bool = False) -> None:
    log("== status")
    app = s.app()
    log(f"  app {APP_ID}: {attr(app, 'name')} ({attr(app, 'bundleId')}) primaryLocale={attr(app, 'primaryLocale')}")
    for info in s.c.get_list(f"/v1/apps/{APP_ID}/appInfos"):
        cats = {k: ((v.get('data') or {}).get('id')) for k, v in (info.get('relationships') or {}).items() if 'ategory' in k and v.get('data')}
        log(f"  appInfo {info['id']}: state={attr(info, 'state')} ageRating={attr(info, 'appStoreAgeRating')} {cats}")
        for loc in s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations"):
            log(f"    {attr(loc, 'locale')}: name={attr(loc, 'name')!r} subtitle={attr(loc, 'subtitle')!r} privacy={attr(loc, 'privacyPolicyUrl')}")
    for v in s.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": PLATFORM}):
        log(f"  appStoreVersion {attr(v, 'versionString')}: state={attr(v, 'appVersionState') or attr(v, 'appStoreState')} copyright={attr(v, 'copyright')!r}")
        for loc in s.c.get_list(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations"):
            sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
            shots = {attr(x, 'screenshotDisplayType'): len(s.c.get_list(f"/v1/appScreenshotSets/{x['id']}/appScreenshots")) for x in sets}
            log(f"    {attr(loc, 'locale')}: description={len(attr(loc, 'description') or '')} chars keywords={attr(loc, 'keywords')!r} screenshots={shots}")
        detail = s.c.get_one(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")
        log(f"    reviewDetail: {'set' if detail else 'missing'}")
    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    log(f"  appPriceSchedule: {'set' if schedule else 'missing'}")
    avail = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    log(f"  appAvailabilityV2: {'set' if avail else 'missing'}")
    for iap in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2"):
        log(f"  iap {attr(iap, 'productId')}: {attr(iap, 'inAppPurchaseType')} state={attr(iap, 'state')} id={iap['id']}")
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups"):
        log(f"  subscriptionGroup {attr(g, 'referenceName')} ({g['id']})")
        for sub in s.c.get_list(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            prices = s.c.get_list(f"/v1/subscriptions/{sub['id']}/prices")
            offers = s.c.get_list(f"/v1/subscriptions/{sub['id']}/introductoryOffers")
            log(f"    {attr(sub, 'productId')}: state={attr(sub, 'state')} period={attr(sub, 'subscriptionPeriod')} prices={len(prices)} introOffers={len(offers)} id={sub['id']}")
    build = s.latest_build()
    log(f"  latest build: {attr(build, 'version') if build else 'none'}" + (f" ({attr(build, 'processingState')})" if build else ""))
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups"):
        log(f"  betaGroup {attr(g, 'name')!r}: public={attr(g, 'publicLinkEnabled')} link={attr(g, 'publicLink')}")
    if categories:
        log("  appCategories (ids for categories.json):")
        for cat in s.c.get_list("/v1/appCategories", {"filter[platforms]": PLATFORM, "exists[parent]": "false", "include": "subcategories"}):
            subs = [x["id"] for x in ((cat.get("relationships") or {}).get("subcategories") or {}).get("data") or []]
            log(f"    {cat['id']}: {', '.join(subs)}")


def cmd_audit(s: Store) -> int:
    """Checklist for App Store submission and a public TestFlight link. Read-only."""
    log("== audit")
    rows: list[tuple[str, str, str]] = []

    def row(state: str, what: str, detail: str = "") -> None:
        rows.append((state, what, detail))

    def ok_if(cond: Any, what: str, detail: str = "") -> None:
        row("OK" if cond else "MISSING", what, detail)

    app = s.app()
    ok_if(app, "app record", f"{attr(app, 'name')} {attr(app, 'bundleId')}" if app else f"GET /v1/apps/{APP_ID} returned nothing")
    if not app and not s.c.dry_run:
        return _print_audit(rows)

    info = s.app_info()
    rels = info.get("relationships") or {}
    primary = ((rels.get("primaryCategory") or {}).get("data")) or s.c.get_one(f"/v1/appInfos/{info['id']}/primaryCategory")
    ok_if(primary, "primary category", primary["id"] if primary else None)
    locs = s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations")
    loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
    ok_if(loc and attr(loc, "name"), f"app name ({LOCALE})")
    ok_if(loc and attr(loc, "subtitle"), f"subtitle ({LOCALE})")
    ok_if(loc and attr(loc, "privacyPolicyUrl"), "privacy policy URL")
    decl = s.c.get_one(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    ok_if(decl and attr(decl, "violenceCartoonOrFantasy") is not None, "age rating questionnaire")

    version = s.version()
    ok_if(version, f"appStoreVersion {VERSION_STRING} ({PLATFORM})")
    if version:
        ok_if(attr(version, "copyright"), "copyright")
        vloc = s.version_localization(version)
        ok_if(vloc, f"version localization ({LOCALE})")
        if vloc:
            for key in ("description", "keywords", "supportUrl"):
                ok_if(attr(vloc, key), f"  {key}")
            row("OK" if attr(vloc, "promotionalText") else "N/A", "  promotionalText (optional)")
            row("OK" if attr(vloc, "marketingUrl") else "N/A", "  marketingUrl (optional)")
            sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")
            by_type = {attr(x, "screenshotDisplayType"): x for x in sets}
            shots = s.c.get_list(f"/v1/appScreenshotSets/{by_type[SCREENSHOT_TYPE]['id']}/appScreenshots") if SCREENSHOT_TYPE in by_type else []
            complete = [x for x in shots if ((attr(x, "assetDeliveryState") or {}).get("state")) in ("COMPLETE", None)]
            ok_if(complete, f"  screenshots {SCREENSHOT_TYPE}", f"{len(complete)} of {len(shots)} delivered")
            row("OK" if "APP_IPAD_PRO_3GEN_129" in by_type else "N/A", "  screenshots iPad 13-inch (only if the app runs on iPad)")
        detail = s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
        ok_if(detail, "App Review contact (appStoreReviewDetail)")
        if detail:
            for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
                ok_if(attr(detail, key), f"  {key}")
            row("OK" if attr(detail, "notes") else "N/A", "  review notes (optional)")
        build_rel = ((version.get("relationships") or {}).get("build") or {}).get("data") or s.c.get_one(f"/v1/appStoreVersions/{version['id']}/build")
        ok_if(build_rel, "build attached to the version",
              f"build {attr(build_rel, 'version')}" if build_rel and build_rel.get("attributes") else "select a build in App Store Connect or PATCH appStoreVersions/{id}/relationships/build")

    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    described = s.describe_price_schedule(schedule) if schedule and not s.c.dry_run else ""
    ok_if(schedule and described != "no manual prices", "price schedule (free)", described or "run `price-free`")
    avail = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    ok_if(avail, "territory availability")
    ok_if(attr(app, "contentRightsDeclaration") if app else None, "content rights declaration", "`app-info` sets USES_THIRD_PARTY_CONTENT (licensed photos)")
    urls = (attr(app, "subscriptionStatusUrl"), attr(app, "subscriptionStatusUrlForSandbox")) if app else (None, None)
    ok_if(all(u == NOTIFICATIONS_URL for u in urls), "App Store Server Notification URLs (production + sandbox, V2)", f"{urls[0]} / {urls[1]}")

    cfg = read_json(SUBS_DIR / "consumables.json")
    existing = {attr(p, "productId"): p for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2")}
    for product in cfg["products"]:
        pid = product["productId"]
        iap = existing.get(pid)
        if not iap:
            row("MISSING", f"iap {pid}")
            continue
        locs_i = s.c.get_list(f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")
        sched = s.c.get_one(f"/v2/inAppPurchases/{iap['id']}/iapPriceSchedule")
        shot = s.c.get_one(f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot")
        parts = [f"state={attr(iap, 'state')}", f"localizations={len(locs_i)}", f"price={'set' if sched else 'MISSING'}", f"reviewScreenshot={'set' if shot else 'missing'}"]
        ok_if(locs_i and sched, f"iap {pid}", " ".join(parts))

    group_cfg = read_json(SUBS_DIR / "group.json")
    groups = s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups", {"filter[referenceName]": group_cfg["referenceName"]})
    ok_if(groups, f"subscription group {group_cfg['referenceName']}")
    if groups:
        glocs = s.c.get_list(f"/v1/subscriptionGroups/{groups[0]['id']}/subscriptionGroupLocalizations")
        ok_if(glocs, "  group localization")
        subs = {attr(x, "productId"): x for x in s.c.get_list(f"/v1/subscriptionGroups/{groups[0]['id']}/subscriptions")}
        for name in ("vip_monthly.json", "vip_yearly.json"):
            scfg = read_json(SUBS_DIR / name)
            pid = scfg["productId"]
            sub = subs.get(pid)
            if not sub:
                row("MISSING", f"  subscription {pid}")
                continue
            sid = sub["id"]
            n_loc = len(s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations"))
            n_price = len(s.c.get_list(f"/v1/subscriptions/{sid}/prices"))
            n_offer = len(s.c.get_list(f"/v1/subscriptions/{sid}/introductoryOffers"))
            shot = s.c.get_one(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
            avail_s = s.c.get_one(f"/v1/subscriptions/{sid}/subscriptionAvailability")
            ok_if(n_loc and n_price and shot and avail_s, f"  subscription {pid}",
                  f"state={attr(sub, 'state')} localizations={n_loc} prices={n_price} introOffers={n_offer} reviewScreenshot={'set' if shot else 'MISSING'} availability={'set' if avail_s else 'MISSING'}")
            row("OK" if n_offer else "MISSING", f"    {pid} introductory offer (1 week free)")

    # TestFlight
    blocs = s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations")
    bloc = next((l for l in blocs if attr(l, "locale") == LOCALE), None)
    ok_if(bloc and attr(bloc, "feedbackEmail"), "TestFlight feedback email (betaAppLocalization)")
    ok_if(bloc and attr(bloc, "description"), "TestFlight 'what to test' description")
    ok_if(bloc and attr(bloc, "privacyPolicyUrl"), "TestFlight privacy policy URL")
    bdetail = s.c.get_one(f"/v1/apps/{APP_ID}/betaAppReviewDetail")
    ok_if(bdetail and attr(bdetail, "contactEmail") and attr(bdetail, "contactFirstName"), "TestFlight beta review contact")
    agreement = s.c.get_one(f"/v1/apps/{APP_ID}/betaLicenseAgreement")
    row("OK" if agreement and attr(agreement, "agreementText") else "N/A", "TestFlight license agreement (optional, Apple's default applies)")
    build = s.latest_build()
    ok_if(build, "uploaded build", f"{attr(build, 'version')} {attr(build, 'processingState')}" if build else "run tools/store/upload_build.sh")
    if build:
        ok_if(attr(build, "processingState") == "VALID", "  build processed", attr(build, "processingState"))
        ok_if(attr(build, "usesNonExemptEncryption") is not None, "  export compliance (usesNonExemptEncryption)", "set ITSAppUsesNonExemptEncryption in Info.plist or run `testflight`")
        bl = s.c.get_list(f"/v1/builds/{build['id']}/betaBuildLocalizations")
        row("OK" if any(attr(x, "whatsNew") for x in bl) else "N/A", "  build 'what to test' (optional)")
    groups_b = s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups")
    public = [g for g in groups_b if attr(g, "publicLinkEnabled")]
    ok_if(public, "public TestFlight group", ", ".join(f"{attr(g, 'name')} {attr(g, 'publicLink')}" for g in public))
    if public and build:
        in_group = {b["id"] for b in s.c.get_list(f"/v1/betaGroups/{public[0]['id']}/builds")}
        ok_if(build["id"] in in_group, "  latest build in the public group")
    row("N/A", "App privacy (data collection) questionnaire", "no public API; fill in App Store Connect > App Privacy")
    row("N/A", "Paid Applications agreement, banking and tax", "no public API; App Store Connect > Business")
    return _print_audit(rows)


def _print_audit(rows: list[tuple[str, str, str]]) -> int:
    missing = 0
    for state, what, detail in rows:
        missing += state == "MISSING"
        log(f"  [{state:7}] {what}" + (f"  - {detail}" if detail else ""))
    log(f"  {missing} missing item(s)")
    return 1 if missing else 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMANDS: dict[str, Callable[[Store], Any]] = {
    "app-info": cmd_app_info,
    "version": cmd_version,
    "age-rating": cmd_age_rating,
    "price-free": cmd_price_free,
    "screenshots": cmd_screenshots,
    "iap": cmd_iap,
    "subscriptions": cmd_subscriptions,
    "review-info": cmd_review_info,
    "testflight": cmd_testflight,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=[*COMMANDS, "status", "audit", "all"],
                        help="`all` runs: " + ", ".join(ALL_ORDER))
    parser.add_argument("--dry-run", action="store_true", help="print every request instead of sending it")
    parser.add_argument("--verbose", "-v", action="store_true", help="also print GET requests")
    parser.add_argument("--categories", action="store_true", help="with `status`: list App Store category ids")
    args = parser.parse_args(argv)

    client = Client(dry_run=args.dry_run, verbose=args.verbose)
    store = Store(client)
    if args.dry_run:
        log(f"dry run: nothing is sent. Issuer ID loaded, key {KEY_ID}, app {APP_ID} ({BUNDLE_ID})")
    global LOCALE
    try:
        app = store.app()
        if app and attr(app, "primaryLocale"):
            LOCALE = attr(app, "primaryLocale")
        elif not args.dry_run:
            sys.exit(f"could not read app {APP_ID}; check the key, the Issuer ID and the key's role")
        log(f"locale: {LOCALE} (metadata read from store/metadata/en-US)")
        if args.command == "status":
            cmd_status(store, categories=args.categories)
        elif args.command == "audit":
            return cmd_audit(store)
        elif args.command == "all":
            for name in ALL_ORDER:
                COMMANDS[name](store)
        else:
            COMMANDS[args.command](store)
    except ApiError as err:
        log(f"error: {err}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
