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

## À faire

Ces trois correctifs partiront dans la prochaine build Xcode Cloud. Rien ne
presse tant que la revue en cours porte sur les informations demandées et non
sur le binaire — mais si Apple redemande une build, ce sont ceux-là qu'elle doit
contenir.
