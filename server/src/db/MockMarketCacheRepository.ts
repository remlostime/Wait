import type { Bar, ProviderQuote, SymbolMatch } from "../providers/types.js"
import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "./MarketCacheRepository.js"

const clone = <T>(entry: CacheEntry<T>): CacheEntry<T> => ({
  payload: structuredClone(entry.payload),
  provider: entry.provider,
  fetchedAt: new Date(entry.fetchedAt.getTime()),
  expiresAt: new Date(entry.expiresAt.getTime()),
})

export class MockMarketCacheRepository implements MarketCacheRepository {
  readonly quotes = new Map<string, CacheEntry<ProviderQuote>>()
  readonly history = new Map<string, CacheEntry<Bar[]>>()
  readonly profiles = new Map<string, CacheEntry<ProfilePayload>>()
  readonly searches = new Map<string, CacheEntry<SymbolMatch[]>>()

  clear(): void {
    this.quotes.clear()
    this.history.clear()
    this.profiles.clear()
    this.searches.clear()
  }

  /** Overview §8.1: every Mock* repository has clear() and seed(). */
  seed(data: {
    quotes?: Array<CacheEntry<ProviderQuote> & { symbol: string }>
    history?: Array<{ symbol: string; series: HistorySeries; entry: CacheEntry<Bar[]> }>
    profiles?: Array<{ symbol: string; entry: CacheEntry<ProfilePayload> }>
    searches?: Array<{ query: string; entry: CacheEntry<SymbolMatch[]> }>
  }): void {
    for (const { symbol, ...entry } of data.quotes ?? []) this.quotes.set(symbol, clone(entry))
    for (const { symbol, series, entry } of data.history ?? []) this.history.set(`${symbol}:${series}`, clone(entry))
    for (const { symbol, entry } of data.profiles ?? []) this.profiles.set(symbol, clone(entry))
    for (const { query, entry } of data.searches ?? []) this.searches.set(query, clone(entry))
  }

  async getQuotes(symbols: string[]) {
    const result = new Map<string, CacheEntry<ProviderQuote>>()
    for (const symbol of symbols) {
      const entry = this.quotes.get(symbol)
      if (entry) result.set(symbol, clone(entry))
    }
    return result
  }

  async putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>) {
    for (const { symbol, ...entry } of entries) this.quotes.set(symbol, clone(entry))
  }

  async getHistory(symbol: string, series: HistorySeries) {
    const entry = this.history.get(`${symbol}:${series}`)
    return entry ? clone(entry) : null
  }

  async putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>) {
    this.history.set(`${symbol}:${series}`, clone(entry))
  }

  async getProfile(symbol: string) {
    const entry = this.profiles.get(symbol)
    return entry ? clone(entry) : null
  }

  async putProfile(symbol: string, entry: CacheEntry<ProfilePayload>) {
    this.profiles.set(symbol, clone({ ...entry, provider: "finnhub" }))
  }

  async getSearch(query: string) {
    const entry = this.searches.get(query)
    return entry ? clone(entry) : null
  }

  async putSearch(query: string, entry: CacheEntry<SymbolMatch[]>) {
    this.searches.set(query, clone({ ...entry, provider: "finnhub" }))
  }
}
