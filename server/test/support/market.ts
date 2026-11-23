import { vi } from "vitest"
import { MockMarketCacheRepository } from "../../src/db/MockMarketCacheRepository.js"
import { fixedClock } from "../../src/lib/clock.js"
import type { Bar, ProviderMetrics, ProviderProfile, ProviderQuote, SymbolMatch } from "../../src/providers/types.js"
import { MarketDataService, type MarketLogger, type MarketProviders } from "../../src/services/MarketDataService.js"
import { MockRateLimiter } from "../../src/services/RateLimiter.js"

/** Friday 2026-11-20 10:00 EST: market open. */
export const NOW = new Date("2026-11-20T15:00:00.000Z")
export const DAY_MS = 86_400_000

export function providerQuote(symbol: string, price: string): ProviderQuote {
  return { symbol, price, previousClose: "100", open: "100", high: "101", low: "99", change: "1", changePercent: 1, asOf: "2026-11-20T14:59:00.000Z" }
}

export function makeProviders(overrides: Partial<MarketProviders> = {}): MarketProviders {
  return {
    quotes: { getQuote: vi.fn(async (symbol: string): Promise<ProviderQuote | null> => providerQuote(symbol, "100")) },
    search: { search: vi.fn(async (_query: string): Promise<SymbolMatch[]> => []) },
    profile: {
      getProfile: vi.fn(async (_symbol: string): Promise<ProviderProfile | null> => null),
      getMetrics: vi.fn(async (_symbol: string): Promise<ProviderMetrics | null> => null),
    },
    daily: { getDailyBars: vi.fn(async (_symbol: string, _from: string, _to: string): Promise<Bar[]> => []) },
    intraday: { getIntradayBars: vi.fn(async (): Promise<Bar[]> => []) },
    ...overrides,
  }
}

export function makeService(options: { providers?: Partial<MarketProviders>; now?: Date; logger?: MarketLogger } = {}) {
  const cache = new MockMarketCacheRepository()
  const limiter = new MockRateLimiter()
  const clock = fixedClock(options.now ?? NOW)
  const providers = makeProviders(options.providers)
  const service = new MarketDataService({ cache, limiter, providers, clock, logger: options.logger })
  return { service, cache, limiter, clock, providers }
}
