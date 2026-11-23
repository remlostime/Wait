import { mapLimit } from "../lib/concurrency.js"
import { easternDate } from "../domain/tradingDate.js"
import { ProviderError, type DailyClose, type GroupedDailyProvider, type ProviderQuote, type QuoteProvider } from "../providers/types.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import { PROVIDER_BUCKETS, type RateLimiter } from "./RateLimiter.js"

export const FALLBACK_LIMIT = 25
const FALLBACK_CONCURRENCY = 5
const HOLIDAY_PROBE = "SPY"

export type CloseResolution =
  | { kind: "holiday" }
  | { kind: "closes"; closes: Map<string, string>; groupedCount: number; fallbackCount: number; missing: string[] }

export interface CloseResolver {
  resolve(tradingDate: string, symbols: string[], log?: LogSink): Promise<CloseResolution>
}

export type DailyCloseResolverDependencies = { grouped: GroupedDailyProvider; quotes: QuoteProvider; rateLimiter: RateLimiter }

const { massive: MASSIVE, finnhub: FINNHUB } = PROVIDER_BUCKETS

/** Overview §8.6 steps 4–6: one grouped call, a holiday check when it is empty, then ≤ 25 same-day Finnhub quotes (a different 25 each day when more are missing). */
export class DailyCloseResolver implements CloseResolver {
  private readonly deps: DailyCloseResolverDependencies

  constructor(deps: DailyCloseResolverDependencies) {
    this.deps = deps
  }

  async resolve(tradingDate: string, symbols: string[], log: LogSink = silentLog): Promise<CloseResolution> {
    const grouped = await this.fetchGrouped(tradingDate, log)
    if (grouped.size === 0) {
      if (await this.isHoliday(tradingDate)) return { kind: "holiday" }
    }

    const closes = new Map<string, string>()
    const needed: string[] = []
    for (const symbol of symbols) {
      const hit = grouped.get(symbol)
      if (hit === undefined) needed.push(symbol)
      else closes.set(symbol, hit.close)
    }

    // Over the limit, start at a date-derived offset so a symbol that missed today's 25 is likely covered tomorrow
    // (same date, same set: a rerun or the catch-up run must not change it).
    const start = needed.length > FALLBACK_LIMIT ? fnv1a(tradingDate) % needed.length : 0
    const ordered = [...needed.slice(start), ...needed.slice(0, start)]
    const fallback = ordered.slice(0, FALLBACK_LIMIT)
    const missing = ordered.slice(FALLBACK_LIMIT)
    const fallbackCloses = await mapLimit(fallback, FALLBACK_CONCURRENCY, (symbol) => this.closeOn(symbol, tradingDate))
    let fallbackCount = 0
    fallback.forEach((symbol, index) => {
      const close = fallbackCloses[index] ?? null
      if (close === null) {
        missing.push(symbol)
      } else {
        closes.set(symbol, close)
        fallbackCount += 1
      }
    })
    missing.sort()

    const groupedCount = symbols.length - needed.length
    log.info({ tradingDate, grouped: groupedCount, fallback: fallbackCount, missing: missing.length }, "alerts.closes")
    return { kind: "closes", closes, groupedCount, fallbackCount, missing }
  }

  private async fetchGrouped(tradingDate: string, log: LogSink): Promise<Map<string, DailyClose>> {
    try {
      if (!(await this.deps.rateLimiter.tryTake(MASSIVE.key, MASSIVE.policy))) {
        log.warn({ tradingDate }, "alerts.massive.bucket_exhausted")
        return new Map()
      }
      return await this.deps.grouped.getGroupedDaily(tradingDate)
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error
      if (error.kind === "rate_limited") await this.deps.rateLimiter.block(MASSIVE.key, error.retryAfterSec ?? 60)
      log.warn({ tradingDate, kind: error.kind, status: error.status }, "alerts.massive.failed")
      return new Map()
    }
  }

  /**
   * A holiday only when SPY's latest quote is dated strictly before `tradingDate`. A missing or undated quote (or a failed
   * call) proves nothing, so it throws and the run stays unfinished for the catch-up cron instead of being recorded as a holiday for good.
   */
  private async isHoliday(tradingDate: string): Promise<boolean> {
    const quote = await this.fetchQuote(HOLIDAY_PROBE, true)
    if (quote === null) throw new ProviderError("finnhub", "bad_response")
    const at = new Date(quote.asOf)
    if (Number.isNaN(at.getTime())) throw new ProviderError("finnhub", "bad_response")
    return easternDate(at) < tradingDate
  }

  /** The symbol's price if Finnhub's latest quote is from `tradingDate` (ET), else null. */
  private async closeOn(symbol: string, tradingDate: string): Promise<string | null> {
    const quote = await this.fetchQuote(symbol, false)
    if (quote === null) return null
    const at = new Date(quote.asOf)
    return !Number.isNaN(at.getTime()) && easternDate(at) === tradingDate ? quote.price : null
  }

  /** The Finnhub quote, or null on a miss. Provider failures return null unless `strict`, which rethrows them (and throws when the bucket is empty). */
  private async fetchQuote(symbol: string, strict: boolean): Promise<ProviderQuote | null> {
    try {
      if (!(await this.deps.rateLimiter.tryTake(FINNHUB.key, FINNHUB.policy))) {
        if (strict) throw new Error(`Finnhub bucket exhausted while checking ${symbol}`)
        return null
      }
      return await this.deps.quotes.getQuote(symbol)
    } catch (error) {
      if (error instanceof ProviderError && error.kind === "rate_limited") {
        await this.deps.rateLimiter.block(FINNHUB.key, error.retryAfterSec ?? 60)
      }
      if (strict) throw error
      return null
    }
  }
}

/** FNV-1a over the date string: a stable, well-spread offset without any state. */
function fnv1a(text: string): number {
  let hash = 0x811c9dc5
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash
}
