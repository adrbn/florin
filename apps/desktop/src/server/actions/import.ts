'use server'

import { revalidatePath } from 'next/cache'
import { mutations } from '@/db/client'
import type { ActionResult } from '@florin/core/types'

interface ParsedTransaction {
  occurredAt: string
  amount: number
  payee: string
  memo?: string
}

interface ImportResult {
  imported: number
  skipped: number
  errors: string[]
}

/**
 * Parse CSV content into transactions.
 * Supports common bank CSV formats:
 * - Date, Description/Payee, Amount
 * - Date, Description/Payee, Debit, Credit
 * Auto-detects column mapping from headers.
 */
function parseCSV(content: string): ParsedTransaction[] {
  const lines = content.trim().split(/\r?\n/)
  if (lines.length < 2) return []

  const header = lines[0]!.toLowerCase()
  const separator = header.includes('\t') ? '\t' : header.includes(';') ? ';' : ','

  function splitRow(line: string): string[] {
    const result: string[] = []
    let current = ''
    let inQuotes = false
    for (const ch of line) {
      if (ch === '"') {
        inQuotes = !inQuotes
      } else if (ch === separator && !inQuotes) {
        result.push(current.trim())
        current = ''
      } else {
        current += ch
      }
    }
    result.push(current.trim())
    return result
  }

  const headers = splitRow(lines[0]!)

  // Find column indices
  const dateIdx = headers.findIndex((h) => /date|datum|valeur/i.test(h))
  const payeeIdx = headers.findIndex((h) => /payee|description|libellé|libelle|label|merchant|name|beneficiary/i.test(h))
  const amountIdx = headers.findIndex((h) => /^amount$|^montant$|^betrag$/i.test(h))
  const debitIdx = headers.findIndex((h) => /debit|débit|ausgabe/i.test(h))
  const creditIdx = headers.findIndex((h) => /credit|crédit|einnahme/i.test(h))
  const memoIdx = headers.findIndex((h) => /memo|note|reference|référence/i.test(h))

  if (dateIdx === -1) throw new Error('Could not find a date column in CSV headers')
  if (payeeIdx === -1 && amountIdx === -1) throw new Error('Could not find payee or amount columns in CSV headers')

  const transactions: ParsedTransaction[] = []

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i]!.trim()
    if (!line) continue

    const cols = splitRow(line)

    const rawDate = cols[dateIdx] ?? ''
    const date = parseDate(rawDate)
    if (!date) continue

    let amount: number
    if (amountIdx !== -1) {
      amount = parseAmount(cols[amountIdx] ?? '0')
    } else if (debitIdx !== -1 && creditIdx !== -1) {
      const debit = parseAmount(cols[debitIdx] ?? '0')
      const credit = parseAmount(cols[creditIdx] ?? '0')
      amount = credit > 0 ? credit : -Math.abs(debit)
    } else {
      continue
    }

    if (amount === 0) continue

    const payee = cols[payeeIdx ?? amountIdx] ?? 'Unknown'
    const memo = memoIdx !== -1 ? cols[memoIdx] : undefined

    transactions.push({
      occurredAt: date,
      amount,
      payee: payee.trim(),
      memo: memo?.trim() || undefined,
    })
  }

  return transactions
}

/**
 * Parse OFX/QFX content into transactions.
 * OFX is an XML-like format used by many banks for statement export.
 */
