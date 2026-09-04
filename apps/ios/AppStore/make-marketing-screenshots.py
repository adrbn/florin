#!/usr/bin/env python3
"""
Marketing-grade App Store screenshots for Florin.

Style: consistent brand gradient across all five (the way one company's
screenshot set reads as one story, not five different apps), a two-weight
headline that sells the outcome rather than describes the screen, the real
screenshot inset in an authentic device frame, and a one-line caption. The
device frame and its screen-cutout offset are Apple's own, via fastlane's
frameit asset pack — not redrawn by hand.
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path("/Users/adrien/vibecoding/claudecode_repos/perso/florin/apps/ios/AppStore")
RAW = ROOT / "screenshots-6.9"
# The app's own UI, captured with the simulator set to English. A French
# screenshot under an English headline is the tell that the listing was
# translated but the product was not, so the locales that read left-to-right
# in English get their own captures rather than sharing the French ones.
RAW_EN = ROOT / "screenshots-6.9-en"
# Which capture set each locale draws from. The four non-French, non-English
# locales have no localized build to capture from yet, so they take the
# English UI — closer to their reader than French is, and honest about being
# a stand-in until those translations exist in the app itself.
RAW_BY_LOCALE = {
    "fr-FR": RAW,
    "en-US": RAW_EN,
    "it": RAW_EN,
    "nl-NL": RAW_EN,
    "es-ES": RAW_EN,
    "de-DE": RAW_EN,
}
OUT = ROOT / "screenshots-6.9-marketing"
OUT.mkdir(exist_ok=True)

FRAME_DIR = Path.home() / ".fastlane/frameit/latest"
FRAME_PATH = FRAME_DIR / "Apple iPhone 17 Pro Max Deep Blue.png"
OFFSETS = json.loads((FRAME_DIR / "offsets.json").read_text())["portrait"]["iPhone 17 Pro Max"]

FONT_DIR = Path("/Library/Fonts")
def font(weight, size):
    return ImageFont.truetype(str(FONT_DIR / f"SF-Pro-Display-{weight}.otf"), size)

W, H = 1320, 2868

# Florin's own accent, dark-mode reading (Design/Theme.swift): #4B4FD6 light,
# #8C8CF7 dark. The gradient runs deep indigo to near-black, the same
# direction the app's own backdrops already fall in.
TOP = (43, 26, 110)      # deep violet
MID = (23, 15, 66)
BOTTOM = (11, 10, 20)    # near the app's own Florin.surface dark

WHITE = (255, 255, 255)
DIM = (200, 197, 235)

# Short fragments, full stops instead of commas or dashes — the register
# Apple's own App Store copy uses ("All your passes. All in one place.").
#
# Which capture set backs each locale is decided by RAW_BY_LOCALE above;
# only the marketing overlay (headline, badge, caption) lives here.
BG_DIR = ROOT / "backgrounds"
SCREEN_KEYS = ["apercu", "plan", "calendrier", "comptes", "activite"]
SCREEN_SRC = {
    "apercu": "1-apercu.png",
    "plan": "2-plan.png",
    "calendrier": "3-calendrier.png",
    "comptes": "4-comptes.png",
    "activite": "5-activite.png",
}

LOCALES = {
    "fr-FR": {
        "apercu": dict(head_light="Votre argent.", head_bold="Enfin clair.",
                        badge="100% LOCAL", caption="Rien n'est envoyé. Nulle part."),
        "plan": dict(head_light="Vous répartissez.", head_bold="L'app suit.",
                      badge=None, caption="Un plan pour le mois. Avant qu'il commence."),
        "calendrier": dict(head_light="Chaque euro.", head_bold="Chaque jour.",
                            badge=None, caption="Un carré par jour. Rien d'oublié."),
        "comptes": dict(head_light="Ce que vous possédez.", head_bold="Ce que vous devez.",
                         badge=None, caption="Courant. Épargne. Titres. Prêts."),
        "activite": dict(head_light="Chaque dépense.", head_bold="Classée en un geste.",
                          badge=None, caption="Rien ne vous échappe."),
    },
    "en-US": {
        "apercu": dict(head_light="Your money.", head_bold="Finally clear.",
                        badge="100% LOCAL", caption="Nothing is sent. Nowhere."),
        "plan": dict(head_light="You assign it.", head_bold="The app follows.",
                      badge=None, caption="A plan for the month. Before it starts."),
        "calendrier": dict(head_light="Every euro.", head_bold="Every day.",
                            badge=None, caption="One square a day. Nothing forgotten."),
        "comptes": dict(head_light="What you own.", head_bold="What you owe.",
                         badge=None, caption="Checking. Savings. Investments. Loans."),
        "activite": dict(head_light="Every expense.", head_bold="Filed in one tap.",
                          badge=None, caption="Nothing slips through."),
    },
    "it": {
        "apercu": dict(head_light="I tuoi soldi.", head_bold="Finalmente chiari.",
                        badge="100% LOCALE", caption="Niente viene inviato. Da nessuna parte."),
        "plan": dict(head_light="Tu assegni.", head_bold="L'app segue.",
                      badge=None, caption="Un piano per il mese. Prima che inizi."),
        "calendrier": dict(head_light="Ogni euro.", head_bold="Ogni giorno.",
                            badge=None, caption="Un quadrato al giorno. Niente dimenticato."),
        "comptes": dict(head_light="Quello che possiedi.", head_bold="Quello che devi.",
                         badge=None, caption="Conto corrente. Risparmi. Investimenti. Prestiti."),
        "activite": dict(head_light="Ogni spesa.", head_bold="Classificata in un gesto.",
                          badge=None, caption="Niente ti sfugge."),
    },
    "nl-NL": {
        "apercu": dict(head_light="Jouw geld.", head_bold="Eindelijk helder.",
                        badge="100% LOKAAL", caption="Niets wordt verzonden. Nergens naartoe."),
        "plan": dict(head_light="Jij verdeelt.", head_bold="De app volgt.",
                      badge=None, caption="Een plan voor de maand. Voor die begint."),
        "calendrier": dict(head_light="Elke euro.", head_bold="Elke dag.",
                            badge=None, caption="Eén vakje per dag. Niets vergeten."),
        "comptes": dict(head_light="Wat je bezit.", head_bold="Wat je verschuldigd bent.",
                         badge=None, caption="Betaalrekening. Sparen. Beleggingen. Leningen."),
        "activite": dict(head_light="Elke uitgave.", head_bold="Gecategoriseerd in één tik.",
                          badge=None, caption="Niets ontsnapt je."),
    },
    "es-ES": {
        "apercu": dict(head_light="Tu dinero.", head_bold="Por fin claro.",
                        badge="100% LOCAL", caption="Nada se envía. A ningún sitio."),
        "plan": dict(head_light="Tú lo repartes.", head_bold="La app lo sigue.",
                      badge=None, caption="Un plan para el mes. Antes de que empiece."),
        "calendrier": dict(head_light="Cada euro.", head_bold="Cada día.",
                            badge=None, caption="Un cuadro por día. Nada se olvida."),
        "comptes": dict(head_light="Lo que tienes.", head_bold="Lo que debes.",
                         badge=None, caption="Corriente. Ahorros. Inversiones. Préstamos."),
        "activite": dict(head_light="Cada gasto.", head_bold="Clasificado en un gesto.",
                          badge=None, caption="Nada se te escapa."),
    },
    "de-DE": {
        "apercu": dict(head_light="Dein Geld.", head_bold="Endlich klar.",
                        badge="100% LOKAL", caption="Nichts wird gesendet. Nirgendwohin."),
        "plan": dict(head_light="Du verteilst.", head_bold="Die App folgt.",
                      badge=None, caption="Ein Plan für den Monat. Bevor er beginnt."),
        "calendrier": dict(head_light="Jeder Euro.", head_bold="Jeder Tag.",
                            badge=None, caption="Ein Feld pro Tag. Nichts vergessen."),
        "comptes": dict(head_light="Was du besitzt.", head_bold="Was du schuldest.",
                         badge=None, caption="Girokonto. Ersparnisse. Investitionen. Kredite."),
        "activite": dict(head_light="Jede Ausgabe.", head_bold="In einer Geste erfasst.",
                          badge=None, caption="Nichts entgeht dir."),
    },
}


def vertical_gradient(w, h, stops):
    """stops: list of (position 0..1, rgb). Smooth multi-stop lerp."""
    grad = Image.new("RGB", (1, h))
    px = grad.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                local = (t - p0) / (p1 - p0) if p1 > p0 else 0
                px[0, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * local) for k in range(3))
                break
        else:
            px[0, y] = stops[-1][1]
    return grad.resize((w, h))


def radial_glow(w, h, center, radius, color, max_alpha):
    """A soft light source behind the phone, the way the reference shots use
    a glow to keep an otherwise flat gradient from reading as empty."""
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        alpha = int(max_alpha * (1 - i / steps) ** 2)
        bbox = [center[0] - r, center[1] - r, center[0] + r, center[1] + r]
        gd.ellipse(bbox, fill=(*color, alpha))
    return glow


def place_background(im, w, h, subject_frac, thickness_frac, text_bottom, visible_top):
    """Scale `im` to the canvas width and slide it so the photo's own
    subject lands where there's actually room for it.

    Centering the crop — the obvious move — put the subject at roughly 70%
    down a 1536-tall source, which after a cover-fit scale landed at canvas
    y≈2000: deep under the phone, invisible.

    Once it was pulled into view, the second problem was that the strip
    between the headline and the phone (~300px) is narrower than the
    subject's own height including its glow (~550px) — no position clears
    both edges at once. So this doesn't try to: the subject's top is placed
    just under the text, and its lower half is allowed to run under the
    phone's top edge. On this app that reads as the coins arriving at the
    phone rather than a bad crop, which is the only reason it's an
    acceptable trade rather than a bug.
    """
    scale = w / im.width
    resized = im.resize((w, int(im.height * scale) + 1), Image.LANCZOS)
    half_thickness = int(resized.height * thickness_frac / 2)
    target_y = text_bottom + 40 + half_thickness
    subject_y = int(resized.height * subject_frac)
    paste_y = target_y - subject_y
    canvas = Image.new("RGB", (w, h), (11, 10, 20))
    canvas.paste(resized, (0, paste_y))
    return canvas


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def fit_font(draw, text, weight, start_size, max_width, min_size=40):
    """The largest size of `weight` that still keeps `text` on one line —
    headlines run big by default, this only steps down for the rare long
    word rather than capping every screen to its longest line's size."""
    size = start_size
    while size > min_size:
        f = font(weight, size)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 4
    return font(weight, min_size)


