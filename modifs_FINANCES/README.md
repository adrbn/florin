# modifs_FINANCES — Google Sheets import scripts

## Fichiers

| Fichier | Description |
|---------|-------------|
| `importerTransactions_YNAB_backup.gs` | Script original YNAB (backup). Nécessite un abonnement YNAB actif. |
| `importerTransactions_EnableBanking.gs` | Script adapté pour Enable Banking (PSD2). Utilise la même API que Florin. |

## Setup Enable Banking

Les credentials sont déjà en dur dans le script (app_id, clé privée, session_id La Banque Postale).

### Tester

Exécuter `testConnexionEB()` dans Apps Script pour vérifier que tout fonctionne.

### Maintenance

- Le session PSD2 expire après ~180 jours → reconnecter la banque dans Florin web et mettre à jour `EB_SESSION_ID` dans le script
- Pour récupérer un nouveau session_id :
  ```bash
  ssh root@100.99.174.79 "pct exec 100 -- bash -c 'docker exec florin-db \
    psql -U florin -c \"SELECT session_id, aspsp_name FROM bank_connections WHERE status=\\\"active\\\";\"'"
  ```
- Les catégories sont à remplir manuellement dans le sheet (Enable Banking n'en fournit pas)
