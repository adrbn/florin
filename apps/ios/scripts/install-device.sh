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
#
# Et on EXPORTE plutôt que de poser le produit de la compilation.
#
# Un build signé « Apple Development » n'est pas autorisé par son profil : au
# premier lancement, iOS appelle Apple pour vérifier que le développeur est
# fiable, et sans réseau il refuse d'ouvrir l'app — « Impossible de vérifier
# l'app », un bouton Annuler, rien d'autre. Dans le métro ou en voyage, un
# build fraîchement posé est donc inutilisable.
#
# Une signature Ad Hoc (`release-testing`) porte la liste des appareils
# autorisés dans le profil lui-même : il n'y a rien à vérifier en ligne, et
# l'app s'ouvre hors réseau comme n'importe quelle autre.
DD="${DERIVED_DATA:-/tmp/florin-dd-rel}"
if [ -z "$APP" ]; then
  cd "$(dirname "$0")/.."
  # Le numéro de build vit dans project.yml, pas dans le .xcodeproj.
  #
  # Sans cette ligne, le projet généré garde l'ancien numéro : le script
  # compile, exporte et annonce « installé » un build qui porte le numéro
  # d'avant. On relit la version sur le tel, on la voit inchangée, et on
  # cherche la panne dans le code au lieu de la chercher ici.
  command -v xcodegen >/dev/null && xcodegen generate --quiet
  ARCH="$DD/Florin.xcarchive"
  OUT="$DD/export"
  rm -rf "$ARCH" "$OUT"
  mkdir -p "$OUT"
  cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>release-testing</string>
  <key>teamID</key><string>2TWQF4T93E</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST
  xcodebuild -project Florin.xcodeproj -scheme Florin -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCH" \
    -allowProvisioningUpdates archive -quiet || exit 1
  xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
    >/dev/null || exit 1
  rm -rf "$OUT/unz" && mkdir -p "$OUT/unz"
  unzip -q "$OUT/Florin.ipa" -d "$OUT/unz"
  APP="$OUT/unz/Payload/Florin.app"
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
