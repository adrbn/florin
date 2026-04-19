/**
 * importerTransactions — Enable Banking edition.
 *
 * Remplace l'ancien script YNAB. Récupère les transactions directement depuis
 * l'API Enable Banking (PSD2) en utilisant le même mécanisme d'auth JWT RS256
 * que Florin desktop/web.
 *
 * ===================== SETUP =====================
 *
 * Les credentials Enable Banking sont en dur ci-dessous (EB_APP_ID, EB_PRIVATE_KEY,
 * EB_SESSION_ID). Pour les mettre à jour :
 *   - EB_SESSION_ID expire après ~180 jours (PSD2). Reconnecte la banque dans
 *     Florin web et mets à jour la valeur ici.
 *   - Pour récupérer un nouveau session_id :
 *     ssh root@100.99.174.79 "pct exec 100 -- bash -c 'docker exec florin-db \
 *       psql -U florin -c \"SELECT session_id, aspsp_name FROM bank_connections WHERE status=\\\"active\\\";\"'"
 *
 * L'onglet "HISTORIQUE TRANSACTIONS" doit exister avec :
 *   - Ligne 1 : en-têtes
 *   - B2 : date de la dernière transaction importée
 *   - Colonnes : A=Account | B=Date | C=Outflow | D=Inflow | E=Payee |
 *                F=Category | G=Memo | H=Group | I=CategoryName | J=(vide) | K=ID
 *
 * ===================== LIMITES PSD2 =====================
 *
 * - Max 90 jours d'historique sans fresh SCA
 * - Certaines banques ne retournent pas toutes les infos (pas de payee, etc.)
 * - Les catégories n'existent pas côté Enable Banking (= pas de YNAB categories)
 *   → tu les remplis manuellement dans le sheet, la logique de "repair" les
 *   préserve lors des re-syncs.
 */

