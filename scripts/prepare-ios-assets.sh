#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${CM_BUILD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ASSETS_DIR="$ROOT_DIR/ios-native/PartenaireFoyer/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
ICON_PATH="$APPICON_DIR/AppIcon.png"
LOGO_URL="https://static.wixstatic.com/media/476a15_d601a17fe7c4406aac35fac85d309948~mv2.jpg"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Préparation des assets iOS dans : $ASSETS_DIR"
mkdir -p "$APPICON_DIR"

curl \
  --fail \
  --location \
  --retry 5 \
  --retry-delay 2 \
  --connect-timeout 20 \
  "$LOGO_URL" \
  --output "$TMP_DIR/logo-source.jpg"

test -s "$TMP_DIR/logo-source.jpg"

sips -s format png "$TMP_DIR/logo-source.jpg" \
  --out "$TMP_DIR/logo.png" >/dev/null

WIDTH="$(sips -g pixelWidth "$TMP_DIR/logo.png" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$TMP_DIR/logo.png" | awk '/pixelHeight/ {print $2}')"

if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
  echo "ERREUR : dimensions du logo impossibles à lire."
  exit 1
fi

if [ "$WIDTH" -lt "$HEIGHT" ]; then
  SIDE="$WIDTH"
else
  SIDE="$HEIGHT"
fi

sips \
  --cropToHeightWidth "$SIDE" "$SIDE" \
  "$TMP_DIR/logo.png" \
  --out "$TMP_DIR/logo-square.png" >/dev/null

sips \
  -z 1024 1024 \
  "$TMP_DIR/logo-square.png" \
  --out "$ICON_PATH" >/dev/null

cat > "$ASSETS_DIR/Contents.json" <<'JSON'
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON

cat > "$APPICON_DIR/Contents.json" <<'JSON'
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON

test -s "$ICON_PATH"

FINAL_WIDTH="$(sips -g pixelWidth "$ICON_PATH" | awk '/pixelWidth/ {print $2}')"
FINAL_HEIGHT="$(sips -g pixelHeight "$ICON_PATH" | awk '/pixelHeight/ {print $2}')"

if [ "$FINAL_WIDTH" != "1024" ] || [ "$FINAL_HEIGHT" != "1024" ]; then
  echo "ERREUR : icône obtenue en ${FINAL_WIDTH}x${FINAL_HEIGHT}, attendu 1024x1024."
  exit 1
fi

echo "OK : AppIcon.png créé et vérifié en 1024x1024."
