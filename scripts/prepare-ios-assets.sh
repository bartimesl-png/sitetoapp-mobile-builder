#!/usr/bin/env bash
set -euo pipefail

# scripts/prepare-ios-assets.sh
# Crée les assets iOS manquants pour PartenaireFoyer afin que Xcode puisse compiler.
# - ios-native/PartenaireFoyer/Assets.xcassets/Contents.json
# - ios-native/PartenaireFoyer/Assets.xcassets/AppIcon.appiconset/Contents.json
# - ios-native/PartenaireFoyer/Assets.xcassets/AppIcon.appiconset/AppIcon.png

ASSETS_DIR="ios-native/PartenaireFoyer/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
PNG_PATH="$APPICON_DIR/AppIcon.png"

echo "Creating asset catalog at: $ASSETS_DIR"
mkdir -p "$APPICON_DIR"

# Contents.json for the asset catalog
cat > "$ASSETS_DIR/Contents.json" <<'JSON'
{
  "info": {
    "version": 1,
    "author": "xcode"
  }
}
JSON

# Contents.json for the AppIcon appiconset (only the App Store / marketing icon 1024x1024 is required for archiving)
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

# Créer AppIcon.png à 1024x1024. Le "logo PartenaireFoyer" est généré ci-dessous.
# Nous utilisons Python + Pillow (installé si nécessaire) pour garantir la taille exacte 1024x1024.

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 introuvable. Nécessaire pour générer l'icône."
  exit 1
fi

python3 - <<'PY'
from __future__ import annotations
import sys
try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:
    # Installer Pillow localement et réessayer
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "--upgrade", "pip"])
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "Pillow==10.1.0"])
    from PIL import Image, ImageDraw, ImageFont

# Chemin de sortie (repris depuis le shell via heredoc)
out = r"""$PNG_PATH"""

# Taille demandée
size = (1024, 1024)
# Couleurs du logo (on utilise une identité simple mais distincte)
bg_color = (10, 132, 255, 255)   # #0A84FF
fg_color = (255, 255, 255, 255)  # blanc
accent = (255, 204, 0, 255)      # un accent jaune

img = Image.new('RGBA', size, bg_color)
d = ImageDraw.Draw(img)

# Dessiner un cercle blanc arrondi au centre (comme un marqueur de logo)
r = int(size[0] * 0.38)
center = (size[0] // 2, size[1] // 2)
left_up = (center[0]-r, center[1]-r)
right_down = (center[0]+r, center[1]+r)
d.ellipse([left_up, right_down], fill=fg_color)

# Dessiner un petit carré accent au-dessus (pour un élément graphique simple)
sq = int(size[0] * 0.18)
sq_left_up = (center[0]-sq//2, center[1]-sq - 40)
sq_right_down = (center[0]+sq//2, center[1]-40)
d.rectangle([sq_left_up, sq_right_down], fill=accent)

# Écrire les initiales PF au centre
try:
    # Essayer une font système lisible
    font = ImageFont.truetype("/Library/Fonts/Arial Bold.ttf", 260)
except Exception:
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 260)
    except Exception:
        font = ImageFont.load_default()

text = "PF"
w, h = d.textsize(text, font=font)
d.text((center[0]-w//2, center[1]-h//2), text, font=font, fill=bg_color)

# Sauvegarder
img.save(out, format='PNG')
print("WROTE", out)
PY

# Vérifier que le PNG a bien été créé et mesure 1024x1024
if [ ! -f "$PNG_PATH" ]; then
  echo "Erreur: $PNG_PATH non créé"
  exit 1
fi

if command -v sips >/dev/null 2>&1; then
  WIDTH=$(sips -g pixelWidth "$PNG_PATH" | awk '/pixelWidth/ {print $2}')
  HEIGHT=$(sips -g pixelHeight "$PNG_PATH" | awk '/pixelHeight/ {print $2}')
else
  # fallback to python check
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

# succès
exit 0
