import type { CacheEntry, MarketCacheRepository } from "../db/MarketCacheRepository.js"
import { expiresAt } from "../domain/ttl.js"
import type { Clock } from "../lib/clock.js"
import { mapLimit } from "../lib/concurrency.js"
import { AppError } from "../lib/errors.js"
import {
  ProviderError,
  type DailyBarsProvider,
  type IntradayBarsProvider,
  type ProfileProvider,
  type ProviderQuote,
  type QuoteProvider,
  type SymbolSearchProvider,
} from "../providers/types.js"
import { PROVIDER_BUCKETS, type BucketPolicy, type RateLimiter } from "./RateLimiter.js"

export interface MarketProviders {
  quotes: QuoteProvider
  search: SymbolSearchProvider
  profile: ProfileProvider
  daily: DailyBarsProvider
  intraday: IntradayBarsProvider
}

export interface MarketLogger {
  warn(details: object, message: string): void
}

export interface MarketDataServiceDeps {
  cache: MarketCacheRepository
  limiter: RateLimiter
  providers: MarketProviders
  clock: Clock
  logger?: MarketLogger
}

/** Wire shape of GET /api/market/quotes items (overview §8.4). */
export interface QuoteDTO {
  symbol: string
  price: string
  previousClose: string | null
  open: string | null
  high: string | null
  low: string | null
  change: string | null
  changePercent: number | null
  volume: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  asOf: string
  source: string
  stale: boolean
}

export interface QuotesResult {
  quotes: QuoteDTO[]
  missing: string[]
}

type Bucket = { key: string; policy: BucketPolicy }
type ProviderOutcome<T> =
  | { ok: true; value: T }
  | { ok: false; reason: "rate_limited" | "not_found" | "unavailable"; retryAfterSec?: number }

const MAX_FETCH_PER_REQUEST = 25
const FETCH_CONCURRENCY = 5

export const rateLimitedError = (retryAfterSec = 60) =>
  new AppError("UPSTREAM_RATE_LIMITED", "Market data is temporarily rate limited, try again shortly", 503, retryAfterSec)
export const unavailableError = () => new AppError("UPSTREAM_UNAVAILABLE", "The market data provider is unavailable", 502)

function toQuoteDTO(entry: CacheEntry<ProviderQuote>, stale: boolean): QuoteDTO {
  const q = entry.payload
  return {
    symbol: q.symbol,
    price: q.price,
    previousClose: q.previousClose,
    open: q.open,
    high: q.high,
    low: q.low,
    change: q.change,
    changePercent: q.changePercent,
    volume: null,
    fiftyTwoWeekHigh: null,
    fiftyTwoWeekLow: null,
    asOf: q.asOf,
    source: entry.provider,
    stale,
  }
}

export class MarketDataService {
  private readonly inflight = new Map<string, Promise<unknown>>()

  constructor(private readonly deps: MarketDataServiceDeps) {}

  /** Shares one in-flight promise per key within this instance (Vercel reuses warm instances). */
  private coalesce<T>(key: string, work: () => Promise<T>): Promise<T> {
    const existing = this.inflight.get(key) as Promise<T> | undefined
    if (existing) return existing
    const promise = work().finally(() => this.inflight.delete(key))
    this.inflight.set(key, promise)
    return promise
  }

  /** Takes a token from every bucket, calls the provider, and blocks the buckets on a provider 429. */
  private async callProvider<T>(buckets: Bucket[], call: () => Promise<T>): Promise<ProviderOutcome<T>> {
    for (const bucket of buckets) {
      if (!(await this.deps.limiter.tryTake(bucket.key, bucket.policy))) {
        const blockedFor = (await this.deps.limiter.retryAfterSec?.(bucket.key)) ?? null
        return { ok: false, reason: "rate_limited", retryAfterSec: blockedFor ?? Math.ceil(1 / bucket.policy.refillPerSec) }
      }
    }
    try {
      return { ok: true, value: await call() }
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error
      if (error.kind === "rate_limited") {
        const seconds = error.retryAfterSec ?? 60
        for (const bucket of buckets) await this.deps.limiter.block(bucket.key, seconds)
        return { ok: false, reason: "rate_limited", retryAfterSec: seconds }
      }
      if (error.kind === "not_found") return { ok: false, reason: "not_found" }
      this.deps.logger?.warn({ provider: error.provider, kind: error.kind, status: error.status }, "market.provider_error")
      return { ok: false, reason: "unavailable" }
    }
  }

  async getQuotes(requested: string[]): Promise<QuotesResult> {
    // Dedupe first: one INSERT … ON CONFLICT can't touch the same row twice.
    const symbols = [...new Set(requested)]
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getQuotes(symbols)
    const fresh = new Map<string, QuoteDTO>()
    const stale = new Map<string, CacheEntry<ProviderQuote>>()
    for (const symbol of symbols) {
      const entry = cached.get(symbol)
      if (entry && entry.expiresAt.getTime() > now.getTime()) fresh.set(symbol, toQuoteDTO(entry, false))
      else if (entry) stale.set(symbol, entry)
    }

    const toFetch = symbols.filter((symbol) => !fresh.has(symbol)).slice(0, MAX_FETCH_PER_REQUEST)
    const fetched: Array<CacheEntry<ProviderQuote> & { symbol: string }> = []
    let rateLimitedFor: number | undefined
    let providerUnavailable = false
    await mapLimit(toFetch, FETCH_CONCURRENCY, async (symbol) => {
      if (rateLimitedFor !== undefined) return
      const outcome = await this.coalesce(`quote:${symbol}`, () =>
        this.callProvider([PROVIDER_BUCKETS.finnhub], () => this.deps.providers.quotes.getQuote(symbol)),
      )
      if (outcome.ok && outcome.value) {
        fetched.push({ symbol, payload: outcome.value, provider: "finnhub", fetchedAt: now, expiresAt: expiresAt("quote", now) })
      } else if (!outcome.ok && outcome.reason === "rate_limited") {
        rateLimitedFor = outcome.retryAfterSec
      } else if (!outcome.ok && outcome.reason === "unavailable") {
        providerUnavailable = true
      }
    })
    await this.deps.cache.putQuotes(fetched)
    for (const entry of fetched) fresh.set(entry.symbol, toQuoteDTO(entry, false))

    const quotes: QuoteDTO[] = []
    const missing: string[] = []
    for (const symbol of symbols) {
      const quote = fresh.get(symbol)
      const staleEntry = stale.get(symbol)
      if (quote) quotes.push(quote)
      else if (staleEntry) quotes.push(toQuoteDTO(staleEntry, true))
      else missing.push(symbol)
    }
    if (quotes.length === 0 && rateLimitedFor !== undefined) throw rateLimitedError(rateLimitedFor)
    if (quotes.length === 0 && providerUnavailable) throw unavailableError()
    return { quotes, missing }
  }
}