function parseOFX(content: string): ParsedTransaction[] {
  const transactions: ParsedTransaction[] = []

  // Extract STMTTRN blocks
  const stmtTrnRegex = /<STMTTRN>([\s\S]*?)<\/STMTTRN>/gi
  let match

  while ((match = stmtTrnRegex.exec(content)) !== null) {
    const block = match[1]!

    const dtPosted = extractOFXTag(block, 'DTPOSTED')
    const amount = extractOFXTag(block, 'TRNAMT')
    const name = extractOFXTag(block, 'NAME')
    const memo = extractOFXTag(block, 'MEMO')

    if (!dtPosted || !amount) continue

    // OFX date format: YYYYMMDD or YYYYMMDDHHMMSS
    const year = dtPosted.substring(0, 4)
    const month = dtPosted.substring(4, 6)
    const day = dtPosted.substring(6, 8)
    const dateStr = `${year}-${month}-${day}`

    transactions.push({
      occurredAt: dateStr,
      amount: parseFloat(amount),
      payee: (name ?? memo ?? 'Unknown').trim(),
      memo: memo?.trim() || undefined,
    })
  }

  // Also handle SGML-style OFX (no closing tags)
  if (transactions.length === 0) {
    const sgmlBlocks = content.split(/<STMTTRN>/i).slice(1)
    for (const block of sgmlBlocks) {
      const dtPosted = extractSGMLTag(block, 'DTPOSTED')
      const amount = extractSGMLTag(block, 'TRNAMT')
      const name = extractSGMLTag(block, 'NAME')
      const memo = extractSGMLTag(block, 'MEMO')

      if (!dtPosted || !amount) continue

      const year = dtPosted.substring(0, 4)
      const month = dtPosted.substring(4, 6)
      const day = dtPosted.substring(6, 8)
      const dateStr = `${year}-${month}-${day}`

      transactions.push({
        occurredAt: dateStr,
        amount: parseFloat(amount),
        payee: (name ?? memo ?? 'Unknown').trim(),
        memo: memo?.trim() || undefined,
      })
    }
  }

  return transactions
}

function extractOFXTag(block: string, tag: string): string | undefined {
  const regex = new RegExp(`<${tag}>([^<]+)`, 'i')
  return regex.exec(block)?.[1]?.trim()
}

function extractSGMLTag(block: string, tag: string): string | undefined {
  const regex = new RegExp(`<${tag}>(.+)`, 'im')
  return regex.exec(block)?.[1]?.trim()
}

function parseDate(raw: string): string | null {
  // Try common date formats
  // YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw
  // DD/MM/YYYY or DD-MM-YYYY (European)
  const eu = raw.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$/)
  if (eu) return `${eu[3]}-${eu[2]!.padStart(2, '0')}-${eu[1]!.padStart(2, '0')}`
  // MM/DD/YYYY (US)
  const us = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/)
  if (us) {
    const m = parseInt(us[1]!, 10)
    const d = parseInt(us[2]!, 10)
    // Heuristic: if first number > 12, it's DD/MM/YYYY
    if (m > 12) return `${us[3]}-${us[2]!.padStart(2, '0')}-${us[1]!.padStart(2, '0')}`
    return `${us[3]}-${us[1]!.padStart(2, '0')}-${us[2]!.padStart(2, '0')}`
  }
  // Try Date.parse as fallback
  const d = new Date(raw)
  if (!isNaN(d.getTime())) {
    return d.toISOString().split('T')[0]!
  }
  return null
}

function parseAmount(raw: string): number {
  // Handle European format: 1.234,56 → 1234.56
  let cleaned = raw.replace(/[^\d.,\-+]/g, '')
  // If comma is the decimal separator (European)
  if (/,\d{1,2}$/.test(cleaned)) {
    cleaned = cleaned.replace(/\./g, '').replace(',', '.')
  }
  const num = parseFloat(cleaned)
  return isNaN(num) ? 0 : num
}

export async function importTransactions(
  accountId: string,
  fileContent: string,
  fileName: string,
): Promise<ActionResult<ImportResult>> {
  try {
    const ext = fileName.toLowerCase().split('.').pop() ?? ''
    let parsed: ParsedTransaction[]

    if (ext === 'ofx' || ext === 'qfx') {
      parsed = parseOFX(fileContent)
    } else {
      // Default to CSV
      parsed = parseCSV(fileContent)
    }

    if (parsed.length === 0) {
      return { success: false, error: 'No transactions found in file' }
    }

    let imported = 0
    let skipped = 0
    const errors: string[] = []

    for (const tx of parsed) {
      try {
        const result = await mutations.addTransaction({
          accountId,
          occurredAt: new Date(tx.occurredAt),
          amount: tx.amount,
          payee: tx.payee,
          memo: tx.memo ?? null,
        })
        if (result.success) {
          imported++
        } else {
          skipped++
        }
      } catch {
        skipped++
        if (errors.length < 5) {
          errors.push(`Row: ${tx.payee} on ${tx.occurredAt}`)
        }
      }
    }

    revalidatePath('/transactions')
    revalidatePath('/accounts')
    revalidatePath('/')

    return {
      success: true,
      data: { imported, skipped, errors },
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to parse file'
    return { success: false, error: message }
  }
}
