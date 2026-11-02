#!/bin/bash
#
# Le miroir Python face au vrai Swift.
#
# `check-accents.py` réécrit en Python ce que fait `Tone.dilute`, pour mesurer
# des contrastes sans lancer l'app. Un miroir qui s'écarte du Swift ne garde
# plus rien : celui-ci écrivait `% 360`, toujours positif en Python, pendant
# que Swift renvoyait un angle négatif pour une rotation vers l'arrière et
# tombait sur un rouge pur, saturation 1,00. Deux cartes de l'accueil sur
# quatre, et le garde-fou disait vert.
#
# Ici on compile le VRAI Palette.swift — amputé de sa seule dépendance UIKit,
# qui est en queue de fichier — et on compare les deux tables.
#
#     bash apps/ios/scripts/check-chord.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../Florin/Design/Palette.swift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cut=$(grep -n '^// MARK: - Encre vers couleur' "$src" | cut -d: -f1)
head -n $((cut - 1)) "$src" > "$work/Palette.swift"
cat >> "$work/Palette.swift" <<'SWIFT'
for accent in EdAccent.allCases {
    UserDefaults.standard.set(accent.rawValue, forKey: "florin.editorialAccent")
    UserDefaults.standard.set(EdInks.palette.rawValue, forKey: "florin.editorialInks")
    let inks = Palette.editorial.series.map { String(format: "%06X", $0.light) }
    print("\(accent)".padding(toLength: 11, withPad: " ", startingAt: 0),
          inks.joined(separator: " "))
}
SWIFT

swiftc -O -o "$work/run" "$work/Palette.swift"
"$work/run" > "$work/swift.txt"
python3 "$here/check-accents.py" --dump > "$work/python.txt"

if diff -u "$work/python.txt" "$work/swift.txt" > "$work/delta.txt"; then
    echo "miroir et Swift d'accord sur $(wc -l < "$work/swift.txt" | tr -d ' ') accents."
else
    echo "LE MIROIR A DÉRIVÉ — gauche Python, droite Swift :"
    cat "$work/delta.txt"
    exit 1
fi
