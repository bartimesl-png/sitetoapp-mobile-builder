#!/usr/bin/env bash
set -euo pipefail

# scripts/prepare-ios-assets.sh
# Prépare les assets iOS manquants pour PartenaireFoyer avant le build Xcode.
# - Crée ios-native/PartenaireFoyer/Assets.xcassets et AppIcon.appiconset
# - Télécharge le logo si PARTENAIREFOYER_LOGO_URL est défini, ou utilise PARTENAIREFOYER_LOGO_PATH
# - Génère AppIcon.png à 1024x1024 (utilisé comme ios-marketing App Icon)
# Ne modifie pas ASSETCATALOG_COMPILER_APPICON_NAME (doit rester AppIcon).

set -o pipefail

CM_BUILD_DIR="${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ASSETS_DIR="$CM_BUILD_DIR/ios-native/PartenaireFoyer/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
PNG_PATH="$APPICON_DIR/AppIcon.png"
TMP_SRC="$APPICON_DIR/.src_logo_tmp"

echo "Preparing iOS asset catalog at: $ASSETS_DIR"
mkdir -p "$APPICON_DIR"

cat > "$ASSETS_DIR/Contents.json" <<'JSON'
{
  "info": {
    "version": 1,
    "author": "xcode"
  }
}
JSON

cat > "$APPICON_DIR/Contents.json" <<'JSON'
{
  "images": [
    {
      "idiom": "ios-marketing",
      "filename": "AppIcon.png",
      "size": "1024x1024",
      "scale": "1x"
    }
  ],
  "info": {
    "version": 1,
    "author": "xcode"
  }
}
JSON

# Determine source logo
if [ -n "${PARTENAIREFOYER_LOGO_URL:-}" ]; then
  echo "Downloading logo from PARTENAIREFOYER_LOGO_URL=$PARTENAIREFOYER_LOGO_URL"
  # Use curl if available, otherwise wget
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$PARTENAIREFOYER_LOGO_URL" -o "$TMP_SRC" || { echo "Erreur: téléchargement échoué"; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_SRC" "$PARTENAIREFOYER_LOGO_URL" || { echo "Erreur: téléchargement échoué"; exit 1; }
  else
    echo "Erreur: ni curl ni wget disponibles pour télécharger le logo"
    exit 1
  fi
elif [ -n "${PARTENAIREFOYER_LOGO_PATH:-}" ] && [ -f "$PARTENAIREFOYER_LOGO_PATH" ]; then
  echo "Using local logo at PARTENAIREFOYER_LOGO_PATH=$PARTENAIREFOYER_LOGO_PATH"
  cp "$PARTENAIREFOYER_LOGO_PATH" "$TMP_SRC"
else
  echo "Erreur: aucun logo fourni. Définissez PARTENAIREFOYER_LOGO_URL (préféré) ou PARTENAIREFOYER_LOGO_PATH"
  exit 1
fi

# Ensure python3 available
if ! command -v python3 >/dev/null 2>&1; then
  echo "Erreur: python3 requis pour redimensionner l'image"
  exit 1
fi

# Use Python + Pillow to open and resize to 1024x1024
python3 - <<PY
from PIL import Image
import sys
src = r"$TMP_SRC"
dst = r"$PNG_PATH"

# Open image; if it's SVG this will fail (Pillow doesn't support SVG). We expect a raster image (png/jpg).
img = Image.open(src).convert('RGBA')
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(dst, format='PNG', optimize=True)
print('WROTE', dst)
PY

# cleanup tmp
rm -f "$TMP_SRC"

# Verify dimensions
if command -v sips >/dev/null 2>&1; then
  WIDTH=$(sips -g pixelWidth "$PNG_PATH" | awk '/pixelWidth/ {print $2}')
  HEIGHT=$(sips -g pixelHeight "$PNG_PATH" | awk '/pixelHeight/ {print $2}')
else
  read WIDTH HEIGHT <<EOF
$(python3 - <<'PY'
from PIL import Image
img = Image.open(r"$PNG_PATH")
print(img.width, img.height)
PY
)
EOF
fi

if [ "$WIDTH" -ne 1024 ] || [ "$HEIGHT" -ne 1024 ]; then
  echo "Erreur: dimensions invalides pour $PNG_PATH (trouvé ${WIDTH}x${HEIGHT}, attendu 1024x1024)"
  exit 1
fi

echo "Created AppIcon at $PNG_PATH with dimensions ${WIDTH}x${HEIGHT}"
exit 0
