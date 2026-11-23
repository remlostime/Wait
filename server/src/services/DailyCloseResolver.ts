import { mapLimit } from "../lib/concurrency.js"
import { easternDate } from "../domain/tradingDate.js"
import { ProviderError, type DailyClose, type GroupedDailyProvider, type QuoteProvider } from "../providers/types.js"
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

/** Overview §8.6 steps 4–6: one grouped call, a holiday check when it is empty, then ≤ 25 same-day Finnhub quotes. */
export class DailyCloseResolver implements CloseResolver {
  private readonly deps: DailyCloseResolverDependencies

  constructor(deps: DailyCloseResolverDependencies) {
    this.deps = deps
  }

  async resolve(tradingDate: string, symbols: string[], log: LogSink = silentLog): Promise<CloseResolution> {
    const grouped = await this.fetchGrouped(tradingDate, log)
    if (grouped.size === 0) {
      const probe = await this.closeOn(HOLIDAY_PROBE, tradingDate, true)
      if (probe === null) return { kind: "holiday" }
    }

    const closes = new Map<string, string>()
    const needed: string[] = []
    for (const symbol of symbols) {
      const hit = grouped.get(symbol)
      if (hit === undefined) needed.push(symbol)
      else closes.set(symbol, hit.close)
    }

    const fallback = needed.slice(0, FALLBACK_LIMIT)
    const missing = needed.slice(FALLBACK_LIMIT)
    const fallbackCloses = await mapLimit(fallback, FALLBACK_CONCURRENCY, (symbol) => this.closeOn(symbol, tradingDate, false))
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

  /** The symbol's price if Finnhub's latest quote is from `tradingDate` (ET), else null. Throws only when `strict`. */
  private async closeOn(symbol: string, tradingDate: string, strict: boolean): Promise<string | null> {
    try {
      if (!(await this.deps.rateLimiter.tryTake(FINNHUB.key, FINNHUB.policy))) {
        if (strict) throw new Error(`Finnhub bucket exhausted while checking ${symbol}`)
        return null
      }
      const quote = await this.deps.quotes.getQuote(symbol)
      if (quote === null) return null
      return easternDate(new Date(quote.asOf)) === tradingDate ? quote.price : null
    } catch (error) {
      if (error instanceof ProviderError && error.kind === "rate_limited") {
        await this.deps.rateLimiter.block(FINNHUB.key, error.retryAfterSec ?? 60)
      }
      if (strict) throw error
      return null
    }
  }
}
