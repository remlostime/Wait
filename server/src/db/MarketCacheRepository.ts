import type { Bar, ProviderMetrics, ProviderProfile, ProviderQuote, SymbolMatch } from "../providers/types.js"

export type HistorySeries = "1D" | "1W" | "daily5y"

export interface CacheEntry<T> {
  payload: T
  provider: string
  fetchedAt: Date
  expiresAt: Date
}

/** profile2 is refreshed every 7 days, metrics every day; both live in one row. */
export interface ProfilePayload {
  profile: ProviderProfile | null
  metrics: ProviderMetrics | null
  profileFetchedAt: string
}

export interface MarketCacheRepository {
  getQuotes(symbols: string[]): Promise<Map<string, CacheEntry<ProviderQuote>>>
  putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>): Promise<void>
  getHistory(symbol: string, series: HistorySeries): Promise<CacheEntry<Bar[]> | null>
  putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>): Promise<void>
  getProfile(symbol: string): Promise<CacheEntry<ProfilePayload> | null>
  putProfile(symbol: string, entry: CacheEntry<ProfilePayload>): Promise<void>
  getSearch(query: string): Promise<CacheEntry<SymbolMatch[]> | null>
  putSearch(query: string, entry: CacheEntry<SymbolMatch[]>): Promise<void>
}
