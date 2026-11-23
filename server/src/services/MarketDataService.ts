import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "../db/MarketCacheRepository.js"
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
  type SymbolMatch,
  type SymbolSearchProvider,
} from "../providers/types.js"
import { PROVIDER_BUCKETS, type BucketPolicy, type RateLimiter } from "./RateLimiter.js"
import { etDateString, isRegularSessionTime, lastSessionOpen } from "../domain/marketCalendar.js"
import type { CacheKind } from "../domain/ttl.js"
import type { Bar } from "../providers/types.js"

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

export const CHART_RANGES = ["1D", "1W", "1M", "1Y", "5Y"] as const
export type ChartRange = (typeof CHART_RANGES)[number]

/** Wire shape of GET /api/market/history (overview §8.4). */
export interface HistoryResult {
  symbol: string
  range: ChartRange
  points: Bar[]
  source: string
  asOf: string
  stale: boolean
  delayedMinutes: number | null
}

const SIP_DELAY_MS = 16 * 60_000
const FIVE_YEARS_MS = (5 * 365 + 7) * 86_400_000

export function isoWeekKey(iso: string): string {
  const source = new Date(iso)
  const d = new Date(Date.UTC(source.getUTCFullYear(), source.getUTCMonth(), source.getUTCDate()))
  const weekday = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - weekday)
  const yearStart = Date.UTC(d.getUTCFullYear(), 0, 1)
  const week = Math.ceil(((d.getTime() - yearStart) / 86_400_000 + 1) / 7)
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`
}

/** 1M = last 22 closes, 1Y = last 252, 5Y = last close of each ISO week. Input oldest first. */
export function deriveDailyRange(bars: Bar[], range: "1M" | "1Y" | "5Y"): Bar[] {
  if (range === "1M") return bars.slice(-22)
  if (range === "1Y") return bars.slice(-252)
  const byWeek = new Map<string, Bar>()
  for (const bar of bars) byWeek.set(isoWeekKey(bar.t), bar)
  return [...byWeek.values()]
}

/** Wire shape of GET /api/market/profile (overview §8.4). Ratios are Finnhub's percentages. */
export interface ProfileDTO {
  symbol: string
  name: string | null
  exchange: string | null
  industry: string | null
  logoUrl: string | null
  marketCap: string | null
  peRatio: number | null
  pbRatio: number | null
  dividendYield: number | null
  roe: number | null
  roa: number | null
  profitMargin: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  beta: number | null
  asOf: string
}

const PROFILE_REFRESH_MS = 7 * 86_400_000
/** How soon a profile with a transiently failed half (profile2 or metrics) is retried. */
const PARTIAL_PROFILE_RETRY_MS = 60_000

function toProfileDTO(symbol: string, entry: CacheEntry<ProfilePayload>): ProfileDTO {
  const p = entry.payload.profile
  const m = entry.payload.metrics
  return {
    symbol,
    name: p?.name ?? null,
    exchange: p?.exchange ?? null,
    industry: p?.industry ?? null,
    logoUrl: p?.logoUrl ?? null,
    marketCap: p?.marketCap ?? null,
    peRatio: m?.peRatio ?? null,
    pbRatio: m?.pbRatio ?? null,
    dividendYield: m?.dividendYield ?? null,
    roe: m?.roe ?? null,
    roa: m?.roa ?? null,
    profitMargin: m?.profitMargin ?? null,
    fiftyTwoWeekHigh: m?.fiftyTwoWeekHigh ?? null,
    fiftyTwoWeekLow: m?.fiftyTwoWeekLow ?? null,
    beta: m?.beta ?? null,
    asOf: entry.fetchedAt.toISOString(),
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
      if (!(error instanceof ProviderError)) {
        // A malformed-but-valid JSON body (or an adapter bug) must still reach the stale fallback, not a 500.
        this.deps.logger?.warn({ err: error instanceof Error ? error.message : String(error) }, "market.provider_unexpected_error")
        return { ok: false, reason: "unavailable" }
      }
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

  async getHistory(symbol: string, range: ChartRange): Promise<HistoryResult> {
    if (range === "1D" || range === "1W") {
      const { entry, stale } = await this.cachedSeries(symbol, range, range === "1D" ? "history1D" : "history1W", "alpaca", [PROVIDER_BUCKETS.alpaca], () =>
        this.loadIntraday(symbol, range),
      )
      return { symbol, range, points: entry.payload, source: entry.provider, asOf: entry.fetchedAt.toISOString(), stale, delayedMinutes: 15 }
    }
    const { entry, stale } = await this.cachedSeries(symbol, "daily5y", "daily5y", "tiingo", [PROVIDER_BUCKETS.tiingoHour, PROVIDER_BUCKETS.tiingoDay], () => {
      const now = this.deps.clock.now()
      return this.deps.providers.daily.getDailyBars(symbol, etDateString(new Date(now.getTime() - FIVE_YEARS_MS)), etDateString(now))
    })
    return {
      symbol,
      range,
      points: deriveDailyRange(entry.payload, range),
      source: entry.provider,
      asOf: entry.fetchedAt.toISOString(),
      stale,
      delayedMinutes: null,
    }
  }

  async search(query: string): Promise<SymbolMatch[]> {
    const key = query.trim().toLowerCase()
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getSearch(key)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return cached.payload
    const outcome = await this.coalesce(`search:${key}`, () =>
      this.callProvider([PROVIDER_BUCKETS.finnhub], () => this.deps.providers.search.search(key)),
    )
    if (outcome.ok) {
      await this.deps.cache.putSearch(key, { payload: outcome.value, provider: "finnhub", fetchedAt: now, expiresAt: expiresAt("search", now) })
      return outcome.value
    }
    if (cached) return cached.payload
    if (outcome.reason === "not_found") return []
    if (outcome.reason === "rate_limited") throw rateLimitedError(outcome.retryAfterSec)
    throw unavailableError()
  }

  getProfile(symbol: string): Promise<ProfileDTO> {
    return this.coalesce(`profile:${symbol}`, () => this.loadProfile(symbol))
  }

  private async loadProfile(symbol: string): Promise<ProfileDTO> {
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getProfile(symbol)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return toProfileDTO(symbol, cached)

    const cachedProfile = cached?.payload.profile ?? null
    const profileIsFresh = cachedProfile !== null && now.getTime() - Date.parse(cached?.payload.profileFetchedAt ?? "") < PROFILE_REFRESH_MS
    const finnhub = [PROVIDER_BUCKETS.finnhub]
    const metrics = await this.callProvider(finnhub, () => this.deps.providers.profile.getMetrics(symbol))
    const profile = profileIsFresh ? null : await this.callProvider(finnhub, () => this.deps.providers.profile.getProfile(symbol))

    const profileFailed = profile !== null && !profile.ok
    if (!metrics.ok && (profileIsFresh || profileFailed)) {
      if (cached) return toProfileDTO(symbol, cached)
      const reasons = [metrics, profile].flatMap((o) => (o && !o.ok ? [o] : []))
      const limited = reasons.find((o) => o.reason === "rate_limited")
      if (limited) throw rateLimitedError(limited.retryAfterSec)
      if (reasons.every((o) => o.reason === "not_found")) throw new AppError("NOT_FOUND", `No profile for ${symbol}`, 404)
      throw unavailableError()
    }

    const payload: ProfilePayload = {
      profile: profile?.ok ? profile.value : cachedProfile,
      metrics: metrics.ok ? metrics.value : (cached?.payload.metrics ?? null),
      profileFetchedAt: profile?.ok ? now.toISOString() : (cached?.payload.profileFetchedAt ?? now.toISOString()),
    }
    // A half that failed for a transient reason (rate limit, outage) must not be cached as fresh for a day:
    // expire soon so the next request retries it (profile2 is skipped again while it is still fresh).
    const transient = [metrics, profile].flatMap((o) => (o && !o.ok && o.reason !== "not_found" ? [o] : []))
    if (payload.profile === null && payload.metrics === null) {
      const limited = transient.find((o) => o.reason === "rate_limited")
      if (limited) throw rateLimitedError(limited.retryAfterSec)
      if (transient.length > 0) throw unavailableError()
      throw new AppError("NOT_FOUND", `No profile for ${symbol}`, 404)
    }
    const expiry = transient.length > 0 ? new Date(now.getTime() + PARTIAL_PROFILE_RETRY_MS) : expiresAt("metrics", now)
    const entry: CacheEntry<ProfilePayload> = { payload, provider: "finnhub", fetchedAt: now, expiresAt: expiry }
    await this.deps.cache.putProfile(symbol, entry)
    return toProfileDTO(symbol, entry)
  }

  /**
   * 1D = the latest session with delayed data; 1W = the last five sessions. The calendar has no holiday
   * table, so an empty window (Thanksgiving, an early close) steps back one session at a time, up to
   * 5 weekdays, before giving up. A valid symbol never gets 404 on a holiday.
   */
  private async loadIntraday(symbol: string, range: "1D" | "1W"): Promise<Bar[]> {
    const now = this.deps.clock.now()
    const timeframe = range === "1D" ? "5Min" : "30Min"
    let open = lastSessionOpen(new Date(now.getTime() - SIP_DELAY_MS))
    let end = now
    for (let attempt = 0; attempt < 5; attempt += 1) {
      let start = open
      if (range === "1W") {
        for (let i = 1; i < 5; i += 1) start = lastSessionOpen(new Date(start.getTime() - 1))
      }
      const bars = await this.deps.providers.intraday.getIntradayBars(symbol, timeframe, start, end)
      const regular = bars.filter((bar) => isRegularSessionTime(new Date(bar.t)))
      if (regular.length > 0) return regular
      end = open
      open = lastSessionOpen(new Date(open.getTime() - 1))
    }
    return []
  }

  private async cachedSeries(
    symbol: string,
    series: HistorySeries,
    kind: CacheKind,
    provider: string,
    buckets: Bucket[],
    load: () => Promise<Bar[]>,
  ): Promise<{ entry: CacheEntry<Bar[]>; stale: boolean }> {
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getHistory(symbol, series)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return { entry: cached, stale: false }
    const outcome = await this.coalesce(`history:${symbol}:${series}`, () => this.callProvider(buckets, load))
    if (outcome.ok && outcome.value.length > 0) {
      const entry: CacheEntry<Bar[]> = { payload: outcome.value, provider, fetchedAt: now, expiresAt: expiresAt(kind, now) }
      await this.deps.cache.putHistory(symbol, series, entry)
      return { entry, stale: false }
    }
    if (cached) return { entry: cached, stale: true }
    if (outcome.ok || outcome.reason === "not_found") throw new AppError("NOT_FOUND", `No price history for ${symbol}`, 404)
    if (outcome.reason === "rate_limited") throw rateLimitedError(outcome.retryAfterSec)
    throw unavailableError()
  }
}
