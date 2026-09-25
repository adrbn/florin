#!/usr/bin/env bash
#
# Pose un build sur l'iPhone, puis le lance une fois.
#
# Le lancement n'est pas une politesse : remplacer le bundle d'une app
# invalide l'enregistrement de ses App Intents auprès de Raccourcis, et tant
# que l'app n'a pas tourné une fois, une automatisation qui l'appelle ne
# lance rien du tout — donc ni journal, ni notification d'échec, rien à
# constater. Un paiement Apple Pay passe alors à la trappe en silence.
#
# `--no-activate` fait tourner l'app sans passer devant ce que son
# propriétaire est en train de faire.
#
# Usage: scripts/install-device.sh [chemin/vers/Florin.app]
set -euo pipefail

DEVICE="${FLORIN_DEVICE:-EA0252BB-60FE-5E8D-8CAD-CA836A1005B0}"
BUNDLE="com.adrbn.florin"
APP="${1:-}"

if [ -z "$APP" ]; then
  APP=$(find "${DERIVED_DATA:-/tmp/florin-dd-rel}/Build/Products" -maxdepth 3 -name "Florin.app" 2>/dev/null | head -1)
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "Florin.app introuvable — passe son chemin en argument." >&2
  exit 1
fi

# L'appareil refuse parfois une installation pendant quelques secondes
# (4016, « unavailable »). C'est transitoire : on réessaie.
for attempt in $(seq 1 10); do
  if xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -q "installationURL"; then
    echo "installé (essai $attempt)"
    break
  fi
  if [ "$attempt" = 10 ]; then
    echo "installation refusée dix fois de suite." >&2
    exit 1
  fi
  sleep 8
done

for attempt in $(seq 1 5); do
  if xcrun devicectl device process launch \
      --device "$DEVICE" --no-activate --terminate-existing "$BUNDLE" >/dev/null 2>&1; then
    echo "lancé une fois — les raccourcis retrouvent l'action Florin"
    exit 0
  fi
  sleep 5
done

echo "installé, mais le lancement a échoué : ouvre l'app une fois à la main," >&2
echo "sinon l'automatisation Apple Pay n'enregistrera rien." >&2
exit 1
