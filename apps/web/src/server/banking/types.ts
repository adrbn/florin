/**
 * TypeScript shapes for the subset of the Enable Banking API that Florin
 * actually consumes. Documented at https://enablebanking.com/docs/api/reference
 *
 * These intentionally only model the fields we use — Enable Banking returns a
 * lot more (foreign currency exchange info, regulatory metadata, etc.) but we
 * keep the surface area small so the typed boundary stays honest.
 */

export interface Aspsp {
  /** Bank name as Enable Banking advertises it (e.g. "La Banque Postale"). */
  name: string
  /** ISO 3166-1 alpha-2 country code (e.g. "FR"). */
  country: string
  /** Logo URL — handy for the bank picker UI. */
  logo?: string
  /** Maximum consent duration (days) the bank allows. We pin to this on POST /auth. */
  maximum_consent_validity?: number
  /** Authentication methods supported. We only handle 'redirect'. */
  auth_methods?: ReadonlyArray<{
    name: string
    title?: string
    psu_types?: ReadonlyArray<'personal' | 'business'>
  }>
}

export interface AspspListResponse {
  aspsps: ReadonlyArray<Aspsp>
}

export interface StartAuthRequest {
  /** When this consent should expire (ISO 8601 with Z). PSD2 caps at ~180 days. */
  access: {
    valid_until: string
    balances?: boolean
    transactions?: boolean
    /**
     * Optional list of account identifiers to pre-select during SCA. Omit to
     * let the user pick every account the bank offers — that's what we want
     * for a personal finance dashboard, so Florin never sets this.
     */
    accounts?: ReadonlyArray<unknown>
  }
  aspsp: {
    name: string
    country: string
  }
  state: string
  redirect_url: string
  psu_type: 'personal' | 'business'
  auth_method?: string
  language?: string
}

export interface StartAuthResponse {
  /** URL to redirect the user to — they authenticate at the bank's UI. */
  url: string
  /** Internal authorization tracking id, useful for support. */
  authorization_id: string
  psu_id_hash?: string
}

export interface SessionAccount {
  /** Stable account identifier — we store this on accounts.syncExternalId. */
  uid: string
  identification_hash?: string
  identification_hashes?: ReadonlyArray<string>
  account_servicer?: {
    bic_fi?: string
    financial_institution_id?: string
  }
  account_id?: {
    iban?: string
    other?: { identification: string; scheme_name?: string }
  }
  all_account_ids?: ReadonlyArray<unknown>
  account_type?: string
  cash_account_type?: string
  product?: string
  details?: string
  currency: string
  name?: string
  usage?: string
  legal_age?: boolean
  postal_address?: unknown
}

export interface Session {
  session_id: string
  status: 'AUTHORIZED' | 'EXPIRED' | 'REVOKED' | 'PENDING_AUTHORIZATION'
  /**
   * Enable Banking returns `accounts` as a list of account UIDs (strings),
   * NOT as full objects. To get the details (currency, IBAN, name, etc.) you
   * have to call GET /accounts/{uid}/details separately.
   */
  accounts: ReadonlyArray<string>
  aspsp: { name: string; country: string }
  psu_type: 'personal' | 'business'
  access: {
    valid_until: string
    balances?: boolean | null
    transactions?: boolean | null
    accounts?: ReadonlyArray<unknown> | null
  }
  created: string
  authorized?: string
  closed?: string
}

export interface CreateSessionResponse {
  session_id: string
  accounts: ReadonlyArray<string>
  aspsp: { name: string; country: string }
  psu_type: string
  access: { valid_until: string }
  authorized?: string
}

/** GET /accounts/{uid}/details response — full account metadata. */
export type AccountDetails = SessionAccount

export interface BalanceAmount {
  amount: string
  currency: string
}

export interface Balance {
  name?: string
  /** Possible values: CLBD (closing booked), XPCD (expected), ITAV (interim available)... */
  balance_type?: string
  balance_amount: BalanceAmount
  reference_date?: string
  last_change_date_time?: string
  last_committed_transaction?: string
}

export interface BalancesResponse {
  balances: ReadonlyArray<Balance>
}

export interface BankTransaction {
  entry_reference?: string
  /** Stable transaction id — we use this as transactions.externalId for dedupe. */
  transaction_id?: string
  /** Amount with sign — negative for debits, positive for credits. */
  transaction_amount: BalanceAmount
  /** Date the transaction was booked at the bank. */
  booking_date?: string
  /** Date the transaction has economic effect (we prefer this for occurredAt). */
  value_date?: string
  status?: 'BOOK' | 'PDNG' | 'INFO' | 'OTHR'
  credit_debit_indicator?: 'CRDT' | 'DBIT'
  reference_number?: string
  remittance_information?: ReadonlyArray<string>
  remittance_information_unstructured?: string
  creditor?: { name?: string }
  debtor?: { name?: string }
  creditor_account?: { iban?: string }
  debtor_account?: { iban?: string }
  bank_transaction_code?: { description?: string; code?: string; sub_code?: string }
  merchant_category_code?: string
  note?: string
  raw?: unknown
}

export interface TransactionsResponse {
  transactions: ReadonlyArray<BankTransaction>
  /** Cursor for pagination — if present, more pages exist. */
  continuation_key?: string
}

export interface ApplicationInfo {
  name: string
  description?: string
  kid: string
  active: boolean
  environment: 'sandbox' | 'production'
  countries?: ReadonlyArray<string>
}
