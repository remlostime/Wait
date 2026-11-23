import { describe, expect, it, vi } from "vitest"
import type { ProviderMetrics, ProviderProfile } from "../../src/providers/types.js"
import { ProviderError } from "../../src/providers/types.js"
import { DAY_MS, makeService, NOW } from "../support/market.js"

const APPLE = [{ symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" }]
const PROFILE: ProviderProfile = { symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", industry: "Technology", logoUrl: null, marketCap: "2650000500000" }
const METRICS: ProviderMetrics = {
  peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
  fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29,
}

describe("MarketDataService.search", () => {
  it("normalizes the query and caches results for 7 days", async () => {
    const search = vi.fn(async () => APPLE)
    const { service, cache } = makeService({ providers: { search: { search } } })
    expect(await service.search("  App ")).toEqual(APPLE)
    expect(search).toHaveBeenCalledWith("app")
    expect(cache.searches.get("app")?.expiresAt.toISOString()).toBe("2026-11-27T15:00:00.000Z")
    await service.search("APP")
    expect(search).toHaveBeenCalledTimes(1)
  })

  it("uses an expired cache entry when the provider fails, else throws 503 when limited", async () => {
    const failing = makeService({ providers: { search: { search: vi.fn(async () => { throw new ProviderError("finnhub", "timeout") }) } } })
    await failing.cache.putSearch("app", { payload: APPLE, provider: "finnhub", fetchedAt: new Date(0), expiresAt: new Date(1) })
    expect(await failing.service.search("app")).toEqual(APPLE)

    const limited = makeService()
    limited.limiter.denied.add("provider:finnhub")
    await expect(limited.service.search("app")).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", statusCode: 503 })
  })
})

describe("MarketDataService.getProfile", () => {
  it("merges profile2 and metrics into the wire DTO", async () => {
    const { service } = makeService({
      providers: { profile: { getProfile: vi.fn(async () => PROFILE), getMetrics: vi.fn(async () => METRICS) } },
    })
    expect(await service.getProfile("AAPL")).toEqual({
      symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", industry: "Technology", logoUrl: null, marketCap: "2650000500000",
      peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
      fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29, asOf: NOW.toISOString(),
    })
  })

  it("refreshes metrics daily but profile2 only weekly", async () => {
    const getProfile = vi.fn(async () => PROFILE)
    const getMetrics = vi.fn(async () => METRICS)
    const { service, clock } = makeService({ providers: { profile: { getProfile, getMetrics } } })
    await service.getProfile("AAPL")
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([1, 1])
    clock.advance(DAY_MS + 60_000)
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([1, 2])
    clock.advance(7 * DAY_MS)
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([2, 3])
  })

  it("throws NOT_FOUND when Finnhub knows nothing about the symbol", async () => {
    const { service } = makeService()
    await expect(service.getProfile("ZZZZ")).rejects.toMatchObject({ code: "NOT_FOUND", statusCode: 404 })
  })
})
