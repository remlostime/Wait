export type ProviderName = "finnhub" | "tiingo" | "alpaca" | "massive"

/** Prices are decimal strings (overview D20); times are ISO 8601 UTC. */
export interface ProviderQuote {
  symbol: string
  price: string
  previousClose: string | null
  open: string | null
  high: string | null
  low: string | null
  change: string | null
  changePercent: number | null
  asOf: string
}

export interface SymbolMatch {
  symbol: string
  name: string
  exchange: string | null
  type: string
}

export interface ProviderProfile {
  symbol: string
  name: string | null
  exchange: string | null
  industry: string | null
  logoUrl: string | null
  /** USD (Finnhub reports millions; adapters convert). */
  marketCap: string | null
}

export interface ProviderMetrics {
  peRatio: number | null
  pbRatio: number | null
  dividendYield: number | null
  roe: number | null
  roa: number | null
  profitMargin: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  beta: number | null
}

/** One close per bar: `t` ISO bar start, `c` decimal close. */
export interface Bar {
  t: string
  c: string
}

export interface QuoteProvider {
  getQuote(symbol: string): Promise<ProviderQuote | null>
}

export interface SymbolSearchProvider {
  search(query: string): Promise<SymbolMatch[]>
}

export interface ProfileProvider {
  getProfile(symbol: string): Promise<ProviderProfile | null>
  getMetrics(symbol: string): Promise<ProviderMetrics | null>
}

export interface DailyBarsProvider {
  /** Inclusive ET dates YYYY-MM-DD, oldest first. */
  getDailyBars(symbol: string, from: string, to: string): Promise<Bar[]>
}

export type IntradayTimeframe = "5Min" | "30Min"

export interface IntradayBarsProvider {
  getIntradayBars(symbol: string, timeframe: IntradayTimeframe, start: Date, end: Date): Promise<Bar[]>
}

export type ProviderErrorKind = "rate_limited" | "not_found" | "upstream" | "bad_response" | "timeout"

export class ProviderError extends Error {
  constructor(
    readonly provider: ProviderName,
    readonly kind: ProviderErrorKind,
    readonly retryAfterSec?: number,
    readonly status?: number,
  ) {
    super(`${provider}:${kind}${status ? `:${status}` : ""}`)
    this.name = "ProviderError"
  }
}

/** One symbol's close for a trading day (decimal string). */
export type DailyClose = { symbol: string; close: string; at: Date }

export interface GroupedDailyProvider {
  /** All US stocks' closes for `date` ("YYYY-MM-DD") in one call. Empty map = no data for that day (yet). */
  getGroupedDaily(date: string): Promise<Map<string, DailyClose>>
}