// =======================================================================
// ⚙️ CONFIGURATION
// =======================================================================
var EB_APP_ID = "6a8cb4ba-9c70-4377-b56b-2b303c49ceaa";
var EB_SESSION_ID = "8a420a42-8228-40cb-81d8-7bcfa3054945"; // La Banque Postale — expire ~180j
var EB_PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\n\
MIIJQgIBADANBgkqhkiG9w0BAQEFAASCCSwwggkoAgEAAoICAQCo4gmQV2iaxutP\n\
UtYwBXT9Qs7tDKhDGYEUMVgcBF9+truBx8ubLjaa0b+GlVlUsbkT2ho6hiqltq47\n\
kz3aovNH+5kCk9E4yCxiRqVjAICHp96UixirWLaJHNk5kSfCaZU2ir8JG1pJhkFW\n\
od5XDAq320Cd0lQOE5EuvN5XMtP//UIVb/GZpUTY8A4svMdBAPv3bhfiipFQGL9x\n\
EUZr5JTodgt7xsWJOLjnH7LkvPmzKBS3P0SAUy2VpSBJo6LS5t7jm/0XMIq+hDoC\n\
8YzEwCHt1cC8cwQkcwNIICyhy5enIgnCbjhAJtWrDWaB/zTH2YpWLrnsm12P49/6\n\
kebkc9CGGCVN4hBM/gQAvp9nML9r4zHc4fmNzql+V64Xqjp+tdVv9aHpiyH0fHUa\n\
v7XbAyMd141RsVgI/HMef3duY2oBhZXfDd4ZwYdKlOQQzd6OKbzQQEE1kTA9h5PK\n\
UwMLUNxGXgT2ETb4epCiaOXiv7opB9cGnNlC1CHtCnvcWRF0zXFX5bo0I7c9CQq1\n\
brEWkmMSdRJwYsD7tVmU9yS/phorVXLLxv4t3ZiDzXNVpWq4HvG5v1rp8yCCebVS\n\
INISIlNDGF7wZA3yF07zpifrnGDtjUF/8XYA2G6MBbLVCAHXKiOmq7CQx0oQkvdB\n\
eygFGT3rvtE+51pheWnIgUESAgoDtQIDAQABAoICAB6RZU5DR/uF6EcgFQU1o6aI\n\
rmghO56DkgXL5akSkI9gt2FG/t88duVAdFSBmVz3WyrQ9iDkMnlyrqg5Xz+A8Zx0\n\
mY4qH7tRnhj+tQZNq7YCKEtGPwWapdV9C4N8NtBdaITqCah2EzpOKurpmxMx6om7\n\
TX+Td6PhnkxxoqPxXwaNemXjcH1ROPw0PTiTRdSJ/1Fak8etMZ6oEBTA3fh+9AX8\n\
gdkaUhxjkDJDXk/BNcgcB93gPX+lrpFQxV6W2Ayo/ayAikelgWN5DwAD5SkiprGE\n\
GGHzxorrZ2tpaXKypWU6x73x0cwoy1Ft+EEs5oqK4Vt2kzAUshNumVajDIIKxXII\n\
zMv+RdxcmbqseEBBhVGnEXqzpo9tbrPjvmN8toQ+lwOIwT09+kBj8jCztjEvfM2u\n\
yItHgVpYudsJv3J7mFBJqSdlrTrzpPMEZ3uR92mHRODTBurG59emKbAzC8WVyNng\n\
mzjIII4VkeZUxD/VA0lgl4dxFjr8C0IaQexLDt5Xpu7X4aFt8dIJPF8CARcizaXg\n\
ck+iJxGm0D598QnoLc2tIxdwztRy04s5huqaceJsaf4eRkgTGbovKJRy7o2tixQh\n\
SMdkCtY+UFmebRK/Dg6Ev40945vRNagXcEkuxDPy2l3niZNmVCSD+WDDTpGDltnJ\n\
8wt62Se192Gy1QcXIGcRAoIBAQDQRkB1OAt9VswZrO5hR8476NWcv4lPG/sryHWy\n\
E/kj1Pie5FBpuMHMaj4+/PYaeKo7+1IZ/xRG+BwupNSL9HAvhCIpxAscMN6LFnVV\n\
+yoc+eNocN5v47ikBZD22opuX77MAhqIAc7CssoV4pvg3oXRap0kgQoHE5Pq4pey\n\
HaIKuqf3pPr4dZf/RERjUH7cbUu0du9lt1F78SaDlYDqjnwVAeOFUrajJBvH41to\n\
yQHIkCnlaGjedVxgD1oKsCExCRNY5WhtjLbsrB2yunCWfZzSw/yG+Y/5s/wNKEZY\n\
QwfSDD0G6NPOYAeeBTYd6y8DzY54IxYr5t9noxixWT/4qbVlAoIBAQDPlQMj6ijs\n\
MmdJD98KGfSmL+scFmQUuUQ1ugBn6G8XYifUERcJALzZzNAFMcskf+Patiwco9yQ\n\
OiseLXfrsiX3Lxpg4tr/6ltTsPsGZNAFetZFciHneapepCtp36SYQn6deVWqnmHd\n\
M8GH9G6tMoZ5gT4NSFpVAZGo+7QmsVLI0KvCEaJXuWX/qTnx/Y858DciPHLFzrRM\n\
vGx7yAGrb6zsGLFmTZ7N/QpU1mCkWb4Di0LgcKCR70pQ0Ipy8SC58IpZJQmWiijV\n\
6COvcXKgDRg+hvHJx9BPkkI2VJoiVn+k3r2Z+rVnoouxQN026c6WGO0IKd5jRJ83\n\
qkLNMphaPZgRAoIBAQC3g88z+egVzq8USI3a5bxQiX3/Gb3RGOSd1YnvGS5DZlqT\n\
FrXMEeGhTlP+iEIJXR0SsQXMpjeluOSMLOyjTQS0uYaoqnbnph/RCj7lPeQDmCPK\n\
WPmGOW7uB4GOIU4spuylMY1THdSjNYpe8kdLQodC2OAR1CmTxqplIrdrWDT5ozJx\n\
QMtqtaLyZ6Kip8DAVQWJw+p5A6gmv3uiIc9v3ZBzqjBhv1nyMdTQsgJPOB38LRrd\n\
arxMl7iHY7+A/2SfolGL2MfFD2H29ElOvHyL/a56//m4rJkx+mcy6LPi/V0ctW/o\n\
cKqAg5jyocDnZ90LSsooDTJyCIH8/Xa6fduiLVcJAoIBADIrImIospE7MUkwI8iO\n\
M1mC1UCpjLCRghG2DWkPfOHa4CNZqgaL/hhpbpEC0sTUf94ZDxow5BqbZFZbyNLW\n\
8GQIJ0jpKuKU4lOcv15xOPFKGcUY62bFOc67wJ5K5b3CvFUUwQaGVsKeQpS4F5OW\n\
VXfCK5wMM4C961U61/ROAOL1w70Yg/LNpQAgBxgcHuRy0PBeSaLS7TJqi5Fy6ixj\n\
xhgdc6p08f94u2l7kknGQq0amCQkNDpw6bYUYJGdAzrNDrKyx9lxNKNWAmHhekGC\n\
SKy78m3A8/B3ObdlxQatfxX6mzo+pF8Sos5JDe26nioahhbl/5BgQlayuIhdRQLy\n\
RfECggEAUaZOe9q6AFV/hUe6sHS0TjcGQPt+nqvOlXxiP7LpDsoj1U3cM1e37sBY\n\
fv0zKC8LimGVJtdMISZcDXXVOMsB14hKHOH5LdtnpP5C2782h7AyMs2ivm2hJH7Y\n\
NP2KQpPSZDadpZS67Fj7eZP3UVf262CQ9Q/LcMp0IC0r8EL4hDoABaT70tZaWpbE\n\
SYuhWEkDh3CzwYbEXUbajjw3L2Z+cgcRoTmp6vOqO2tSRVLgMi1JwobMmm3wnbDL\n\
mhg/6tELqoCN22D8G3Y1Fr1rHDIYivdP5jE850y/jn5qCnyuW8Cx0DLREDiCAgMs\n\
E5tnP6aMSbQudQ1gdqHnuhLLPygN2Q==\n\
-----END PRIVATE KEY-----";

