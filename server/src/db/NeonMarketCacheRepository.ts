import type { Bar, ProviderQuote, SymbolMatch } from "../providers/types.js"
import { asDate } from "../lib/time.js"
import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "./MarketCacheRepository.js"
import type { Row, Sql } from "./sql.js"

function mapEntry<T>(row: Row, provider = String(row.provider ?? "finnhub")): CacheEntry<T> {
  return { payload: row.payload as T, provider, fetchedAt: asDate(row.fetched_at), expiresAt: asDate(row.expires_at) }
}

export class NeonMarketCacheRepository implements MarketCacheRepository {
  constructor(private readonly sql: Sql) {}

  async getQuotes(symbols: string[]): Promise<Map<string, CacheEntry<ProviderQuote>>> {
    const result = new Map<string, CacheEntry<ProviderQuote>>()
    if (symbols.length === 0) return result
    const rows = await this.sql`
      SELECT symbol, payload, provider, fetched_at, expires_at FROM quote_cache
      WHERE symbol IN (SELECT jsonb_array_elements_text(${JSON.stringify(symbols)}::jsonb))`
    for (const row of rows) result.set(String(row.symbol), mapEntry<ProviderQuote>(row))
    return result
  }

  async putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>): Promise<void> {
    if (entries.length === 0) return
    const records = entries.map((e) => ({
      symbol: e.symbol,
      payload: e.payload,
      provider: e.provider,
      fetched_at: e.fetchedAt.toISOString(),
      expires_at: e.expiresAt.toISOString(),
    }))
    await this.sql`
      INSERT INTO quote_cache (symbol, payload, provider, fetched_at, expires_at)
      SELECT x.symbol, x.payload, x.provider, x.fetched_at, x.expires_at
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb)
        AS x(symbol text, payload jsonb, provider text, fetched_at timestamptz, expires_at timestamptz)
      ON CONFLICT (symbol) DO UPDATE SET
        payload = EXCLUDED.payload, provider = EXCLUDED.provider,
        fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getHistory(symbol: string, series: HistorySeries): Promise<CacheEntry<Bar[]> | null> {
    const rows = await this.sql`
      SELECT payload, provider, fetched_at, expires_at FROM history_cache WHERE symbol = ${symbol} AND series = ${series}`
    return rows[0] ? mapEntry<Bar[]>(rows[0]) : null
  }

  async putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>): Promise<void> {
    await this.sql`
      INSERT INTO history_cache (symbol, series, payload, provider, fetched_at, expires_at)
      VALUES (${symbol}, ${series}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.provider}, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (symbol, series) DO UPDATE SET
        payload = EXCLUDED.payload, provider = EXCLUDED.provider,
        fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getProfile(symbol: string): Promise<CacheEntry<ProfilePayload> | null> {
    const rows = await this.sql`SELECT payload, fetched_at, expires_at FROM profile_cache WHERE symbol = ${symbol}`
    return rows[0] ? mapEntry<ProfilePayload>(rows[0], "finnhub") : null
  }

  async putProfile(symbol: string, entry: CacheEntry<ProfilePayload>): Promise<void> {
    await this.sql`
      INSERT INTO profile_cache (symbol, payload, fetched_at, expires_at)
      VALUES (${symbol}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (symbol) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getSearch(query: string): Promise<CacheEntry<SymbolMatch[]> | null> {
    const rows = await this.sql`SELECT payload, fetched_at, expires_at FROM search_cache WHERE query = ${query}`
    return rows[0] ? mapEntry<SymbolMatch[]>(rows[0], "finnhub") : null
  }

  async putSearch(query: string, entry: CacheEntry<SymbolMatch[]>): Promise<void> {
    await this.sql`
      INSERT INTO search_cache (query, payload, fetched_at, expires_at)
      VALUES (${query}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (query) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }
}
