#!/usr/bin/env python3
"""
Sync Game Center achievement + leaderboard images to App Store Connect using the ASC API.

This script uses ONLY stdlib + `openssl` (for ES256 signing).

Required:
  - App Store Connect API Issuer ID (UUID)
  - API Key ID (10 chars, from AuthKey_<KEYID>.p8)
  - Path to the .p8 private key
  - Bundle ID (e.g. Jorsh.WorkingOut)

It reads local image mappings from:
  GameCenterResources.gamekit/gameCenterResources.json
and expects the referenced files to exist (e.g. GameCenterResources.gamekit/en-US/...png).
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple, NoReturn


ASC_API = "https://api.appstoreconnect.apple.com/v1"


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAMEKIT_JSON = REPO_ROOT / "GameCenterResources.gamekit" / "gameCenterResources.json"


def die(msg: str) -> NoReturn:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(2)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _der_read_len(buf: bytes, i: int) -> Tuple[int, int]:
    if i >= len(buf):
        raise ValueError("DER: truncated length")
    first = buf[i]
    i += 1
    if first < 0x80:
        return first, i
    n = first & 0x7F
    if n == 0 or n > 4:
        raise ValueError("DER: unsupported length")
    if i + n > len(buf):
        raise ValueError("DER: truncated length bytes")
    length = int.from_bytes(buf[i : i + n], "big")
    return length, i + n


def der_parse_ecdsa_sig(der: bytes) -> Tuple[int, int]:
    # ECDSA signature from OpenSSL is ASN.1 DER:
    # SEQUENCE { INTEGER r; INTEGER s }
    i = 0
    if i >= len(der) or der[i] != 0x30:
        raise ValueError("DER: expected SEQUENCE")
    i += 1
    seq_len, i = _der_read_len(der, i)
    end = i + seq_len
    if end > len(der):
        raise ValueError("DER: truncated sequence")

    def read_int(buf: bytes, j: int) -> Tuple[int, int]:
        if j >= len(buf) or buf[j] != 0x02:
            raise ValueError("DER: expected INTEGER")
        j += 1
        ln, j = _der_read_len(buf, j)
        if j + ln > len(buf):
            raise ValueError("DER: truncated INTEGER")
        raw = buf[j : j + ln]
        # two's complement; for ECDSA it should be positive
        return int.from_bytes(raw, "big", signed=False), j + ln

    r, i = read_int(der, i)
    s, i = read_int(der, i)
    if i != end:
        # allow trailing bytes inside SEQ? no.
        pass
    return r, s


def ecdsa_der_to_raw_64(der: bytes) -> bytes:
    r, s = der_parse_ecdsa_sig(der)
    rb = r.to_bytes(32, "big", signed=False)
    sb = s.to_bytes(32, "big", signed=False)
    return rb + sb


def make_jwt_es256(issuer_id: str, key_id: str, p8_path: Path, ttl_seconds: int = 1200) -> str:
    now = int(dt.datetime.now(dt.timezone.utc).timestamp())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "exp": now + ttl_seconds, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}".encode(
        "ascii"
    )

    # OpenSSL emits DER-encoded ECDSA signature; ASC expects raw r||s.
    try:
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(p8_path)],
            input=signing_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        die(f"openssl signing failed: {e.stderr.decode('utf-8', 'replace').strip()}")
    raw_sig = ecdsa_der_to_raw_64(proc.stdout)
    token = signing_input.decode("ascii") + "." + b64url(raw_sig)
    return token


def http_request(method: str, url: str, token: str, body: Optional[bytes] = None, content_type: str = "application/json") -> Tuple[int, bytes]:
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    if body is not None:
        req.add_header("Content-Type", content_type)
        req.data = body
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def asc_get(path: str, token: str, params: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    url = ASC_API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    code, data = http_request("GET", url, token)
    if code >= 400:
        die(f"ASC GET {path} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")
    return json.loads(data.decode("utf-8"))


def asc_post(path: str, token: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    code, data = http_request("POST", ASC_API + path, token, body=body)
    if code >= 400:
        die(f"ASC POST {path} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")
    return json.loads(data.decode("utf-8"))

def asc_patch(path: str, token: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    code, data = http_request("PATCH", ASC_API + path, token, body=body)
    if code >= 400:
        die(f"ASC PATCH {path} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")
    return json.loads(data.decode("utf-8"))

def asc_delete(path: str, token: str) -> None:
    code, data = http_request("DELETE", ASC_API + path, token)
    if code not in (200, 202, 204):
        die(f"ASC DELETE {path} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")

def asc_get_optional(path: str, token: str, params: Optional[Dict[str, str]] = None) -> Optional[Dict[str, Any]]:
    url = ASC_API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    code, data = http_request("GET", url, token)
    if code == 404:
        return None
    if code >= 400:
        die(f"ASC GET {path} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")
    return json.loads(data.decode("utf-8"))


def asc_list(path: str, token: str, params: Optional[Dict[str, str]] = None) -> List[Dict[str, Any]]:
    url = ASC_API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    out: List[Dict[str, Any]] = []
    while url:
        code, data = http_request("GET", url, token)
        if code >= 400:
            die(f"ASC GET {url} failed ({code}): {data.decode('utf-8', 'replace')[:2000]}")
        j = json.loads(data.decode("utf-8"))
        out.extend(j.get("data") or [])
        url = (j.get("links") or {}).get("next")
    return out


def find_app_id(token: str, bundle_id: str) -> str:
    j = asc_get("/apps", token, params={"filter[bundleId]": bundle_id})
    data = j.get("data", [])
    if not data:
        die(f"No app found for bundle id {bundle_id}")
    return data[0]["id"]


def get_or_create_game_center_detail(token: str, app_id: str) -> str:
    j = asc_get(f"/apps/{app_id}/relationships/gameCenterDetail", token)
    rel = j.get("data")
    if rel and isinstance(rel, dict) and rel.get("id"):
        return rel["id"]
    created = asc_post(
        "/gameCenterDetails",
        token,
        {"data": {"type": "gameCenterDetails", "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}},
    )
    return created["data"]["id"]


@dataclass(frozen=True)
class ImageMapping:
    local_id: str
    url: str  # relative to GameCenterResources.gamekit/
    file_path: Path  # resolved on disk


def load_gamekit_image_mappings(gamekit_json: Path) -> Tuple[List[ImageMapping], List[ImageMapping]]:
    obj = json.loads(gamekit_json.read_text(encoding="utf-8"))
    res = obj.get("resources", {}) if isinstance(obj.get("resources"), dict) else {}
    ach = res.get("achievementImages", {}) or {}
    lbs = res.get("leaderboardImages", {}) or {}

    def flatten(m: Dict[str, Any]) -> List[ImageMapping]:
        out: List[ImageMapping] = []
        for local_id, arr in m.items():
            if not isinstance(arr, list):
                continue
            for item in arr:
                if not isinstance(item, dict):
                    continue
                lid = item.get("localID") or local_id
                url = item.get("url")
                if not (isinstance(lid, str) and isinstance(url, str)):
                    continue
                file_path = gamekit_json.parent / url
                out.append(ImageMapping(local_id=lid, url=url, file_path=file_path))
        return out

    return flatten(ach), flatten(lbs)

def find_localization_relationship_key(localization_resource: Dict[str, Any], preferred: str) -> str:
    rels = ((localization_resource.get("data") or {}).get("relationships") or {})
    if preferred in rels:
        return preferred
    image_keys = [k for k in rels.keys() if "Image" in k or k.lower().endswith("image")]
    if len(image_keys) == 1:
        return image_keys[0]
    if image_keys:
        # Best-effort: prefer exact suffix match.
        for k in image_keys:
            if k.lower().endswith("image"):
                return k
    die(f"Could not determine image relationship key for localization; relationships: {sorted(rels.keys())}")


def upload_via_operations(file_bytes: bytes, operations: List[Dict[str, Any]]) -> None:
    if not operations:
        die("ASC did not return uploadOperations; cannot upload file")

    for op in operations:
        method = op.get("method") or "PUT"
        url = op.get("url")
        if not isinstance(url, str) or not url:
            die(f"Invalid upload operation url: {op!r}")
        headers_list = op.get("headers") or []
        headers: Dict[str, str] = {}
        if isinstance(headers_list, list):
            for h in headers_list:
                if isinstance(h, dict) and isinstance(h.get("name"), str) and isinstance(h.get("value"), str):
                    headers[h["name"]] = h["value"]

        offset = op.get("offset")
        length = op.get("length")
        if isinstance(offset, int) and isinstance(length, int):
            chunk = file_bytes[offset : offset + length]
        else:
            chunk = file_bytes

        req = urllib.request.Request(url, method=method)
        for k, v in headers.items():
            req.add_header(k, v)
        req.data = chunk
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                if resp.status >= 400:
                    die(f"Upload failed ({resp.status}) to {url}")
        except urllib.error.HTTPError as e:
            die(f"Upload failed ({e.code}) to {url}: {e.read().decode('utf-8', 'replace')[:2000]}")


def parse_vendor_identifier_from_local_id(local_id: str) -> str:
    # For our .gamekit, localIDs are "<vendorIdentifier>-en-US"
    if local_id.endswith("-en-US"):
        return local_id[: -len("-en-US")]
    return local_id


def autodetect_p8_and_key_id(explicit_p8: Optional[str], explicit_key_id: Optional[str]) -> Tuple[Path, str]:
    if explicit_p8:
        p8_path = Path(explicit_p8).expanduser().resolve()
        if not p8_path.exists():
            die(f"Missing .p8 file: {p8_path}")
        key_id = explicit_key_id
        if not key_id:
            m = re.search(r"AuthKey_([A-Z0-9]{10})\\.p8$", p8_path.name)
            if not m:
                die("Missing --key-id (and could not infer from .p8 filename)")
            key_id = m.group(1)
        return p8_path, key_id

    candidates = sorted(REPO_ROOT.glob("AuthKey_*.p8"))
    if not candidates:
        die("No AuthKey_*.p8 found in repo root; pass --p8")
    if len(candidates) > 1:
        names = ", ".join([c.name for c in candidates])
        die(f"Multiple AuthKey_*.p8 found ({names}); pass --p8 to choose one")
    p8_path = candidates[0].resolve()
    if explicit_key_id:
        return p8_path, explicit_key_id
    m = re.search(r"AuthKey_([A-Z0-9]{10})\\.p8$", p8_path.name)
    if not m:
        die("Could not infer key id from AuthKey_*.p8 filename; pass --key-id")
    return p8_path, m.group(1)


def load_existing_achievement_localizations(token: str, gc_detail_id: str) -> Dict[Tuple[str, str], str]:
    # Map (vendorIdentifier, locale) -> localization_id
    out: Dict[Tuple[str, str], str] = {}
    achievements = asc_list(f"/gameCenterDetails/{gc_detail_id}/gameCenterAchievements", token, params={"limit": "200"})
    for a in achievements:
        ach_id = a.get("id")
        vendor = ((a.get("attributes") or {}).get("vendorIdentifier"))
        if not (isinstance(ach_id, str) and isinstance(vendor, str)):
            continue
        # Relationship name is `localizations` (not `gameCenterAchievementLocalizations`).
        locs = asc_list(f"/gameCenterAchievements/{ach_id}/localizations", token, params={"limit": "200"})
        for loc in locs:
            loc_id = loc.get("id")
            locale = ((loc.get("attributes") or {}).get("locale"))
            if isinstance(loc_id, str) and isinstance(locale, str):
                out[(vendor, locale)] = loc_id
    return out


def load_existing_leaderboard_localizations(token: str, gc_detail_id: str) -> Dict[Tuple[str, str], str]:
    # Map (vendorIdentifier, locale) -> localization_id
    out: Dict[Tuple[str, str], str] = {}
    boards = asc_list(f"/gameCenterDetails/{gc_detail_id}/gameCenterLeaderboards", token, params={"limit": "200"})
    for b in boards:
        lb_id = b.get("id")
        vendor = ((b.get("attributes") or {}).get("vendorIdentifier"))
        if not (isinstance(lb_id, str) and isinstance(vendor, str)):
            continue
        # Relationship name is `localizations` (not `gameCenterLeaderboardLocalizations`).
        locs = asc_list(f"/gameCenterLeaderboards/{lb_id}/localizations", token, params={"limit": "200"})
        for loc in locs:
            loc_id = loc.get("id")
            locale = ((loc.get("attributes") or {}).get("locale"))
            if isinstance(loc_id, str) and isinstance(locale, str):
                out[(vendor, locale)] = loc_id
    return out


def get_localization(token: str, kind: str, localization_id: str) -> Dict[str, Any]:
    if kind == "achievement":
        return asc_get(f"/gameCenterAchievementLocalizations/{localization_id}", token)
    return asc_get(f"/gameCenterLeaderboardLocalizations/{localization_id}", token)


def set_localization_image_relationship(token: str, kind: str, localization_id: str, image_id: str) -> None:
    if kind == "achievement":
        loc = get_localization(token, kind, localization_id)
        rel_key = find_localization_relationship_key(loc, preferred="gameCenterAchievementImage")
        asc_patch(
            f"/gameCenterAchievementLocalizations/{localization_id}",
            token,
            {"data": {"type": "gameCenterAchievementLocalizations", "id": localization_id, "relationships": {rel_key: {"data": {"type": "gameCenterAchievementImages", "id": image_id}}}}},
        )
    else:
        loc = get_localization(token, kind, localization_id)
        rel_key = find_localization_relationship_key(loc, preferred="gameCenterLeaderboardImage")
        asc_patch(
            f"/gameCenterLeaderboardLocalizations/{localization_id}",
            token,
            {"data": {"type": "gameCenterLeaderboardLocalizations", "id": localization_id, "relationships": {rel_key: {"data": {"type": "gameCenterLeaderboardImages", "id": image_id}}}}},
        )


def get_existing_image_id(token: str, kind: str, localization_id: str) -> Optional[str]:
    if kind == "achievement":
        j = asc_get_optional(f"/gameCenterAchievementLocalizations/{localization_id}/gameCenterAchievementImage", token)
    else:
        j = asc_get_optional(f"/gameCenterLeaderboardLocalizations/{localization_id}/gameCenterLeaderboardImage", token)
    if not j:
        return None
    data = j.get("data")
    if isinstance(data, dict) and isinstance(data.get("id"), str):
        return data["id"]
    return None


def create_and_upload_image(token: str, kind: str, localization_id: str, image_file: Path) -> str:
    file_bytes = image_file.read_bytes()
    filename = image_file.name
    file_size = len(file_bytes)

    if kind == "achievement":
        payload = {
            "data": {
                "type": "gameCenterAchievementImages",
                "attributes": {"fileName": filename, "fileSize": file_size},
                "relationships": {"gameCenterAchievementLocalization": {"data": {"type": "gameCenterAchievementLocalizations", "id": localization_id}}},
            }
        }
        created = asc_post("/gameCenterAchievementImages", token, payload)
        image_id = created["data"]["id"]
        attrs = (created.get("data") or {}).get("attributes") or {}
        upload_ops = attrs.get("uploadOperations") or []
        upload_via_operations(file_bytes, upload_ops)
        return image_id

    payload = {
        "data": {
            "type": "gameCenterLeaderboardImages",
            "attributes": {"fileName": filename, "fileSize": file_size},
            "relationships": {"gameCenterLeaderboardLocalization": {"data": {"type": "gameCenterLeaderboardLocalizations", "id": localization_id}}},
        }
    }
    created = asc_post("/gameCenterLeaderboardImages", token, payload)
    image_id = created["data"]["id"]
    attrs = (created.get("data") or {}).get("attributes") or {}
    upload_ops = attrs.get("uploadOperations") or []
    upload_via_operations(file_bytes, upload_ops)
    return image_id


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", default=os.getenv("ASC_BUNDLE_ID") or "Jorsh.WorkingOut")
    ap.add_argument("--issuer-id", default=os.getenv("ASC_ISSUER_ID"))
    ap.add_argument("--key-id", default=os.getenv("ASC_KEY_ID"), help="10-char key id; can be inferred from AuthKey_<KEYID>.p8")
    ap.add_argument("--p8", default=os.getenv("ASC_PRIVATE_KEY_PATH"), help="Path to AuthKey_<KEYID>.p8; defaults to auto-detect in repo root")
    ap.add_argument("--gamekit-json", default=str(DEFAULT_GAMEKIT_JSON))
    ap.add_argument("--dry-run", action="store_true", help="Print what would be uploaded without changing ASC.")
    ap.add_argument("--force", action="store_true", help="Replace existing images by deleting/re-uploading.")
    args = ap.parse_args()

    if not args.issuer_id:
        die("Missing --issuer-id (or ASC_ISSUER_ID env var)")
    p8_path, key_id = autodetect_p8_and_key_id(args.p8, args.key_id)

    gamekit_json = Path(args.gamekit_json).resolve()
    if not gamekit_json.exists():
        die(f"Missing gamekit json: {gamekit_json}")

    ach_imgs, lb_imgs = load_gamekit_image_mappings(gamekit_json)
    if not ach_imgs:
        die("No achievementImages mappings in .gamekit JSON")
    if not lb_imgs:
        die("No leaderboardImages mappings in .gamekit JSON")

    missing = [m for m in (ach_imgs + lb_imgs) if not m.file_path.exists()]
    if missing:
        die(f"Missing {len(missing)} referenced image files; first: {missing[0].file_path}")

    token = make_jwt_es256(args.issuer_id, key_id, p8_path)

    app_id = find_app_id(token, args.bundle_id)
    gc_detail_id = get_or_create_game_center_detail(token, app_id)
    print(f"App: {args.bundle_id} -> {app_id}")
    print(f"GameCenterDetail -> {gc_detail_id}")

    ach_loc_map = load_existing_achievement_localizations(token, gc_detail_id)
    lb_loc_map = load_existing_leaderboard_localizations(token, gc_detail_id)

    # Upload achievement images
    uploaded = 0
    skipped_missing = 0
    skipped_existing = 0

    for m in ach_imgs:
        vendor = parse_vendor_identifier_from_local_id(m.local_id)
        loc_id = ach_loc_map.get((vendor, "en-US"))
        if not loc_id:
            print(f"! Skip achievement (not found in ASC): {vendor}")
            skipped_missing += 1
            continue

        existing_image_id = get_existing_image_id(token, "achievement", loc_id)
        if existing_image_id and not args.force:
            print(f"= Skip achievement (image already set): {vendor}")
            skipped_existing += 1
            continue
        if existing_image_id and args.force:
            print(f"- Delete existing achievement image: {vendor} ({existing_image_id})")
            if not args.dry_run:
                asc_delete(f"/gameCenterAchievementImages/{existing_image_id}", token)

        print(f"-> Upload achievement image: {vendor} ({m.file_path.name})")
        if not args.dry_run:
            create_and_upload_image(token, "achievement", loc_id, m.file_path)
        uploaded += 1

    # Upload leaderboard images
    for m in lb_imgs:
        vendor = parse_vendor_identifier_from_local_id(m.local_id)
        loc_id = lb_loc_map.get((vendor, "en-US"))
        if not loc_id:
            print(f"! Skip leaderboard (not found in ASC): {vendor}")
            skipped_missing += 1
            continue

        existing_image_id = get_existing_image_id(token, "leaderboard", loc_id)
        if existing_image_id and not args.force:
            print(f"= Skip leaderboard (image already set): {vendor}")
            skipped_existing += 1
            continue
        if existing_image_id and args.force:
            print(f"- Delete existing leaderboard image: {vendor} ({existing_image_id})")
            if not args.dry_run:
                asc_delete(f"/gameCenterLeaderboardImages/{existing_image_id}", token)

        print(f"-> Upload leaderboard image: {vendor} ({m.file_path.name})")
        if not args.dry_run:
            create_and_upload_image(token, "leaderboard", loc_id, m.file_path)
        uploaded += 1

    print(f"\nDone. queued={uploaded} skipped_existing={skipped_existing} skipped_missing={skipped_missing} dry_run={args.dry_run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