var NOM_ONGLET_HISTO = "HISTORIQUE TRANSACTIONS";
var API_BASE = "https://api.enablebanking.com";
var JWT_LIFETIME_SEC = 50 * 60; // 50 minutes

// Mapping des noms de comptes Enable Banking → noms dans le sheet (pour matcher l'ancien YNAB)
var ACCOUNT_NAME_MAP = {
  "La Banque Postale": "CCP"
  // Ajouter d'autres mappings si besoin : "Nom EB": "Nom Sheet"
};

// =======================================================================
// 🔑 JWT RS256 — signature pure Apps Script (pas de lib externe)
// =======================================================================

/**
 * Encode bytes to base64url (RFC 4648 §5).
 */
function base64UrlEncode_(bytes) {
  return Utilities.base64Encode(bytes)
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

/**
 * Encode a string to base64url.
 */
function base64UrlEncodeString_(str) {
  return base64UrlEncode_(Utilities.newBlob(str).getBytes());
}

/**
 * Sign a JWT with RS256 using the PEM private key from Script Properties.
 * Apps Script doesn't have native RSA signing, so we use the
 * Utilities.computeRsaSha256Signature method available in Apps Script.
 */
function signJwt_() {
  if (!EB_APP_ID || !EB_PRIVATE_KEY) {
    throw new Error("❌ EB_APP_ID et EB_PRIVATE_KEY doivent être configurés en haut du script.");
  }

  var now = Math.floor(Date.now() / 1000);
  var header = { typ: "JWT", alg: "RS256", kid: EB_APP_ID };
  var payload = {
    iss: "enablebanking.com",
    aud: "api.enablebanking.com",
    iat: now,
    exp: now + JWT_LIFETIME_SEC
  };

  var headerB64 = base64UrlEncodeString_(JSON.stringify(header));
  var payloadB64 = base64UrlEncodeString_(JSON.stringify(payload));
  var signingInput = headerB64 + "." + payloadB64;

  var signatureBytes = Utilities.computeRsaSha256Signature(signingInput, EB_PRIVATE_KEY);
  var signatureB64 = base64UrlEncode_(signatureBytes);

  return signingInput + "." + signatureB64;
}

// =======================================================================
// 🌐 API HELPERS
// =======================================================================

/**
 * Authenticated GET request to Enable Banking API.
 */
function ebGet_(path, queryParams) {
  var jwt = signJwt_();
  var url = API_BASE + path;

  if (queryParams) {
    var parts = [];
    for (var key in queryParams) {
      if (queryParams[key] !== undefined && queryParams[key] !== null) {
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(queryParams[key]));
      }
    }
    if (parts.length > 0) url += "?" + parts.join("&");
  }

  var response = UrlFetchApp.fetch(url, {
    method: "get",
    headers: {
      Authorization: "Bearer " + jwt,
      Accept: "application/json"
    },
    muteHttpExceptions: true
  });

  var code = response.getResponseCode();
  var body = response.getContentText();

  if (code < 200 || code >= 300) {
    throw new Error("Enable Banking API " + code + " on GET " + path + " — " + body.substring(0, 300));
  }

  return JSON.parse(body);
}

