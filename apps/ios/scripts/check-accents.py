#!/usr/bin/env python3
"""Le plancher de contraste des accents d'Éditorial.

Un accent sert à deux choses incompatibles : il s'écrit sur le fond, et il
sert de fond à du blanc. Les deux lectures doivent tenir, et c'est le genre
de chose qu'on ne voit pas en ajoutant la dix-neuvième pastille — elle a
l'air jolie dans la grille et devient illisible sur l'écran.

    python3 apps/ios/scripts/check-accents.py

Le plancher est 4,1:1, mesuré sur l'ocre du jeu d'origine. Pas 4,5 : deux
des six accents historiques sont en dessous, et les descendre ici ferait
échouer un état qu'on a décidé de garder.
"""
import pathlib
import re
import sys

FLOOR = 4.1
PALETTE = pathlib.Path(__file__).resolve().parents[1] / "Florin/Design/Palette.swift"


def luminance(value: int) -> float:
    def channel(c: int) -> float:
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (value >> 16) & 255, (value >> 8) & 255, value & 255
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a: int, b: int) -> float:
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def accents(source: str) -> list[tuple[str, int, int]]:
    """Les tons de `EdAccent.tone`, et eux seuls."""
    block = source.split("enum EdAccent", 1)[1].split("\n}", 1)[0]
    pattern = r"case \.(\w+): return Tone\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)"
    return [(n, int(li, 16), int(da, 16)) for n, li, da in re.findall(pattern, block)]


def main() -> int:
    found = accents(PALETTE.read_text(encoding="utf-8"))
    if len(found) < 6:
        print(f"seulement {len(found)} accents lus — le format a changé ?")
        return 1

    failures = []
    for name, light, dark in found:
        on_white = ratio(light, 0xFFFFFF)
        white_on_dark = ratio(0xFFFFFF, dark)
        worst = min(on_white, white_on_dark)
        flag = "  " if worst >= FLOOR else "←"
        print(f"{flag} {name:11} clair/blanc {on_white:5.2f}   blanc/sombre {white_on_dark:5.2f}")
        if worst < FLOOR:
            failures.append(name)

    if failures:
        print(f"\nsous {FLOOR}:1 — {', '.join(failures)}")
        return 1
    print(f"\n{len(found)} accents, tous au-dessus de {FLOOR}:1.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
