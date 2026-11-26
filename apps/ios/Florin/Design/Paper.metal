#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/*
 * La matière d'un ticket de caisse, calculée par pixel.
 *
 * Un aplat gris ne ressemble à rien : ce qui fait reconnaître du papier
 * thermique, ce sont trois choses qu'aucun dégradé SwiftUI ne sait poser
 * ensemble — la fibre, qui est étirée dans le sens de la bobine et non
 * isotrope ; la courbure, parce qu'une bande coupée d'un rouleau ne reste
 * jamais plate et que ses bords s'éloignent de la lumière ; et le reflet
 * rasant, qui n'a de sens que s'il bouge avec l'appareil.
 *
 * Tout est relatif à la couleur passée, jamais à un beige écrit ici : les
 * cinq palettes de Florin n'ont pas le même fond, et un ticket crème sur
 * l'Ardoise serait une tache. Ce qui fait le papier, c'est la fibre et la
 * courbure, pas la teinte.
 */

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/*
 * `light` est la position du reflet, de 0 (bord gauche) à 1 (bord droit).
 * Elle vient de l'inclinaison du téléphone, pas d'une horloge : un reflet
 * qui avance tout seul est une animation, un reflet qui suit la main est
 * une surface.
 *
 * `ink` dose le creux de la courbure. À 0 le papier est plat — c'est ce
 * qu'on veut derrière une vignette photo, où une ombre de pli passerait
 * pour une tache sur l'image.
 */
[[ stitchable ]] half4 thermalPaper(
    float2 position, float2 size, half4 base, float light, float bend
) {
    float2 uv = position / max(size, float2(1.0));

    // La fibre suit la bobine : tres etiree en x, serree en y. Une fibre
    // isotrope donne du sable, pas du papier.
    float fibre = valueNoise(float2(position.x * 0.8, position.y * 0.11));
    float speck = valueNoise(position * 2.6);
    float grain = (fibre - 0.5) * 0.030 + (speck - 0.5) * 0.014;

    // Le cylindre. Puissance quatre plutot que deux : le creux reste franc
    // au centre et ne tombe que tout pres des bords, la ou la bande se
    // releve vraiment.
    float v = uv.y * 2.0 - 1.0;
    float curve = -0.055 * v * v * v * v;

    // Les bords lateraux sont coupes net par la lame : une ombre d'un
    // millimetre, pas un degrade sur toute la largeur.
    float sides = -0.030 * pow(abs(uv.x * 2.0 - 1.0), 14.0);

    // Le reflet rasant. Large et faible : une bande etroite et vive est un
    // neon, pas une lumiere de piece.
    float spec = exp(-pow((uv.x - light) * 2.6, 2.0)) * 0.040;

    /*
     * Ajoute, jamais multiplie.
     *
     * Une lumiere en facteur ne se voit pas sur du noir : sur le theme
     * Editorial, fond 0x101218, un gain de 5 % vaut un demi-point de
     * luminance et la feuille redevenait un rectangle plat. Le meme ecart
     * pose en absolu se lit sur les cinq palettes -- c'est d'ailleurs
     * physique, une surface eclairee recoit des photons, elle ne multiplie
     * pas ceux qu'elle avait.
     */
    half delta = half((curve + sides) * bend + grain + spec);
    return half4(clamp(base.rgb + delta, 0.0h, 1.0h), base.a);
}

/*
 * Le bord arraché.
 *
 * Une dent de scie régulière se lit comme un motif décoratif — c'est le
 * timbre-poste, pas le papier déchiré. Ce masque ronge le haut et le bas
 * avec un bruit, donc chaque dent a sa profondeur et sa largeur, et les
 * fibres les plus longues dépassent.
 *
 * Un masque plutôt qu'un `Shape` : une déchirure tient dans quelques
 * pixels et un tracé vectoriel qui la décrit honnêtement coûte deux cents
 * segments par bord, redessinés à chaque image.
 */
[[ stitchable ]] half4 tornEdge(
    float2 position, half4 color, float2 size, float depth, float seed
) {
    float bite = max(depth, 1.0);
    float along = position.x / 9.0 + seed;
    // Deux échelles : la grande fait les dents, la petite les fibres.
    float teeth = valueNoise(float2(along, seed));
    float fibres = valueNoise(float2(along * 4.3, seed + 7.0));
    float edge = bite * (0.35 + 0.65 * teeth) * (0.78 + 0.22 * fibres);

    float top = position.y;
    float bottom = size.y - position.y;
    float nearest = min(top, bottom);
    // Un demi-pixel d'adoucissement : net, mais sans escalier.
    float alpha = smoothstep(edge - 0.5, edge + 0.5, nearest);
    return color * half(alpha);
}