// =======================================================================
// 🏦 ENABLE BANKING DATA HELPERS
// =======================================================================

/**
 * Extraire le nom du payee depuis une transaction Enable Banking.
 * Même logique de priorité que Florin (sync.ts:pickPayee).
 */
function pickPayee_(t) {
  if (t.creditor && t.creditor.name) return t.creditor.name;
  if (t.debtor && t.debtor.name) return t.debtor.name;
  if (t.remittance_information_unstructured) return t.remittance_information_unstructured;
  if (t.remittance_information && t.remittance_information.length > 0) {
    return t.remittance_information.join(" ").trim();
  }
  if (t.bank_transaction_code && t.bank_transaction_code.description) {
    return t.bank_transaction_code.description;
  }
  return "(unknown)";
}

/**
 * Choisir la date effective (value_date > booking_date > aujourd'hui),
 * puis écraser avec la date réelle trouvée dans le payee/memo si présente.
 */
function pickDate_(t) {
  var raw = t.value_date || t.booking_date;
  var d = (raw && !isNaN(new Date(raw).getTime())) ? new Date(raw) : new Date();

  // Détecteur de date réelle dans le texte (ex: "13.04.26" → 13 avril 2026)
  var payee = pickPayee_(t);
  var memo = t.note || "";
  var text = payee + " " + memo;
  var dateMatch = text.match(/(\d{1,2})[\.\/](\d{1,2})[\.\/](\d{2,4})/);
  if (dateMatch) {
    var j = parseInt(dateMatch[1], 10);
    var m = parseInt(dateMatch[2], 10) - 1;
    var a = dateMatch[3];
    if (a.length === 2) a = "20" + a;
    var dateTrouvee = new Date(parseInt(a, 10), m, j);
    if (!isNaN(dateTrouvee.getTime())) d = dateTrouvee;
  }

  return d;
}

/**
 * Montant signé : négatif pour les débits.
 */
function signedAmount_(t) {
  var raw = t.transaction_amount.amount;
  var num = parseFloat(raw);
  if (raw.charAt(0) === "-" || raw.charAt(0) === "+") return num;
  if (t.credit_debit_indicator === "DBIT") return -Math.abs(num);
  return Math.abs(num);
}

/**
 * ID externe unique pour dédoublonnage.
 */
