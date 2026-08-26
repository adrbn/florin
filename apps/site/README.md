# Le site de Florin

Deux pages statiques et un fichier d'association. Il n'y a pas de serveur ici et
il ne doit jamais y en avoir : c'est du contenu figé, servi par un CDN.

## Pourquoi il existe

Enable Banking n'accepte que des URI de redirection en `https` — un schéma
d'application comme `florin://` est refusé par leur console. La redirection
après la connexion bancaire passe donc par une vraie URL https qu'iOS
intercepte et route vers l'app : un *universal link*.

Pour qu'iOS accepte de router une adresse vers Florin, il lit une fois
`/.well-known/apple-app-site-association` à la racine du domaine. Ce fichier
nomme l'app autorisée (`2TWQF4T93E.com.adrbn.florin`) et le chemin concerné
(`/banking/callback`). Il est lu à l'installation, pas à chaque connexion — il
n'est jamais dans le chemin critique d'une synchro.

## Déployer

N'importe quel hébergeur statique convient, à condition de contrôler la
**racine** du domaine : Apple ne lit ce fichier nulle part ailleurs.

```
npx wrangler pages deploy apps/site --project-name florin
```

Deux exigences, toutes deux satisfaites par défaut sur Cloudflare Pages,
Netlify et GitHub Pages :

- servi en `https`, sans redirection ;
- servi tel quel, sans en-tête `Content-Type` particulier — Apple accepte
  aujourd'hui `application/json` comme du texte brut, mais le fichier ne doit
  pas porter d'extension `.json`.

## Une fois déployé

1. Reporter le domaine obtenu dans `BankingFlow.redirectHost`.
2. Ajouter `applinks:<domaine>` aux Associated Domains de la cible iOS.
3. Enregistrer `https://<domaine>/banking/callback` comme URI de redirection
   dans la console Enable Banking.

Les trois doivent concorder. S'ils divergent, la banque refuse la demande avant
même d'afficher une page de connexion, et son message ne dit pas lequel des
trois est en cause.

## Ne pas changer de domaine à la légère

Ce domaine fait partie de l'identité de l'app. S'il cesse de répondre, les
universal links cassent pour toutes les installations existantes — pas
seulement pour les nouvelles.
