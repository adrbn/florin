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

# Sans chemin donné, on construit.
#
# Le script se contentait de ramasser le premier Florin.app traînant dans
# DerivedData. Il annonçait « installé » en posant un build de la veille, et
# on cherchait ensuite pourquoi le correctif n'avait rien changé à l'écran.
# Un produit périmé ressemble trait pour trait à un produit à jour.
DD="${DERIVED_DATA:-/tmp/florin-dd-rel}"
if [ -z "$APP" ]; then
  cd "$(dirname "$0")/.."
  xcodebuild -project Florin.xcodeproj -scheme Florin -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
    -allowProvisioningUpdates build -quiet || exit 1
  APP=$(find "$DD/Build/Products" -maxdepth 3 -name "Florin.app" 2>/dev/null | head -1)
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

# Un téléphone verrouillé refuse de lancer quoi que ce soit, et il le reste
# le temps qu'on le reprenne en main. On insiste quatre minutes plutôt que
# vingt-cinq secondes : l'installation sans lancement est une panne complète
# de l'automatisation, pas un détail de confort.
ATTEMPTS="${FLORIN_LAUNCH_ATTEMPTS:-24}"
for attempt in $(seq 1 "$ATTEMPTS"); do
  if xcrun devicectl device process launch \
      --device "$DEVICE" --no-activate --terminate-existing "$BUNDLE" >/dev/null 2>&1; then
    echo "lancé une fois — les raccourcis retrouvent l'action Florin"
    exit 0
  fi
  if [ $((attempt % 6)) = 0 ]; then
    echo "en attente du téléphone (déverrouille-le) — essai $attempt/$ATTEMPTS" >&2
  fi
  sleep 10
done

echo "" >&2
echo "ATTENTION : le build est installé mais n'a jamais tourné." >&2
echo "Tant que Florin n'est pas ouvert une fois, l'automatisation Apple Pay" >&2
echo "n'enregistre RIEN, sans erreur ni trace. Ouvre l'app, ou relance :" >&2
echo "  xcrun devicectl device process launch --device $DEVICE \\" >&2
echo "    --no-activate --terminate-existing $BUNDLE" >&2
exit 1