function externalId_(t) {
  return t.transaction_id || t.entry_reference || null;
}

/**
 * Fetch toutes les transactions d'un compte avec pagination.
 */
function fetchAllTransactions_(accountUid, dateFrom, dateTo) {
  var allTx = [];
  var continuationKey = undefined;

  do {
    var params = {
      date_from: dateFrom,
      date_to: dateTo
    };
    if (continuationKey) params.continuation_key = continuationKey;

    var page = ebGet_("/accounts/" + encodeURIComponent(accountUid) + "/transactions", params);
    if (page.transactions && page.transactions.length > 0) {
      allTx = allTx.concat(page.transactions);
    }
    continuationKey = page.continuation_key || null;
  } while (continuationKey);

  return allTx;
}

// =======================================================================
// 🚀 FONCTION PRINCIPALE
// =======================================================================

function importerTransactions() {
  if (!EB_SESSION_ID) {
    Logger.log("❌ EB_SESSION_ID manquant en haut du script.");
    return;
  }
  var sessionId = EB_SESSION_ID;

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(NOM_ONGLET_HISTO);
  if (!sheet) { Logger.log("❌ Onglet '" + NOM_ONGLET_HISTO + "' introuvable."); return; }

  // 1. DATES & TIMEZONE
  var lastDateValue = sheet.getRange(2, 2).getValue();
  if (!(lastDateValue instanceof Date)) {
    Logger.log("⚠️ B2 n'est pas une date valide !");
    return;
  }
  var timeZone = ss.getSpreadsheetTimeZone();
  var sinceDateNew = Utilities.formatDate(lastDateValue, timeZone, "yyyy-MM-dd");

  // Date de repair : 15 jours avant B2 (pour mettre à jour les catégories)
  var repairDate = new Date(lastDateValue.getTime() - (15 * 24 * 60 * 60 * 1000));
  var sinceDateRepair = Utilities.formatDate(repairDate, timeZone, "yyyy-MM-dd");

  // PSD2 cap : max 90 jours en arrière
  var psd2Floor = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
  var psd2FloorStr = Utilities.formatDate(psd2Floor, timeZone, "yyyy-MM-dd");

  // Clamp les dates de recherche au plancher PSD2
  if (sinceDateRepair < psd2FloorStr) sinceDateRepair = psd2FloorStr;
  if (sinceDateNew < psd2FloorStr) sinceDateNew = psd2FloorStr;

  var today = Utilities.formatDate(new Date(), timeZone, "yyyy-MM-dd");

  // 2. RÉCUPÉRATION DES IDS ET SIGNATURES EXISTANTS (500 dernières lignes)
  var lastRow = sheet.getLastRow();
  var scanRows = Math.min(500, Math.max(0, lastRow - 1));
  var existingIds = [];
  var existingSignatures = [];

  if (scanRows > 0) {
    var rangeData = sheet.getRange(2, 1, scanRows, 11);
    var existingData = rangeData.getValues();

    for (var k = 0; k < existingData.length; k++) {
      var id = existingData[k][10]; // Col K = ID
      if (id && id !== "") existingIds.push(String(id));

      if (existingData[k][1] instanceof Date) {
        var d = Utilities.formatDate(existingData[k][1], timeZone, "yyyy-MM-dd");
        var outRound = Math.round((existingData[k][2] || 0) * 100) / 100;
        var inRound = Math.round((existingData[k][3] || 0) * 100) / 100;
        existingSignatures.push(d + "|" + outRound + "|" + inRound);
      }
    }
  }

  try {
    // 3. FETCH SESSION → liste des comptes
    Logger.log("🔗 Récupération de la session Enable Banking...");
    var session = ebGet_("/sessions/" + encodeURIComponent(sessionId));

    if (session.status !== "AUTHORIZED") {
      Logger.log("❌ Session " + session.status + " — reconnecte la banque dans Florin et mets à jour EB_SESSION_ID.");
      return;
    }

    var accountUids = session.accounts || [];
    Logger.log("📋 " + accountUids.length + " compte(s) trouvé(s) dans la session.");

    // 4. FETCH TRANSACTIONS POUR CHAQUE COMPTE
    var allTransactions = [];

    for (var a = 0; a < accountUids.length; a++) {
      var uid = accountUids[a];

      // Récupérer les détails du compte (nom, IBAN)
      var details;
      try {
        details = ebGet_("/accounts/" + encodeURIComponent(uid) + "/details");
      } catch (e) {
        Logger.log("⚠️ Impossible de récupérer les détails du compte " + uid + " : " + e);
        continue;
      }

      var rawName = details.product
        || (details.account_id && details.account_id.iban
            ? session.aspsp.name + " ·" + details.account_id.iban.slice(-4)
            : null)
        || details.name
        || session.aspsp.name;

      // Chercher un mapping custom, d'abord par nom exact, puis par préfixe (aspsp)
      var accountName = ACCOUNT_NAME_MAP[rawName] || ACCOUNT_NAME_MAP[session.aspsp.name] || rawName;

      Logger.log("🏦 Fetch transactions pour : " + accountName);

      // Fetch le flux large (depuis sinceDateRepair) pour couvrir le repair + les nouvelles
      var txList;
      try {
        txList = fetchAllTransactions_(uid, sinceDateRepair, today);
      } catch (e) {
        Logger.log("⚠️ Erreur fetch transactions pour " + accountName + " : " + e);
        continue;
      }

      // Attacher le nom du compte à chaque transaction
      for (var ti = 0; ti < txList.length; ti++) {
        txList[ti]._accountName = accountName;
      }

      allTransactions = allTransactions.concat(txList);
      Logger.log("   → " + txList.length + " transaction(s) récupérée(s).");
    }

    // -------------------------------------------------------------------------
    // 🔄 ÉTAPE 1 : RE-SYNCHRONISATION DES LIGNES SANS CATÉGORIE
    // -------------------------------------------------------------------------
    // Enable Banking ne fournit pas de catégories, mais cette logique préserve
    // les catégories que tu as ajoutées manuellement dans le sheet.
    // Si une ligne a déjà une catégorie → on n'y touche pas.
    // Cette étape est gardée pour compatibilité avec le workflow existant.
    Logger.log("🔎 Vérification des catégories manquantes (15 derniers jours)...");

    if (scanRows > 0) {
      var checkCount = Math.min(150, scanRows);
      var checkRange = sheet.getRange(2, 1, checkCount, 11);
      var dataRows = checkRange.getValues();
      // Note : pas de mise à jour auto des catégories ici car Enable Banking
      // n'en fournit pas. Les catégories sont gérées manuellement.
      // La structure est gardée pour un futur système de rules automatiques.
    }

    // -------------------------------------------------------------------------
    // ➕ ÉTAPE 2 : AJOUT DES NOUVELLES TRANSACTIONS
    // -------------------------------------------------------------------------
    var rowsToAdd = [];

    // Filtrer : seulement >= sinceDateNew ET pas déjà importées
    var newTransactions = allTransactions.filter(function(t) {
      var tDate = (t.value_date || t.booking_date || "");
      var tId = externalId_(t);
      return tDate >= sinceDateNew && (!tId || existingIds.indexOf(tId) === -1);
    });

    // Pré-calculer la date finale (avec détecteur de date réelle) sur chaque transaction
    for (var p = 0; p < newTransactions.length; p++) {
      newTransactions[p]._finalDate = pickDate_(newTransactions[p]);
    }

    // Trier par date finale décroissante (les plus récentes en haut)
    newTransactions.sort(function(a, b) {
      var da = a._finalDate.getTime();
      var db = b._finalDate.getTime();
      if (da !== db) return db - da;
      var ma = parseFloat(a.transaction_amount.amount) || 0;
      var mb = parseFloat(b.transaction_amount.amount) || 0;
      return ma - mb;
    });

    for (var i = 0; i < newTransactions.length; i++) {
      var t = newTransactions[i];

      // Skip si pas d'ID (pas de dédoublonnage possible)
      var tExtId = externalId_(t);

      // Skip les transactions en pending
      if (t.status === "PDNG") continue;

      var amount = signedAmount_(t);
      var outflow = 0, inflow = 0;
      if (amount < 0) outflow = Math.abs(amount); else inflow = amount;

      // Check signature pour les transactions sans ID externe
      if (!tExtId) {
        var tDate = t.value_date || t.booking_date || "";
        var tSignature = tDate + "|" + (Math.round(outflow * 100) / 100) + "|" + (Math.round(inflow * 100) / 100);
        if (existingSignatures.indexOf(tSignature) > -1) continue;
      }

      var dateDeTransaction = t._finalDate;
      var payee = pickPayee_(t);
      var memo = t.note || "";
      var accountName = t._accountName || "";

      // Colonnes : A=Account | B=Date | C=Outflow | D=Inflow | E=Payee |
      //            F=Category | G=Memo | H=Group | I=CategoryName | J=(vide) | K=ID
      rowsToAdd.push([
        accountName,          // A - Account
        dateDeTransaction,    // B - Date
        outflow,              // C - Outflow
        inflow,               // D - Inflow
        payee,                // E - Payee
        "",                   // F - Category (combiné — à remplir manuellement)
        memo,                 // G - Memo
        "",                   // H - Group (à remplir manuellement)
        "",                   // I - CategoryName (à remplir manuellement)
        "",                   // J - (vide)
        tExtId || ""          // K - ID (transaction_id ou entry_reference)
      ]);
    }

    if (rowsToAdd.length > 0) {
      sheet.insertRowsAfter(1, rowsToAdd.length);
      sheet.getRange(2, 1, rowsToAdd.length, 11).setValues(rowsToAdd);

      // RESTAURATION STYLE
      var rowSourceForFormat = 2 + rowsToAdd.length;
      if (rowSourceForFormat <= sheet.getLastRow()) {
        sheet.getRange(rowSourceForFormat, 1, 1, 9).copyFormatToRange(sheet, 1, 9, 2, 2 + rowsToAdd.length - 1);
      }

      Logger.log("✅ " + rowsToAdd.length + " nouvelle(s) transaction(s) ajoutée(s).");
    } else {
      Logger.log("😴 Tout est déjà à jour.");
    }

  } catch (e) {
    Logger.log("❌ Erreur : " + e);
  }
}

