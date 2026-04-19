/**
 * BACKUP — Script YNAB original (avant migration Enable Banking).
 * Fonctionnait avec un token YNAB et un budget_id.
 * Conservé pour restauration si ré-abonnement YNAB.
 */
function importerTransactions() {
  // =======================================================
  // ⚙️ CONFIGURATION
  // =======================================================
  var YNAB_TOKEN = "rd7zO32W38WQ29FnCsYy5_-U4iNgWbL4eNcf2dlWq3E";
  var BUDGET_ID = "43e3424f-42b7-4a2d-ae5e-0b4e9b9c937f";
  var NOM_ONGLET_HISTO = "HISTORIQUE TRANSACTIONS";

  // =======================================================
  // 🚀 LE MOTEUR
  // =======================================================
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(NOM_ONGLET_HISTO);
  if (!sheet) { Logger.log("❌ Erreur : Onglet introuvable."); return; }

  // 1. DATES & TIMEZONE
  var lastDateValue = sheet.getRange(2, 2).getValue();
  if (!(lastDateValue instanceof Date)) {
    Logger.log("⚠️ ALERTE : B2 n'est pas une date valide !");
    return;
  }
  var timeZone = ss.getSpreadsheetTimeZone();

  // On définit deux dates de recherche :
  // - Depuis B2 pour les nouvelles transactions
  // - 15 jours avant B2 pour aller repêcher les "Uncategorized" mis à jour
  var sinceDateNew = Utilities.formatDate(lastDateValue, timeZone, "yyyy-MM-dd");
  var repairDate = new Date(lastDateValue.getTime() - (15 * 24 * 60 * 60 * 1000));
  var sinceDateRepair = Utilities.formatDate(repairDate, timeZone, "yyyy-MM-dd");

  // 2. RÉCUPÉRATION DES IDS ET SIGNATURES EXISTANTS (500 dernières lignes)
  var rangeData = sheet.getRange(2, 1, 500, 11);
  var existingData = rangeData.getValues();
  var existingIds = [];
  var existingSignatures = [];

  for (var k = 0; k < existingData.length; k++) {
    var id = existingData[k][10];
    if (id && id !== "") existingIds.push(id);
    if (existingData[k][1] instanceof Date) {
      var d = Utilities.formatDate(existingData[k][1], timeZone, "yyyy-MM-dd");
      var outRound = Math.round((existingData[k][2] || 0) * 100) / 100;
      var inRound = Math.round((existingData[k][3] || 0) * 100) / 100;
      existingSignatures.push(d + "|" + outRound + "|" + inRound);
    }
  }

  var options = { "headers": { "Authorization": "Bearer " + YNAB_TOKEN } };
  var categoryMap = {};

  try {
    // 3. FETCH CATEGORIES
    var repCat = UrlFetchApp.fetch("https://api.ynab.com/v1/budgets/" + BUDGET_ID + "/categories", options);
    var groups = JSON.parse(repCat.getContentText()).data.category_groups;
    for (var g = 0; g < groups.length; g++) {
      for (var c = 0; c < groups[g].categories.length; c++) {
        categoryMap[groups[g].categories[c].id] = groups[g].name;
      }
    }

    // 4. FETCH TRANSACTIONS (On prend le flux large pour la réparation)
    var repTrans = UrlFetchApp.fetch("https://api.ynab.com/v1/budgets/" + BUDGET_ID + "/transactions?since_date=" + sinceDateRepair, options);
    var allTransactions = JSON.parse(repTrans.getContentText()).data.transactions;

    // -------------------------------------------------------------------------
    // 🔄 ÉTAPE 1 : RE-SYNCHRONISATION DES LIGNES "UNCATEGORIZED"
    // -------------------------------------------------------------------------
    Logger.log("🔎 Vérification des lignes à mettre à jour (15 derniers jours)...");
    var checkRange = sheet.getRange(2, 1, 150, 11);
    var dataRows = checkRange.getValues();
    var hasChanged = false;

    for (var r = 0; r < dataRows.length; r++) {
      var currentCat = dataRows[r][8]; // Col I
      var currentId = dataRows[r][10]; // Col K

      if (currentId && (currentCat === "Uncategorized" || currentCat === "" || !currentCat)) {
        var updatedT = allTransactions.find(function(item) { return item.id === currentId; });

        if (updatedT && updatedT.category_name && updatedT.category_name !== "Uncategorized") {
          var gName = categoryMap[updatedT.category_id] || "";
          var cName = updatedT.category_name || "";
          if (gName === "Internal Master Category" || gName === "Inflow") gName = "Revenus";

          dataRows[r][5] = (gName && cName) ? (gName + ": " + cName) : "";
          dataRows[r][6] = updatedT.memo;
          dataRows[r][7] = gName;
          dataRows[r][8] = cName;
          hasChanged = true;
          Logger.log("✨ Réparation : " + updatedT.payee_name + " -> " + cName);
        }
      }
    }
    if (hasChanged) checkRange.setValues(dataRows);

    // -------------------------------------------------------------------------
    // ➕ ÉTAPE 2 : AJOUT DES NOUVELLES TRANSACTIONS
    // -------------------------------------------------------------------------
    var rowsToAdd = [];
    // On filtre : seulement ce qui est >= B2 ET pas déjà dans nos IDs
    var newTransactions = allTransactions.filter(function(t) {
      return t.date >= sinceDateNew && existingIds.indexOf(t.id) === -1;
    }).reverse();

    for (var i = 0; i < newTransactions.length; i++) {
      var t = newTransactions[i];
      if (t.deleted || t.transfer_account_id !== null || t.payee_name === "Starting Balance") continue;

      var outflow = 0, inflow = 0;
      var amount = t.amount / 1000;
      if (amount < 0) outflow = Math.abs(amount); else inflow = amount;

      // Check final par signature pour les lignes sans ID
      var tSignature = t.date + "|" + (Math.round(outflow*100)/100) + "|" + (Math.round(inflow*100)/100);
      if (existingSignatures.indexOf(tSignature) > -1) continue;

      // --- 🚨 LE NOUVEAU DÉTECTEUR DE DATE RÉELLE 🚨 ---
      var dateDeTransaction = new Date(t.date); // Date YNAB de base
      var textePourRecherche = t.payee_name + " " + (t.memo || "");
      // Cette regex cherche un motif comme "28.03.26" ou "28/03/26"
      var dateMatch = textePourRecherche.match(/(\d{1,2})[\.\/](\d{1,2})[\.\/](\d{2,4})/);

      if (dateMatch) {
        var j = parseInt(dateMatch[1], 10);
        var m = parseInt(dateMatch[2], 10) - 1; // JS compte les mois de 0 à 11
        var a = dateMatch[3];
        if (a.length === 2) a = "20" + a; // "26" devient "2026"

        var dateTrouvee = new Date(a, m, j);
        // Si la date est valide, on écrase la date de YNAB
        if (!isNaN(dateTrouvee.getTime())) {
          dateDeTransaction = dateTrouvee;
        }
      }
      // ------------------------------------------------

      var groupName = categoryMap[t.category_id] || "";
      var categoryName = t.category_name || "";
      if (groupName === "Internal Master Category" || groupName === "Inflow") groupName = "Revenus";
      var combinedCategory = (groupName && categoryName) ? (groupName + ": " + categoryName) : "";

      // ⚠️ On utilise `dateDeTransaction` ici au lieu de `new Date(t.date)`
      rowsToAdd.push([t.account_name, dateDeTransaction, outflow, inflow, t.payee_name, combinedCategory, t.memo, groupName, categoryName, "", t.id]);
    }

    if (rowsToAdd.length > 0) {
      sheet.insertRowsAfter(1, rowsToAdd.length);
      sheet.getRange(2, 1, rowsToAdd.length, 11).setValues(rowsToAdd);

      // RESTAURATION STYLE
      var rowSourceForFormat = 2 + rowsToAdd.length;
      sheet.getRange(rowSourceForFormat, 1, 1, 9).copyFormatToRange(sheet, 1, 9, 2, 2 + rowsToAdd.length - 1);

      Logger.log("✅ " + rowsToAdd.length + " nouvelles transactions ajoutées.");
    } else {
      Logger.log("😴 Tout est déjà à jour.");
    }

  } catch (e) {
    Logger.log("❌ Erreur : " + e);
  }
}
