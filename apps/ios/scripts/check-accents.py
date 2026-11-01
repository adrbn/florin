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


# Le papier d'Éditorial et ses encres, recopiés d'`editorialBase`. Si la
# maquette change là-bas, ces valeurs doivent suivre — c'est le prix d'un
# contrôle qui ne compile pas le Swift.
PAPER = {"bg": (0xFFFFFF, 0x000000), "surface": (0xF2F2F4, 0x1C1C1E),
         "surface2": (0xEFEFF1, 0x2C2C2E)}
MIX = {"bg": (0.09, 0.10), "surface": (0.14, 0.16), "surface2": (0.16, 0.18)}
TEXT = (0x0A0A0A, 0xF5F5F7)
TEXT2 = (0x5C5C61, 0xA1A1A6)


def blend(a: int, b: int, amount: float) -> int:
    out = 0
    for shift in (16, 8, 0):
        lo, hi = (a >> shift) & 255, (b >> shift) & 255
        out |= round(lo + (hi - lo) * amount) << shift
    return out


def paper_floor(light: int, dark: int) -> float:
    """Le pire contraste texte/papier une fois la teinte posée."""
    worst = 99.0
    for face, (ink, tone) in enumerate(((light, 0), (dark, 1))):
        for name, grounds in PAPER.items():
            tinted = blend(grounds[tone], light if tone == 0 else dark, MIX[name][tone])
            for body in (TEXT, TEXT2):
                worst = min(worst, ratio(body[tone], tinted))
    return worst


# L'éventail d'`editorialSeries`, recopié de Palette.swift.
FAN = [(0, 1.00, 0.00), (19, 0.78, 0.70), (-19, 0.90, -0.60), (10, 0.64, 1.00),
       (-10, 0.96, -0.95), (24, 0.82, 0.32), (-24, 0.70, -0.28), (-11, 0.58, 0.92)]
SHAPE_FLOOR = 3.0


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


def spin(value: int, turn: float, scale: float, target: float) -> int:
    """Même dichotomie que `Tone.spin` : la luminance visée, pas la clarté."""
    hue, sat, _ = hsl(value)
    hue = (hue + turn) % 360
    sat = min(max(sat, 0.30), 0.55) * scale
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
    """Le pire contraste d'une encre catégorielle sur son propre papier."""
    worst = 99.0
    for face, ink in ((0, light), (1, dark)):
        base = light if face == 0 else dark
        paper = blend(PAPER["bg"][face], base, MIX["bg"][face])
        for turn, scale, shift in FAN:
            nominal, amplitude = (0.135, 0.60) if face == 0 else (0.44, 0.26)
            tone = spin(ink, turn, scale, nominal * (1 + shift * amplitude))
            worst = min(worst, ratio(tone, paper))
    return worst


def main() -> int:
    found = accents(PALETTE.read_text(encoding="utf-8"))
    if len(found) < 6:
        print(f"seulement {len(found)} accents lus — le format a changé ?")
        return 1

    failures = []
    for name, light, dark in found:
        on_white = ratio(light, 0xFFFFFF)
        white_on_dark = ratio(0xFFFFFF, dark)
        paper = paper_floor(light, dark)
        inks = series_floor(light, dark)
        worst = min(on_white, white_on_dark, paper)
        flag = "  " if worst >= FLOOR and inks >= SHAPE_FLOOR else "←"
        print(f"{flag} {name:11} clair/blanc {on_white:5.2f}"
              f"   blanc/sombre {white_on_dark:5.2f}   texte/papier {paper:5.2f}"
              f"   encres/papier {inks:5.2f}")
        if worst < FLOOR or inks < SHAPE_FLOOR:
            failures.append(name)

    if failures:
        print(f"\nsous {FLOOR}:1 — {', '.join(failures)}")
        return 1
    print(f"\n{len(found)} accents, tous au-dessus de {FLOOR}:1.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
