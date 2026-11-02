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


# Le papier d'Éditorial, recopié d'`editorialBase`. Il n'est plus teinté :
# l'accent tient les encres, le héros et l'alerte, pas la feuille.
PAPER = (0xFFFFFF, 0x000000)


# Les deux générateurs d'encres, recopiés de Palette.swift. Chacun des deux
# modes du réglage « encres » en tient un, et les deux descendent de l'accent :
# il faut donc surveiller les deux, pas celui qu'on a écrit en dernier.
#
# La rampe d'`editorialRamp` : rotation (nulle), saturation, luminance claire,
# luminance sombre.
RAMP = [(0, 1.00, 0.040, 0.100), (0, 0.97, 0.065, 0.145), (0, 0.94, 0.100, 0.200),
        (0, 0.90, 0.145, 0.265), (0, 0.84, 0.200, 0.340), (0, 0.77, 0.265, 0.420),
        (0, 0.69, 0.335, 0.510), (0, 0.60, 0.410, 0.600)]
INK_BAND = (0.30, 0.55)

# L'accord d'`editorialFan` : les relations de la roue, pas le voisinage.
FAN = [(0, 1.00, 0.120, 0.42), (150, 0.94, 0.165, 0.50), (-150, 1.00, 0.098, 0.38),
       (30, 0.90, 0.190, 0.54), (180, 0.96, 0.140, 0.45), (-30, 1.00, 0.112, 0.40),
       (90, 0.92, 0.175, 0.52), (-90, 0.98, 0.150, 0.47)]
CHORD_BAND = (0.46, 0.78)

SHAPE_FLOOR = 1.5
# Deux encres d'un même accord doivent se distinguer l'une de l'autre, pas
# seulement du papier : c'est tout l'objet du mode. Mesuré en distance de
# teinte, parce que c'est elle qui sépare les rangs ici.
CHORD_SPREAD = 25.0


def hsl(value: int) -> tuple[float, float, float]:
    r, g, b = ((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255
    high, low = max(r, g, b), min(r, g, b)
    light = (high + low) / 2
    if high == low:
        return 0.0, 0.0, light
    span = high - low
    sat = span / (2 - high - low) if light > 0.5 else span / (high + low)
    if high == r:
        hue = (g - b) / span + (6 if g < b else 0)
    elif high == g:
        hue = (b - r) / span + 2
    else:
        hue = (r - g) / span + 4
    return hue * 60, sat, light


def pack(hue: float, sat: float, light: float) -> int:
    chroma = (1 - abs(2 * light - 1)) * sat
    sector = hue / 60
    second = chroma * (1 - abs(sector % 2 - 1))
    lift = light - chroma / 2
    table = [(chroma, second, 0), (second, chroma, 0), (0, chroma, second),
             (0, second, chroma), (second, 0, chroma), (chroma, 0, second)]
    out = 0
    for shift, part in zip((16, 8, 0), table[int(sector) % 6]):
        out |= round(min(max(part + lift, 0), 1) * 255) << shift
    return out


def dilute(value: int, turn: float, scale: float, target: float,
            band: tuple[float, float] = INK_BAND) -> int:
    """Même dichotomie que `Tone.dilute` : la luminance visée, pas la clarté."""
    hue, sat, _ = hsl(value)
    hue = (hue + turn) % 360
    sat = min(max(sat, band[0]), band[1]) * scale
    low, high, packed = 0.0, 1.0, 0
    for _ in range(14):
        middle = (low + high) / 2
        packed = pack(hue, sat, middle)
        if luminance(packed) < target:
            low = middle
        else:
            high = middle
    return packed


def series_floor(light: int, dark: int) -> float:
    """Le contraste de l'encre la plus pâle sur son propre papier.

    Un dégradé finit forcément près du papier : c'est le bout clair qui
    décide, et c'est lui qu'on surveille. En dessous de 1,5:1 la carte la
    plus pâle se confondrait avec la feuille.

    Les deux modes passent ici. L'éventail est le moins exposé des deux — son
    rang le plus doux vise 0,216 là où la rampe monte à 0,410 — mais rien ne
    garantit qu'il le reste, et c'est tout l'intérêt de le mesurer.
    """
    worst = 99.0
    for face, ink in ((0, light), (1, dark)):
        paper = PAPER[face]
        for table, band in ((RAMP, INK_BAND), (FAN, CHORD_BAND)):
            for turn, scale, pale, deep in table:
                tone = dilute(ink, turn, scale, pale if face == 0 else deep, band)
                worst = min(worst, ratio(tone, paper))
    return worst


def chord_spread(light: int, dark: int) -> float:
    """La plus petite distance de teinte entre deux encres de l'accord.

    Deux essais ont tourné la teinte de ±64° puis de ±24° seulement : les
    huit rangs tombaient dans la même famille, et une légende de huit
    briques ne se lit pas. L'accord couvre maintenant le tour de la roue, et
    c'est cette mesure-là qui l'empêche de se refermer.
    """
    worst = 360.0
    for face, ink in ((0, light), (1, dark)):
        hues = [hsl(dilute(ink, turn, scale, pale if face == 0 else deep, CHORD_BAND))[0]
                for turn, scale, pale, deep in FAN]
        for i, a in enumerate(hues):
            for b in hues[i + 1:]:
                gap = abs(a - b) % 360
                worst = min(worst, min(gap, 360 - gap))
    return worst


def dump() -> int:
    """Les huit encres de l'accord, pour chaque accent, en clair.

    Sert à `check-chord.sh`, qui compare cette table à celle que le VRAI
    Palette.swift imprime une fois compilé. Un miroir qui diverge du Swift
    ne garde rien : celui-ci écrivait `% 360`, toujours positif en Python,
    quand Swift renvoyait un angle négatif et sortait un rouge pur.
    """
    for name, light, _ in accents(PALETTE.read_text(encoding="utf-8")):
        inks = " ".join(f"{dilute(light, turn, scale, pale, CHORD_BAND):06X}"
                        for turn, scale, pale, _ in FAN)
        print(f"{name:11} {inks}")
    return 0


def main() -> int:
    if "--dump" in sys.argv:
        return dump()
    found = accents(PALETTE.read_text(encoding="utf-8"))
    if len(found) < 6:
        print(f"seulement {len(found)} accents lus — le format a changé ?")
        return 1

    failures = []
    for name, light, dark in found:
        on_white = ratio(light, 0xFFFFFF)
        white_on_dark = ratio(0xFFFFFF, dark)
        inks = series_floor(light, dark)
        spread = chord_spread(light, dark)
        worst = min(on_white, white_on_dark)
        ok = worst >= FLOOR and inks >= SHAPE_FLOOR and spread >= CHORD_SPREAD
        print(f"{'  ' if ok else '←'} {name:11} clair/blanc {on_white:5.2f}"
              f"   blanc/sombre {white_on_dark:5.2f}   lavis/papier {inks:5.2f}"
              f"   accord {spread:5.1f}°")
        if not ok:
            failures.append(name)

    if failures:
        print(f"\nsous {FLOOR}:1 — {', '.join(failures)}")
        return 1
    print(f"\n{len(found)} accents, tous au-dessus de {FLOOR}:1.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
