import * as XLSX from 'xlsx'

const path = process.argv[2]
const wb = XLSX.readFile(path)
console.log('Sheets:', wb.SheetNames)
const actifs = XLSX.utils.sheet_to_json(wb.Sheets['ACTIFS'], { header: 1, defval: null })
console.log('\n=== ACTIFS (first 20 rows) ===')
for (let i = 0; i < Math.min(20, actifs.length); i++) {
  console.log(i, JSON.stringify(actifs[i]))
}

const hist = XLSX.utils.sheet_to_json(wb.Sheets['HISTORIQUE TRANSACTIONS'], {
  header: 1,
  defval: null,
})
console.log('\n=== HISTORIQUE row 0 (header) ===')
console.log(JSON.stringify(hist[0]))

// Unique account names in transactions (column 0)
const accNames = new Set()
for (let i = 1; i < hist.length; i++) {
  if (hist[i] && hist[i][0]) accNames.add(String(hist[i][0]).trim())
}
console.log('\n=== Unique account names in HISTORIQUE column 0 ===')
for (const n of [...accNames].sort()) console.log('-', JSON.stringify(n))

// SUIVI SOLDE last 5 rows
const suivi = XLSX.utils.sheet_to_json(wb.Sheets['SUIVI SOLDE'], { header: 1, defval: null })
console.log('\n=== SUIVI SOLDE last 6 rows ===')
for (let i = Math.max(0, suivi.length - 6); i < suivi.length; i++) {
  console.log(i, JSON.stringify(suivi[i]))
}
