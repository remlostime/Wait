import type { DailyClose, GroupedDailyProvider, ProviderQuote, QuoteProvider } from "../../src/providers/types.js"
import type { BucketPolicy, RateLimiter } from "../../src/services/RateLimiter.js"

export class FakeRateLimiter implements RateLimiter {
  readonly taken: string[] = []
  readonly blocked: Array<{ key: string; seconds: number }> = []
  readonly denied = new Set<string>()

  async tryTake(key: string, _policy: BucketPolicy): Promise<boolean> {
    this.taken.push(key)
    return !this.denied.has(key)
  }

  async block(key: string, seconds: number): Promise<void> {
    this.blocked.push({ key, seconds })
  }
}

export class FakeQuoteProvider implements QuoteProvider {
  readonly calls: string[] = []
  private readonly answers = new Map<string, ProviderQuote | Error>()

  answer(symbol: string, price: string, asOf: string): this {
    this.answers.set(symbol, { symbol, price, previousClose: null, open: null, high: null, low: null, change: null, changePercent: null, asOf })
    return this
  }

  fail(symbol: string, error: Error): this {
    this.answers.set(symbol, error)
    return this
  }

  async getQuote(symbol: string): Promise<ProviderQuote | null> {
    this.calls.push(symbol)
    const answer = this.answers.get(symbol)
    if (answer instanceof Error) throw answer
    return answer ?? null
  }
}

export class FakeGroupedProvider implements GroupedDailyProvider {
  readonly calls: string[] = []
  private readonly result: Map<string, DailyClose> | Error

  constructor(result: Map<string, DailyClose> | Error = new Map()) {
    this.result = result
  }

  async getGroupedDaily(date: string): Promise<Map<string, DailyClose>> {
    this.calls.push(date)
    if (this.result instanceof Error) throw this.result
    return this.result
  }
}

export function groupedCloses(tradingDate: string, closes: Record<string, string>): Map<string, DailyClose> {
  return new Map(Object.entries(closes).map(([symbol, close]) => [symbol, { symbol, close, at: new Date(`${tradingDate}T21:00:00.000Z`) }]))
}

/** Collects `warn`/`info` calls so tests can assert what the job logged. */
export class RecordingLogger {
  readonly entries: Array<{ level: "info" | "warn"; message: string; details: object }> = []

  info(details: object, message: string): void {
    this.entries.push({ level: "info", message, details })
  }

  warn(details: object, message: string): void {
    this.entries.push({ level: "warn", message, details })
  }
}
