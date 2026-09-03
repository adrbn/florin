# Mettre Florin sur l'App Store

Tout ce que la soumission demande, prêt à coller. L'app est `6807898365`,
`com.adrbn.florin`, équipe `2TWQF4T93E`.

---

## Où on en est

**Fait, et vérifié :**

| | |
|---|---|
| Certificat de distribution | `iOS Distribution: Adrien Robino`, émis le 03/09/2026, valable jusqu'au 03/09/2027. Créé depuis la CSR de `~/florin-signing/`, installé dans le trousseau. |
| Profils App Store | `Florin App Store` et `Florin Widgets App Store`, actifs, installés dans `~/Library/MobileDevice/Provisioning Profiles/`. |
| IPA signée | `apps/ios/build-export/Florin.ipa`, 5,7 Mo, signée pour l'App Store. |
| Icône | Aplatie sur blanc. Apple refuse un canal alpha sur l'icône 1024 ; le rendu est identique au pixel près, iOS applique son propre masque. |
| Conformité export | `ITSAppUsesNonExemptEncryption = false` dans l'Info.plist, donc la question n'est plus posée à chaque envoi. |
| Captures 6,9″ | `AppStore/screenshots-6.9/`, 1320 × 2868, ledger fictif. |

**Bloqué sur une seule chose :** Apple refuse tout ce qui est construit avec un
Xcode bêta, à la validation comme au téléversement.

```
Unsupported SDK or Xcode version (90534)
```

Cette machine n'a que **Xcode-beta 27.0**. Il faut un Xcode public ou RC — c'est
le seul geste que je ne peux pas faire à ta place, l'installation demandant ton
compte Apple.

