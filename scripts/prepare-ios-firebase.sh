#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${CM_BUILD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEST="${ROOT_DIR}/ios-native/PartenaireFoyer/GoogleService-Info.plist"

python3 - "$DEST" <<'PY'
import base64
import os
import plistlib
import sys

destination = sys.argv[1]
encoded = os.environ.get("GOOGLE_SERVICE_INFO_PLIST_BASE64", "")
raw_xml = os.environ.get("GOOGLE_SERVICE_INFO_PLIST", "")

try:
    if encoded:
        raw = base64.b64decode("".join(encoded.split()), validate=True)
    elif raw_xml.lstrip().startswith("<?xml") or raw_xml.lstrip().startswith("<plist"):
        raw = raw_xml.encode("utf-8")
    elif raw_xml and os.path.isfile(raw_xml):
        with open(raw_xml, "rb") as source:
            raw = source.read()
    else:
        raise ValueError(
            "Aucune configuration fournie. Définissez GOOGLE_SERVICE_INFO_PLIST_BASE64 "
            "ou GOOGLE_SERVICE_INFO_PLIST dans l’environnement Codemagic."
        )
    config = plistlib.loads(raw)
except Exception as error:
    raise SystemExit(f"Configuration Firebase iOS invalide: {error}")

expected_bundle = "com.partenairefoyer.app"
if config.get("BUNDLE_ID") != expected_bundle:
    raise SystemExit(
        f"BUNDLE_ID incorrect dans GoogleService-Info.plist: "
        f"{config.get('BUNDLE_ID')!r}, attendu {expected_bundle!r}"
    )

required = ("GOOGLE_APP_ID", "GCM_SENDER_ID", "API_KEY", "PROJECT_ID")
missing = [key for key in required if not config.get(key)]
if missing:
    raise SystemExit("Champs Firebase manquants: " + ", ".join(missing))

os.makedirs(os.path.dirname(destination), exist_ok=True)
with open(destination, "wb") as output:
    plistlib.dump(config, output, fmt=plistlib.FMT_XML)

print("GoogleService-Info.plist créé et validé pour " + expected_bundle)
PY