// =======================================================================
// 🔧 UTILITAIRES
// =======================================================================

/**
 * Fonction de test : vérifie que la connexion à Enable Banking fonctionne.
 * Exécute-la une première fois pour valider ta config.
 */
function testConnexionEB() {
  if (!EB_SESSION_ID) {
    Logger.log("❌ EB_SESSION_ID manquant en haut du script.");
    return;
  }
  var sessionId = EB_SESSION_ID;

  try {
    var session = ebGet_("/sessions/" + encodeURIComponent(sessionId));
    Logger.log("✅ Connexion OK !");
    Logger.log("   Status : " + session.status);
    Logger.log("   Banque : " + session.aspsp.name + " (" + session.aspsp.country + ")");
    Logger.log("   Comptes : " + (session.accounts || []).length);
    Logger.log("   Expire : " + (session.access && session.access.valid_until || "?"));

    var accounts = session.accounts || [];
    for (var i = 0; i < accounts.length; i++) {
      try {
        var det = ebGet_("/accounts/" + encodeURIComponent(accounts[i]) + "/details");
        var name = det.product || det.name || (det.account_id && det.account_id.iban) || accounts[i];
        Logger.log("   → " + name + " (" + det.currency + ")");
      } catch (e) {
        Logger.log("   → " + accounts[i] + " (détails indisponibles)");
      }
    }
  } catch (e) {
    Logger.log("❌ Erreur : " + e);
  }
}