1. App Store → chercher « Xcode » → installer (ou developer.apple.com/download).
2. `sudo xcode-select -s /Applications/Xcode.app`
3. Relancer les trois commandes de la section [Construire et envoyer](#construire-et-envoyer).

---

## Statut de commerçant — à lire avant tout le reste

Depuis février 2025, Apple exige un **statut de commerçant** (_trader status_)
pour distribuer sur l'App Store de l'Union européenne. Sans lui, l'app n'est
simplement pas disponible en France — et c'est là que sont tes amis.

Le déclarer publie ton nom, ton adresse et un moyen de contact sur la fiche de
l'app. C'est le prix, et il n'y a pas de contournement : un non-commerçant peut
publier partout **sauf** dans l'UE.

- **App Store Connect → Business → Statut de commerçant.**
- TestFlight n'est pas concerné : tes amis peuvent tester sans que tu déclares
  quoi que ce soit.

Si tu ne veux pas publier ton adresse, la voie honnête est de rester sur
TestFlight (100 testeurs externes, builds valables 90 jours) et de garder l'IPA
et le code sur GitHub pour les autres.

---

## Version

La fiche annonce **1.0**, la build est **1.3.4**. La chaîne de version dans App
Store Connect doit être exactement celle du `CFBundleShortVersionString`.

→ Dans **Distribution**, renomme la version en `1.3.4` avant d'attacher la build.

---

## Informations sur l'app

| Champ | Valeur |
|---|---|
| Nom | `Florin` |
| Sous-titre | `Vos comptes restent chez vous` |
| Catégorie principale | Finance |
| Catégorie secondaire | — (laisser vide) |
| Langue principale | Français |
| Droits relatifs au contenu | Non, l'app ne contient aucun contenu tiers |
| Copyright | `2026 Adrien Robino` |
| Classification par âge | 4+ — répondre « Aucun » à toutes les questions, et **Non** à « Accès web sans restriction » |
| Prix | Gratuit |
| Disponibilité | Tous les pays (sous réserve du statut de commerçant pour l'UE) |

### URL

| Champ | Valeur |
|---|---|
| URL d'assistance | `https://github.com/adrbn/florin/issues` |
| URL marketing | `https://github.com/adrbn/florin` |
| Politique de confidentialité | `https://github.com/adrbn/florin/blob/main/PRIVACY.md` |

---

## Texte de la fiche — français

### Texte promotionnel (170 max, modifiable sans nouvelle version)

```
Le plan du mois, le patrimoine sur un an et chaque dépense classée — dans un fichier qui ne quitte pas votre téléphone.
```

### Description

```
Florin garde vos comptes chez vous.

Vos relevés ne partent sur aucun serveur qui ne soit pas le vôtre. L'app lit votre banque depuis le téléphone, écrit tout dans un fichier local, et n'envoie rien à personne. Pas de compte à créer, pas de mesure d'audience, pas de publicité.

CE QUE ÇA FAIT

• Le patrimoine sur un an — comptes courants, épargne, titres et prêts compris.
• Un plan mensuel : vous répartissez ce qui rentre, l'app suit ce qui sort et vous dit ce qu'il reste.
• Chaque opération classée, à la main ou par des règles qui retiennent vos décisions.
• L'analyse par poste, par mois et par jour, avec la liste des abonnements que vous aviez oubliés.
• Un widget qui répond à la seule question qu'on se pose vraiment : combien reste-t-il.
• Face ID à l'ouverture, si vous le voulez.

VOS DONNÉES

Tout tient dans un fichier sur votre iPhone. Vous pouvez l'exporter, le reprendre sur un autre téléphone, ou brancher Florin sur votre propre serveur si vous en avez un.

VOTRE BANQUE

La synchronisation passe par Enable Banking (DSP2), avec vos propres identifiants d'application. Elle est facultative : Florin fonctionne entièrement à la main, ou par import des fichiers CSV et OFX que votre banque vous donne déjà.

OUVERT

Florin est un logiciel libre sous licence AGPL-3.0. Le code se lit :
github.com/adrbn/florin
```

### Mots-clés (100 caractères, sans espace après les virgules)

```
budget,épargne,dépenses,comptes,finances,patrimoine,banque,DSP2,PEA,hors-ligne
```

### Nouveautés de cette version

```
Première version publique.
```

---

## Texte de la fiche — anglais

### Sous-titre

```
Your accounts stay with you
```

### Texte promotionnel

```
This month's plan, a year of net worth, every expense filed — in one file that never leaves your phone.
```

### Description

```
Florin keeps your accounts where they are: with you.

Your statements go to no server that isn't yours. The app reads your bank from the phone, writes everything to a local file, and sends nothing to anyone. No account to create, no analytics, no advertising.

WHAT IT DOES

• A year of net worth — current accounts, savings, holdings and loans included.
• A monthly plan: you assign what comes in, the app follows what goes out and tells you what is left.
• Every transaction filed, by hand or by rules that remember your decisions.
• Analysis by category, by month and by day, with the subscriptions you had forgotten.
• A widget that answers the only question anyone actually asks: how much is left.
• Face ID at the door, if you want it.

YOUR DATA

It all fits in one file on your iPhone. Export it, carry it to another phone, or point Florin at your own server if you run one.

YOUR BANK

Syncing goes through Enable Banking (PSD2) with your own application credentials. It is optional: Florin works entirely by hand, or by importing the CSV and OFX files your bank already gives you.

OPEN

Florin is free software under the AGPL-3.0. The code reads plainly:
github.com/adrbn/florin
```

### Mots-clés

```
budget,savings,expenses,accounts,finance,net worth,banking,offline,private,ledger
```

---

## Confidentialité de l'app

**Réponse : « Données non collectées ».**

Rien ne quitte l'appareil vers nous. Il n'y a pas de serveur à nous, pas de SDK
tiers, pas de mesure d'audience, pas de rapport de plantage. Enable Banking n'est
pas notre partenaire : c'est une application que l'utilisateur enregistre lui-même,
avec ses identifiants, et la liaison va de son téléphone à sa banque.

Dans **Distribution → Confidentialité de l'app**, coche « Non » à la première
question et le questionnaire s'arrête là.

---

## Notes pour l'examinateur

À coller dans **Informations sur la vérification → Notes**.

```
Aucun compte n'est nécessaire. Florin fonctionne entièrement hors ligne : à la première ouverture, un guide propose d'ajouter un compte et quelques opérations à la main, ce qui suffit à voir tous les écrans (Aperçu, Comptes, Plan, Activité, Analyse).

La synchronisation bancaire est facultative et n'est pas nécessaire pour l'examen. Elle exige que l'utilisateur enregistre sa propre application auprès d'Enable Banking (DSP2) et fournisse sa clé privée ; nous ne pouvons pas fournir d'identifiants de test, parce que l'app n'en possède aucun — elle n'a pas de serveur.

L'app peut aussi importer un fichier CSV ou OFX depuis Réglages → Données, si vous préférez remplir l'écran en une fois.

Le code source est public : https://github.com/adrbn/florin
```

---

## Captures d'écran

`AppStore/screenshots-6.9/`, cinq fichiers 1320 × 2868 (iPhone 6,9″ — la seule
taille qu'Apple exige aujourd'hui, les autres sont dérivées automatiquement).

1. `1-apercu.png` — patrimoine et courbe sur un an
2. `2-plan.png` — le plan du mois
3. `3-calendrier.png` — dépenses par jour
4. `4-comptes.png` — répartition et comptes
5. `5-activite.png` — la file à vérifier

Le ledger est fictif : `seed-demo-ledger.py` le fabrique dans un simulateur.
Aucune donnée réelle n'y figure.

```bash
UDID=$(xcrun simctl create "Florin Shots" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$UDID"
# installer la build, puis
python3 apps/ios/AppStore/seed-demo-ledger.py "$(xcrun simctl get_app_container "$UDID" com.adrbn.florin data)/Library/Application Support/Florin/florin.db"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
```

---

## Construire et envoyer

Une fois un Xcode public installé :

```bash
cd apps/ios
xcodebuild -project Florin.xcodeproj -scheme Florin -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build-archive/Florin.xcarchive" archive
```

```bash
cd apps/ios
xcodebuild -exportArchive -archivePath "$PWD/build-archive/Florin.xcarchive" \
  -exportOptionsPlist ExportOptions-appstore.plist -exportPath "$PWD/build-export"
```

```bash
xcrun altool --upload-app --type ios -f apps/ios/build-export/Florin.ipa --apiKey 5L888V4RWV --apiIssuer 21df40c7-84f8-445f-ae7d-a46e373904db
```

Le traitement de la build prend cinq à quinze minutes, après quoi elle apparaît
dans TestFlight et devient sélectionnable dans la fiche.

### Si la signature casse un jour

Le certificat a été créé par l'API, pas par Xcode, parce que la clé
`5L888V4RWV` n'a pas le rôle Admin qu'exige la signature automatique. Pour que
Xcode se débrouille seul à l'avenir, il suffit de régénérer une clé API en
**Admin** (App Store Connect → Utilisateurs et accès → Intégrations) ; sinon
`ExportOptions-appstore.plist` nomme les profils à la main et n'a besoin de rien.

---

## L'ordre des choses

1. Installer un Xcode public. — **toi**
2. Statut de commerçant, si tu veux l'UE. — **toi**
3. Renommer la version en 1.3.4. — **toi**
4. Coller le texte, les URL, les captures ci-dessus. — **toi** (ou moi, si tu me
   redonnes la main sur ASC)
5. Confidentialité : « Données non collectées ».
6. Construire, exporter, envoyer.
7. Attacher la build, répondre aux notes d'examen, soumettre.
