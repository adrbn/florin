# Correctifs en attente d'une build

Trois corrections sont dans l'arbre mais ne sont dans aucune build téléversée.
La build en revue chez Apple est la **1.3.4 (3)**, compilée par Xcode Cloud, et
elle ne les contient pas.

## 1. La langue choisie n'atteignait que l'écran ouvert

`Florin/FlorinApp.swift`

`changeLocale` écrit la préférence et vide le cache de traductions, mais une vue
déjà rendue garde le texte avec lequel elle a été construite. Choisir English
passait les Réglages en anglais et laissait les cinq onglets derrière en
français, jusqu'à ce que quelque chose les reconstruise — fermer puis rouvrir
les Réglages suffisait, ce qui faisait passer le défaut pour un caprice.

La racine lit maintenant la préférence, ce qui fait réévaluer la scène, et un
`.id()` jette l'arbre périmé.

Vérifié : la vidéo de démonstration montre l'Aperçu entièrement en anglais après
le changement.

## 2. « Ready to Assign » au milieu des catégories françaises

`Florin/Local/Resources/SeedCategories.json`

Le bloc français n'avait jamais été traduit pour cette catégorie ; le
néerlandais l'était. Elle apparaissait en anglais entre Salaires, Loyer et
Courses au premier lancement — visible vers 0:24 de la vidéo envoyée à Apple.

Devenue « À répartir », le terme déjà employé par l'écran Budget.

## 3. L'écran « Votre serveur Florin » était sans issue

`Florin/SetupView.swift`

Le bouton de fermeture n'est dessiné que lorsque l'écran est poussé depuis les
réglages. Au premier lancement il n'y en avait aucun, et le seul bouton restant
reste désactivé tant qu'aucune adresse ne se parse. Quiconque choisissait « j'ai
déjà un serveur » par erreur — ou réinstallait et atterrissait là parce que la
préférence avait survécu au conteneur — se retrouvait sans serveur, sans retour
et sans avancée : supprimer l'app était la seule sortie.

Un bouton « Utiliser cet appareil » écrit `florin.dataSource` et rend l'app à
elle-même. Traduit en/fr/nl.

C'est exactement le genre de blocage qu'un examinateur Apple signale comme
« app incomplète », donc à ne pas laisser passer une soumission de plus.

## 4. Un compte bancaire dédoublé à chaque reconnexion

`Florin/Banking/BankingSync.swift` — **écrit, pas encore compilé**

Enable Banking donne à chaque compte un `uid` valable pour la session qui l'a
produit : reconnecter la même banque en renvoie un autre pour le même compte
réel. `upsertAccount` ne cherchait que sur cet uid, donc après une reconnexion
il ne trouvait rien et insérait un second compte pour de l'argent déjà suivi.

C'est arrivé le 5 septembre : le CCP et un « MR ROBINO ADRIEN » affichaient tous
deux 3 001 €, et le patrimoine était surévalué d'autant.

La feuille de rattachement ne pouvait pas sauver la situation : `candidates()`
masque tout compte ayant déjà un `sync_external_id`, donc le CCP — le seul
choix correct — était absent de la liste, et « Nouveau compte » restait la seule
option.

L'IBAN est le compte, quel que soit celui qui demande et quand. Enable Banking
le renvoie (`AccountDetails.accountId.iban`) et la colonne existait déjà, mais
la synchro ne l'écrivait jamais. Elle l'écrit maintenant, à l'insertion comme à
la mise à jour, et le cherche en second recours quand l'uid ne trouve rien.

### Suppression délibérée — tranché

Supprimer un compte synchronisé le faisait revenir à la synchro suivante : la
ligne supprimée portait l'uid, seule chose sur laquelle la recherche s'appuyait,
donc la synchro ne trouvait rien et réinsérait.

`commitDelete` retire maintenant la connexion en même temps, mais seulement si
plus aucun compte ne l'utilise. Quelqu'un qui supprime un compte dit qu'il ne
veut plus le suivre ; la connexion qui le réajoute doit partir avec. La
confirmation le dit désormais, et précise que rien ne change côté banque.

## 5. Une zone de graphique vide au premier jour — fait

`Florin/Screens/OverviewScreen.swift`

`netWorthSeries` remonte le temps depuis les soldes d'aujourd'hui jusqu'à la
transaction la plus ancienne. C'est le bon sens de lecture : sommer vers l'avant
depuis zéro dessinerait un patrimoine qui part de rien et grimpe, ce qui n'est
jamais ce qui s'est passé.

Mais quelqu'un qui vient de créer son compte et saisit deux transactions du jour
n'a qu'une seule journée d'historique, donc un seul point, donc aucune ligne —
et l'app lui montre une bande vide entre son patrimoine et les boutons de
période, sans un mot d'explication. C'est visible sur la vidéo envoyée à Apple.

Le graphique n'était masqué que lorsqu'il n'y avait *aucune* transaction. Il est
maintenant masqué aussi quand la série n'a qu'un point, et une ligne à sa place
dit que la courbe viendra — plutôt que de laisser une bande vide passer pour une
panne. Le sélecteur de période se masque avec lui.

## 6. Le widget ne ressemblait pas à l'app

`FlorinWidgets/` — fait

Il était en français en dur alors que l'app parle trois langues, peignait deux
violets qui lui étaient propres, restait sombre chez quelqu'un ayant choisi le
thème clair, et écrivait ses montants sans chiffres à chasse fixe.

Il lit maintenant le même `Strings.json` — inscrit dans les ressources de
l'extension, résolu depuis la langue que le snapshot transporte, parce qu'une
extension ne partage pas les préférences de l'app. Le fond reprend la
construction de `Backdrop` sur un plus petit canevas, et la teinte de l'Aperçu a
été remontée dans `Theme.swift` pour qu'il n'y en ait qu'une seule définition.
`Appearance` en est sorti : il lisait la table de traductions, ce qui rendait la
palette impartageable pour une raison qui n'avait rien à voir avec la couleur.

## À faire

Ces trois correctifs partiront dans la prochaine build Xcode Cloud. Rien ne
presse tant que la revue en cours porte sur les informations demandées et non
sur le binaire — mais si Apple redemande une build, ce sont ceux-là qu'elle doit
contenir.
