#!/usr/bin/env python3
"""
Import Game Center achievements + localizations from a .gamekit JSON into App Store Connect.

Prereqs:
  pip install requests pyjwt cryptography

Env vars (recommended):
  ASC_ISSUER_ID           -> Your App Store Connect API Issuer ID
  ASC_KEY_ID              -> Your App Store Connect API Key ID
  ASC_PRIVATE_KEY_PATH    -> Path to the .p8 private key

Args:
  --bundle-id com.your.bundleid
  --json /path/to/GameCenterResources.gamekit/gameCenterResources.json
  [--create-release]  Attach each new achievement to the current Game Center detail via a release

Example:
  export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  export ASC_KEY_ID="ABC123DEF4"
  export ASC_PRIVATE_KEY_PATH="$HOME/Keys/AuthKey_ABC123DEF4.p8"

  python3 scripts/import_achievements.py \
    --bundle-id "Jorsh.WorkingOut" \
    --json "GameCenterResources.gamekit/gameCenterResources.json" \
    --create-release
"""

import argparse
import json
import os
import sys
import time
from typing import Dict, Any, List, Tuple

import jwt  # PyJWT
import requests

ASC_API = "https://api.appstoreconnect.apple.com/v1"


def make_jwt(issuer_id: str, key_id: str, p8_path: str) -> str:
    with open(p8_path, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "exp": now + 1200,  # 20 minutes
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": key_id, "alg": "ES256", "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def asc_session(token: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    return s


def die(msg: str):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def get_app_id(sess: requests.Session, bundle_id: str) -> str:
    r = sess.get(f"{ASC_API}/apps", params={"filter[bundleId]": bundle_id})
    try:
        r.raise_for_status()
    except requests.HTTPError:
        print(r.text, file=sys.stderr)
        raise
    data = r.json().get("data", [])
    if not data:
        die(f"No app found for bundle id {bundle_id}")
    return data[0]["id"]


def get_or_create_game_center_detail(sess: requests.Session, app_id: str) -> str:
    # Try to read the app's Game Center Detail relation first
    rel = sess.get(f"{ASC_API}/apps/{app_id}/relationships/gameCenterDetail")
    try:
        rel.raise_for_status()
    except requests.HTTPError:
        print(rel.text, file=sys.stderr)
        raise
    rel_data = rel.json().get("data")
    if rel_data:
        return rel_data["id"]

    # Create one if missing (enable Game Center for app)
    payload = {
        "data": {
            "type": "gameCenterDetails",
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            },
        }
    }
    r = sess.post(f"{ASC_API}/gameCenterDetails", json=payload)
    try:
        r.raise_for_status()
    except requests.HTTPError:
        print(r.text, file=sys.stderr)
        raise
    return r.json()["data"]["id"]


def list_existing_achievements(sess: requests.Session, game_center_detail_id: str) -> Dict[str, str]:
    # Attempt via relationship endpoint first
    url = f"{ASC_API}/gameCenterDetails/{game_center_detail_id}/gameCenterAchievements"
    existing: Dict[str, str] = {}
    while url:
        r = sess.get(url)
        try:
            r.raise_for_status()
        except requests.HTTPError:
            # Fallback to filter endpoint
            r = sess.get(f"{ASC_API}/gameCenterAchievements", params={"filter[gameCenterDetail]": game_center_detail_id})
            r.raise_for_status()
        j = r.json()
        for item in j.get("data", []):
            attrs = item.get("attributes", {})
            ach_id = attrs.get("vendorIdentifier")
            if ach_id:
                existing[ach_id] = item["id"]
        url = j.get("links", {}).get("next")
    return existing


def create_achievement(sess: requests.Session, game_center_detail_id: str,
                       reference_name: str, vendor_identifier: str,
                       points: int, repeatable: bool,
                       show_before: bool) -> str:
    payload = {
        "data": {
            "type": "gameCenterAchievements",
            "attributes": {
                "referenceName": reference_name,
                "vendorIdentifier": vendor_identifier,
                "points": points,
                "repeatable": repeatable,
                "showBeforeEarned": show_before,
            },
            "relationships": {
                "gameCenterDetail": {
                    "data": {"type": "gameCenterDetails", "id": game_center_detail_id}
                }
            },
        }
    }
    r = sess.post(f"{ASC_API}/gameCenterAchievements", json=payload)
    try:
        r.raise_for_status()
    except requests.HTTPError:
        print(r.text, file=sys.stderr)
        raise
    return r.json()["data"]["id"]


def create_localization(sess: requests.Session, achievement_api_id: str,
                        locale: str, display_name: str,
                        before_desc: str, after_desc: str) -> str:
    payload = {
        "data": {
            "type": "gameCenterAchievementLocalizations",
            "attributes": {
                "locale": locale,
                "name": display_name,
                "beforeEarnedDescription": before_desc,
                "afterEarnedDescription": after_desc,
            },
            "relationships": {
                "gameCenterAchievement": {
                    "data": {"type": "gameCenterAchievements", "id": achievement_api_id}
                }
            },
        }
    }
    r = sess.post(f"{ASC_API}/gameCenterAchievementLocalizations", json=payload)
    try:
        r.raise_for_status()
    except requests.HTTPError:
        print(r.text, file=sys.stderr)
        raise
    return r.json()["data"]["id"]


def create_release(sess: requests.Session, game_center_detail_id: str, achievement_api_id: str) -> str:
    payload = {
        "data": {
            "type": "gameCenterAchievementReleases",
            "relationships": {
                "gameCenterAchievement": {
                    "data": {"type": "gameCenterAchievements", "id": achievement_api_id}
                },
                "gameCenterDetail": {
                    "data": {"type": "gameCenterDetails", "id": game_center_detail_id}
                },
            },
        }
    }
    r = sess.post(f"{ASC_API}/gameCenterAchievementReleases", json=payload)
    try:
        r.raise_for_status()
    except requests.HTTPError:
        print(r.text, file=sys.stderr)
        raise
    return r.json()["data"]["id"]


def load_gamekit_json(path: str) -> Dict[str, Any]:
    with open(path, "r") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--json", required=True, help="Path to gameCenterResources.json (inside .gamekit)")
    ap.add_argument("--create-release", action="store_true", help="Also create releases for each achievement")
    args = ap.parse_args()

    issuer_id = os.getenv("ASC_ISSUER_ID")
    key_id = os.getenv("ASC_KEY_ID")
    p8_path = os.getenv("ASC_PRIVATE_KEY_PATH")
    if not (issuer_id and key_id and p8_path and os.path.exists(p8_path)):
        die("Missing ASC_ISSUER_ID / ASC_KEY_ID / ASC_PRIVATE_KEY_PATH env vars or .p8 file")

    token = make_jwt(issuer_id, key_id, p8_path)
    sess = asc_session(token)

    # 1) App + Game Center Detail
    app_id = get_app_id(sess, args.bundle_id)
    gc_detail_id = get_or_create_game_center_detail(sess, app_id)

    # 2) Parse your .gamekit JSON
    j = load_gamekit_json(args.json)
    res = j.get("resources", {}) if isinstance(j.get("resources"), dict) else {}
    achievements = j.get("achievements", []) or res.get("achievements", [])
    localizations_map = j.get("achievementLocalizations", {}) or res.get("achievementLocalizations", {})

    if not achievements:
        die("No achievements in JSON.")

    # 3) Skip already-existing achievements by achievementId
    existing = list_existing_achievements(sess, gc_detail_id)

    created: List[Tuple[str, str, str]] = []
    for ach in achievements:
        ref_name = ach.get("referenceName") or ach.get("name") or "Achievement"
        ach_id = ach.get("vendorIdentifier") or ach.get("achievementId")
        if not ach_id:
            die(f"Achievement missing vendorIdentifier/achievementId: {ref_name}")

        if ach_id in existing:
            print(f"= Skipping existing achievement {ach_id} ({ref_name})")
            api_id = existing[ach_id]
        else:
            api_id = create_achievement(
                sess, gc_detail_id,
                reference_name=ref_name,
                vendor_identifier=ach_id,
                points=int(ach.get("points", 10)),
                repeatable=bool(ach.get("repeatable", False)),
                show_before=bool(ach.get("showBeforeEarned", True)),
            )
            print(f"+ Created achievement {ach_id} ({ref_name}) -> {api_id}")
        created.append((ach_id, api_id, ref_name))

        # 4) Create localizations, if any
        locs = localizations_map.get(ach_id, [])
        for loc in locs:
            try:
                locale = loc["locale"]
                name = loc.get("name") or loc.get("displayName") or ref_name
                before_desc = loc.get("beforeEarnedDescription", "")
                after_desc = loc.get("afterEarnedDescription", "")
            except KeyError as e:
                die(f"Localization missing required field: {e}")
            loc_id = create_localization(sess, api_id, locale, name, before_desc, after_desc)
            print(f"  + Localization [{locale}] -> {loc_id}")

        # 5) Optionally, create a release to hook the achievement to the GC detail now
        if args.create_release:
            rel_id = create_release(sess, gc_detail_id, api_id)
            print(f"  + Release -> {rel_id}")

    print("\nDone.")
    print(f"Processed {len(created)} achievements.")
    print("If not already, associate your Game Center group with this app version in App Store Connect.")


if __name__ == "__main__":
    main()