# Left margin for every left-aligned element — headline, badge — so they
# share one edge the way a magazine masthead does.
MARGIN = 88

# How much of the phone's own height stays on canvas. Was 0.80 on a flat
# gradient, where nothing was lost by the phone covering most of the frame.
# A photographed scene has an actual subject somewhere in it, and 0.80 left
# it only the top ~25% of the canvas to appear in — not enough room for a
# subject that was generated sitting in the lower-middle of its own frame.
VISIBLE_SHARE_PHOTO = 0.60
VISIBLE_SHARE_FLAT = 0.80

# Where the subject sits in every generated background, and roughly how
# tall it reads including its own glow — both as a fraction of the source's
# height. Measured off the piggy bank's bright pixels (source rows ~880 to
# ~1300 of 1536); every prompt asked for the same centered-low composition,
# so one shared pair covers the set.
SUBJECT_FRAC = 0.71
SUBJECT_THICKNESS_FRAC = 0.27


def build(entry, index, out_dir, raw_dir):
    src = Image.open(raw_dir / entry["src"]).convert("RGB")
    frame = Image.open(FRAME_PATH).convert("RGBA")

    # --- The phone's geometry, worked out before the background — a
    # photographed scene needs to know how much room it actually has before
    # it can decide where to put its subject. ---
    # Full width, but no wider — the frame's own edges are the device's
    # identity (the titanium rail, the button) and a horizontal crop was
    # cutting them off. The vertical bleed at the bottom is a different
    # thing: that edge was never meant to read as the phone's silhouette.
    frame_target_w = int(W * 0.99)
    frame_scale = frame_target_w / frame.width
    frame_h = int(frame.height * frame_scale)
    frame_r = frame.resize((frame_target_w, frame_h), Image.LANCZOS)

    off_x = int(int(OFFSETS["offset"].split("+")[1]) * frame_scale)
    off_y = int(int(OFFSETS["offset"].split("+")[2]) * frame_scale)
    screen_w = int(OFFSETS["width"] * frame_scale)
    screen_h = int(screen_w * src.height / src.width)

    screen_r = src.resize((screen_w, screen_h), Image.LANCZOS)
    mask = rounded_mask((screen_w, screen_h), int(screen_w * 0.09))
    phone = Image.new("RGBA", frame_r.size, (0, 0, 0, 0))
    phone.paste(screen_r, (off_x, off_y), mask)
    phone.alpha_composite(frame_r)

    bg_path = entry.get("bg")
    has_bg = bool(bg_path and bg_path.exists())
    visible_share = VISIBLE_SHARE_PHOTO if has_bg else VISIBLE_SHARE_FLAT

    phone_x = (W - frame_target_w) // 2
    phone_y = H - int(frame_h * visible_share)

    # --- Headline layout, measured before either the background or the
    # canvas exist — a photographed background needs to know where the text
    # block actually ends before it can decide where its own subject goes,
    # and text metrics don't need a real canvas to be computed on. ---
    scratch = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    max_head_w = W - MARGIN - 50
    f_light = font("Medium", 104)
    f_bold = fit_font(scratch, entry["head_bold"], "Bold", 250, max_head_w, min_size=140)
    bold_size = f_bold.size
    y = 170
    y += int(f_light.size * 1.05)
    # PIL's y is the glyph box top, not the baseline, so this lands past the
    # visible bottom of the capitals rather than at their own em-square edge
    # — 0.85 landed the badge close enough to read as touching the letters.
    y += int(bold_size * 1.05)

    badge_box = None
    if entry["badge"]:
        bf = font("Bold", 34)
        bw = scratch.textlength(entry["badge"], font=bf)
        pad_x, pad_y = 34, 16
        badge_h = 34 + pad_y * 2
        bx0 = MARGIN
        # Clamped to sit above the phone with a fixed gap, whatever the
        # headline's own flow would have put it at — the phone is drawn
        # after this and would otherwise paint over a badge sitting too low.
        by0 = min(y + 56, phone_y - badge_h - 60)
        badge_box = (bf, bw, pad_x, pad_y, bx0, by0, bx0 + bw + pad_x * 2, by0 + badge_h)
    text_bottom = badge_box[7] if badge_box else y

    if has_bg:
        # A generated scene already carries its own light and mood — the
        # synthetic glow this app used to add on top would just muddy it.
        canvas = place_background(
            Image.open(bg_path).convert("RGB"), W, H,
            SUBJECT_FRAC, SUBJECT_THICKNESS_FRAC, text_bottom, phone_y,
        ).convert("RGBA")
    else:
        canvas = vertical_gradient(W, H, [
            (0.0, TOP), (0.45, MID), (1.0, BOTTOM),
        ]).convert("RGBA")
        glow = radial_glow(W, H, (W // 2, int(H * 0.60)), int(W * 0.9),
                            (140, 130, 247), 140)
        canvas.alpha_composite(glow)

    draw = ImageDraw.Draw(canvas)

    # --- Headline, left-aligned, two sizes deliberately far apart: a small
    # lead-in over one huge word of consequence. ---
    y = 170
    draw.text((MARGIN, y), entry["head_light"], font=f_light, fill=DIM)
    y += int(f_light.size * 1.05)
    draw.text((MARGIN, y), entry["head_bold"], font=f_bold, fill=WHITE)
    y += int(bold_size * 1.05)

    # --- Trust badge, first screenshot only (the hook frame) ---
    if badge_box:
        bf, bw, pad_x, pad_y, bx0, by0, bx1, by1 = badge_box
        # ImageDraw writes raw pixel values, not a blend — a translucent fill
        # painted straight onto the canvas keeps its RGB at full opacity, and
        # a later `convert("RGB")` drops the alpha that was supposed to soften
        # it, leaving a solid white pill with white text invisible on it.
        # Composited on its own layer, the blend actually happens.
        badge_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        bd = ImageDraw.Draw(badge_layer)
        bd.rounded_rectangle([bx0, by0, bx1, by1], radius=(by1 - by0) / 2,
                              fill=(255, 255, 255, 46),
                              outline=(255, 255, 255, 130), width=2)
        canvas.alpha_composite(badge_layer)
        draw.text((bx0 + pad_x, by0 + pad_y - 2), entry["badge"], font=bf, fill=WHITE)

    # Drop shadow: the frame's own alpha, blurred and darkened, offset down.
    # Clipped to the canvas the same as the phone, so no dark halo appears
    # past the bottom edge where the phone itself has already been cut off.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_alpha = frame_r.split()[-1].point(lambda a: int(a * 0.55))
    shadow.paste((0, 0, 0, 255), (phone_x, phone_y + 30), shadow_alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.alpha_composite(shadow)

    canvas.alpha_composite(phone, (phone_x, phone_y))

    out_path = out_dir / f"{index}-{Path(entry['src']).stem}.png"
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(out_path.name, canvas.size)


for locale, screens in LOCALES.items():
    locale_dir = OUT / locale
    locale_dir.mkdir(parents=True, exist_ok=True)
    for i, key in enumerate(SCREEN_KEYS, start=1):
        entry = dict(screens[key])
        entry["src"] = SCREEN_SRC[key]
        entry["bg"] = BG_DIR / SCREEN_SRC[key]
        build(entry, i, locale_dir, RAW_BY_LOCALE[locale])
