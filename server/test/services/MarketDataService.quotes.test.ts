import { describe, expect, it, vi } from "vitest"
import { ProviderError } from "../../src/providers/types.js"
import { makeService, NOW, providerQuote } from "../support/market.js"

describe("MarketDataService.getQuotes", () => {
  it("serves fresh cache without calling the provider", async () => {
    const { service, cache, providers } = makeService()
    await cache.putQuotes([{ symbol: "AAPL", payload: providerQuote("AAPL", "172.1"), provider: "finnhub", fetchedAt: NOW, expiresAt: new Date(NOW.getTime() + 60_000) }])
    const result = await service.getQuotes(["AAPL"])
    expect(result.quotes[0]).toMatchObject({ symbol: "AAPL", price: "172.1", stale: false, source: "finnhub", volume: null })
    expect(providers.quotes.getQuote).not.toHaveBeenCalled()
  })

  it("fetches misses, caches them for 3 minutes and keeps request order", async () => {
    const { service, cache } = makeService()
    const result = await service.getQuotes(["MSFT", "AAPL"])
    expect(result.quotes.map((q) => q.symbol)).toEqual(["MSFT", "AAPL"])
    expect(result.missing).toEqual([])
    expect(cache.quotes.get("AAPL")?.expiresAt.toISOString()).toBe("2026-11-20T15:03:00.000Z")
  })

  it("reports unknown symbols in missing", async () => {
    const { service } = makeService({ providers: { quotes: { getQuote: vi.fn(async () => null) } } })
    expect(await service.getQuotes(["ZZZZ"])).toEqual({ quotes: [], missing: ["ZZZZ"] })
  })

  it("falls back to stale cache when the provider fails", async () => {
    const { service, cache } = makeService({
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "upstream", undefined, 502) }) } },
    })
    await cache.putQuotes([{ symbol: "AAPL", payload: providerQuote("AAPL", "150"), provider: "finnhub", fetchedAt: new Date(0), expiresAt: new Date(1) }])
    const result = await service.getQuotes(["AAPL"])
    expect(result.quotes[0]).toMatchObject({ symbol: "AAPL", price: "150", stale: true })
  })

  it("treats an unexpected adapter exception (malformed body) like an outage and serves stale cache", async () => {
    const { service, cache } = makeService({
      providers: { quotes: { getQuote: vi.fn(async () => { throw new TypeError("Cannot read properties of null (reading 'c')") }) } },
    })
    await cache.putQuotes([{ symbol: "AAPL", payload: providerQuote("AAPL", "150"), provider: "finnhub", fetchedAt: new Date(0), expiresAt: new Date(1) }])
    const result = await service.getQuotes(["AAPL"])
    expect(result.quotes[0]).toMatchObject({ symbol: "AAPL", price: "150", stale: true })
  })

  it("fetches at most 25 symbols per request", async () => {
    const { service, providers } = makeService()
    const symbols = Array.from({ length: 30 }, (_, i) => `SYM${i}`)
    const result = await service.getQuotes(symbols)
    expect(providers.quotes.getQuote).toHaveBeenCalledTimes(25)
    expect(result.missing).toEqual(symbols.slice(25))
  })

  it("blocks the bucket on a provider 429 and throws 503 when nothing is cached", async () => {
    const { service, limiter } = makeService({
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "rate_limited", 30, 429) }) } },
    })
    await expect(service.getQuotes(["AAPL"])).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", statusCode: 503, retryAfterSec: 30 })
    expect(limiter.blocks).toEqual([{ key: "provider:finnhub", seconds: 30 }])
    // While blocked, Retry-After comes from the block itself, not the refill rate.
    await expect(service.getQuotes(["MSFT"])).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", retryAfterSec: 30 })
  })

  it("throws UPSTREAM_UNAVAILABLE (502) when every symbol failed and nothing is cached", async () => {
    const warn = vi.fn()
    const { service } = makeService({
      logger: { warn },
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "upstream", undefined, 502) }) } },
    })
    await expect(service.getQuotes(["AAPL"])).rejects.toMatchObject({ code: "UPSTREAM_UNAVAILABLE", statusCode: 502 })
    expect(warn).toHaveBeenCalledWith({ provider: "finnhub", kind: "upstream", status: 502 }, "market.provider_error")
  })

  it("dedupes requested symbols before fetching and caching", async () => {
    const { service, providers } = makeService()
    const result = await service.getQuotes(["AAPL", "AAPL", "MSFT"])
    expect(result.quotes.map((q) => q.symbol)).toEqual(["AAPL", "MSFT"])
    expect(providers.quotes.getQuote).toHaveBeenCalledTimes(2)
  })

  it("coalesces concurrent identical fetches", async () => {
    const getQuote = vi.fn(async (symbol: string) => {
      await new Promise((resolve) => setTimeout(resolve, 10))
      return providerQuote(symbol, "100")
    })
    const { service } = makeService({ providers: { quotes: { getQuote } } })
    await Promise.all([service.getQuotes(["AAPL"]), service.getQuotes(["AAPL"])])
    expect(getQuote).toHaveBeenCalledTimes(1)
  })
})
