import Foundation

/*
 * Which website a well-known merchant lives at.
 *
 * Only addresses — no pictures. A brand's logo is its trademark and cannot be
 * shipped under the app's licence; the address is a public fact. With it, the
 * phone asks the merchant's own site for its icon (`LogoFetcher`), and no
 * logo service in the middle learns where anyone shops.
 *
 * Matched on whole words of the merchant key (`MerchantNames.key`), first
 * match wins, so the more specific names come first ("uber eats" before
 * "uber"). A word that is also a common name or word — "free", "action",
 * "claude", "lydia", "leclerc" — is left out rather than put on the wrong rows: the
 * merchant sheet lets anyone set the site themselves.
 */
enum KnownMerchants {
    static func domain(forKey key: String) -> String? {
        let words = normalize(key)
        guard !words.isEmpty else { return nil }
        let padded = " \(words) "
        for (pattern, domain) in entries where padded.contains(" \(pattern) ") {
            return domain
        }
        return nil
    }

    /// Lowercase, no accents, letters and digits only: "H&M" → "h m",
    /// "Amazon.fr" → "amazon fr", "McDonald's" → "mcdonald s".
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let spaced = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    private static let entries: [(String, String)] = [
        // Phone and internet
        ("free mobile", "free.fr"), ("free telecom", "free.fr"), ("freebox", "free.fr"),
        ("iliad", "iliad.it"), ("orange", "orange.fr"), ("sosh", "sosh.fr"), ("sfr", "sfr.fr"),
        ("bouygues", "bouyguestelecom.fr"), ("telecom italia", "tim.it"), ("vodafone", "vodafone.com"),
        ("windtre", "windtre.it"), ("wind tre", "windtre.it"), ("fastweb", "fastweb.it"),
        ("ho mobile", "ho-mobile.it"), ("movistar", "movistar.es"), ("telekom", "telekom.de"),
        ("kpn", "kpn.com"), ("ziggo", "ziggo.nl"), ("meo", "meo.pt"),

        // Subscriptions and software
        ("netflix", "netflix.com"), ("spotify", "spotify.com"), ("deezer", "deezer.com"),
        ("disney", "disneyplus.com"), ("canal", "canalplus.com"), ("dazn", "dazn.com"),
        ("prime video", "primevideo.com"), ("audible", "audible.com"), ("youtube", "youtube.com"),
        ("google", "google.com"), ("itunes", "apple.com"), ("icloud", "apple.com"), ("apple", "apple.com"),
        ("microsoft", "microsoft.com"), ("xbox", "xbox.com"), ("playstation", "playstation.com"),
        ("steam", "steampowered.com"), ("steampowered", "steampowered.com"), ("nintendo", "nintendo.com"),
        ("openai", "openai.com"), ("chatgpt", "openai.com"), ("anthropic", "anthropic.com"),
        ("github", "github.com"), ("dropbox", "dropbox.com"), ("adobe", "adobe.com"),
        ("notion", "notion.so"), ("duolingo", "duolingo.com"), ("twitch", "twitch.tv"),
        ("patreon", "patreon.com"), ("linkedin", "linkedin.com"), ("discord", "discord.com"),
        ("crunchyroll", "crunchyroll.com"), ("paramount", "paramountplus.com"), ("tidal", "tidal.com"),

        // Money
        ("paypal", "paypal.com"), ("revolut", "revolut.com"),
        ("n26", "n26.com"), ("boursorama", "boursobank.com"), ("boursobank", "boursobank.com"),
        ("satispay", "satispay.com"), ("klarna", "klarna.com"), ("scalapay", "scalapay.com"),
        ("qonto", "qonto.com"),

        // Getting around
        ("uber eats", "ubereats.com"), ("ubereats", "ubereats.com"), ("uber", "uber.com"),
        ("sncf", "sncf-connect.com"), ("ouigo", "ouigo.com"), ("ratp", "ratp.fr"),
        ("bolt", "bolt.eu"), ("blablacar", "blablacar.fr"), ("freenow", "free-now.com"),
        ("free now", "free-now.com"), ("trenitalia", "trenitalia.com"), ("italotreno", "italotreno.it"),
        ("renfe", "renfe.com"), ("deutsche bahn", "bahn.de"), ("flixbus", "flixbus.com"),
        ("ryanair", "ryanair.com"), ("easyjet", "easyjet.com"), ("air france", "airfrance.fr"),
        ("vueling", "vueling.com"), ("lufthansa", "lufthansa.com"), ("transavia", "transavia.com"),
        ("ita airways", "ita-airways.com"), ("totalenergies", "totalenergies.com"),
        ("esso", "esso.com"), ("shell", "shell.com"), ("eni", "eni.com"), ("telepass", "telepass.com"),
        ("vinci autoroutes", "vinci-autoroutes.com"), ("sanef", "sanef.com"), ("aprr", "aprr.fr"),

        // Food delivered
        ("deliveroo", "deliveroo.com"), ("just eat", "just-eat.com"), ("glovo", "glovoapp.com"),
        ("too good to go", "toogoodtogo.com"),

        // Groceries
        ("carrefour", "carrefour.fr"), ("e leclerc", "e.leclerc"), ("auchan", "auchan.fr"),
        ("intermarche", "intermarche.com"), ("lidl", "lidl.com"), ("aldi", "aldi.fr"),
        ("monoprix", "monoprix.fr"), ("franprix", "franprix.fr"), ("picard surgeles", "picard.fr"),
        ("super u", "magasins-u.com"), ("hyper u", "magasins-u.com"), ("biocoop", "biocoop.fr"),
        ("naturalia", "naturalia.fr"), ("grand frais", "grandfrais.com"),
        ("esselunga", "esselunga.it"), ("conad", "conad.it"), ("coop italia", "e-coop.it"),
        ("eurospin", "eurospin.it"), ("despar", "despar.it"),
        ("naturasi", "naturasi.it"), ("tigota", "tigota.it"),
        ("mercadona", "mercadona.es"), ("el corte ingles", "elcorteingles.es"), ("eroski", "eroski.es"),
        ("alcampo", "alcampo.es"), ("rewe", "rewe.de"), ("edeka", "edeka.de"), ("kaufland", "kaufland.de"),
        ("rossmann", "rossmann.de"), ("albert heijn", "ah.nl"), ("jumbo", "jumbo.com"),
        ("continente", "continente.pt"), ("pingo doce", "pingodoce.pt"), ("tesco", "tesco.com"),
        ("sainsbury", "sainsburys.co.uk"), ("sainsburys", "sainsburys.co.uk"), ("waitrose", "waitrose.com"),

        // Shops
        ("amazon", "amazon.com"), ("amzn", "amazon.com"), ("decathlon", "decathlon.com"),
        ("ikea", "ikea.com"), ("leroy merlin", "leroymerlin.fr"), ("castorama", "castorama.fr"),
        ("fnac", "fnac.com"), ("darty", "darty.com"),
        ("zara", "zara.com"), ("h m", "hm.com"), ("uniqlo", "uniqlo.com"), ("primark", "primark.com"),
        ("kiabi", "kiabi.com"), ("sephora", "sephora.com"), ("nocibe", "nocibe.fr"),
        ("yves rocher", "yves-rocher.com"), ("cdiscount", "cdiscount.com"), ("vinted", "vinted.com"),
        ("leboncoin", "leboncoin.fr"), ("aliexpress", "aliexpress.com"), ("temu", "temu.com"),
        ("shein", "shein.com"), ("zalando", "zalando.com"), ("asos", "asos.com"), ("etsy", "etsy.com"),
        ("ebay", "ebay.com"), ("wallapop", "wallapop.com"), ("subito", "subito.it"),
        ("mediaworld", "mediaworld.it"), ("unieuro", "unieuro.it"), ("euronics", "euronics.it"),
        ("mediamarkt", "mediamarkt.de"), ("media markt", "mediamarkt.de"), ("saturn", "saturn.de"),
        ("maisons du monde", "maisonsdumonde.com"), ("conforama", "conforama.fr"),
        ("flying tiger", "flyingtiger.com"), ("lush", "lush.com"), ("nespresso", "nespresso.com"),
        ("hema", "hema.com"), ("bol com", "bol.com"), ("boots", "boots.com"),

        // Eating out
        ("starbucks", "starbucks.com"), ("mcdonald", "mcdonalds.com"), ("mcdonalds", "mcdonalds.com"),
        ("burger king", "burgerking.fr"), ("kfc", "kfc.com"), ("subway", "subway.com"),
        ("dominos", "dominos.com"), ("domino s", "dominos.com"), ("five guys", "fiveguys.com"),
        ("pret a manger", "pret.com"), ("brioche doree", "briochedoree.fr"),

        // Home, health, paperwork
        ("edf", "edf.fr"), ("engie", "engie.fr"), ("enel", "enel.it"), ("iberdrola", "iberdrola.es"),
        ("endesa", "endesa.com"), ("naturgy", "naturgy.es"), ("vattenfall", "vattenfall.com"),
        ("veolia", "veolia.com"), ("axa", "axa.com"), ("maif", "maif.fr"), ("macif", "macif.fr"),
        ("matmut", "matmut.fr"), ("allianz", "allianz.com"), ("generali", "generali.com"),
        ("groupama", "groupama.fr"), ("doctolib", "doctolib.fr"), ("ameli", "ameli.fr"),
        ("cpam", "ameli.fr"), ("urssaf", "urssaf.fr"), ("dgfip", "impots.gouv.fr"),
        ("la poste", "laposte.fr"), ("poste italiane", "poste.it"), ("chronopost", "chronopost.fr"),
        ("mondial relay", "mondialrelay.fr"), ("dhl", "dhl.com"),

        // Travel and leisure
        ("airbnb", "airbnb.com"), ("booking", "booking.com"), ("expedia", "expedia.com"),
        ("trainline", "thetrainline.com"), ("accor", "all.accor.com"), ("basic fit", "basic-fit.com"),
        ("fitness park", "fitnesspark.fr"),
    ]
}
