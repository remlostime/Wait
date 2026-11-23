import { describe, expect, it, vi } from "vitest"
import type { Bar } from "../../src/providers/types.js"
import { ProviderError } from "../../src/providers/types.js"
import { deriveDailyRange, isoWeekKey } from "../../src/services/MarketDataService.js"
import { makeService, NOW } from "../support/market.js"

const day = (isoDate: string, c: string): Bar => ({ t: `${isoDate}T00:00:00.000Z`, c })
const consecutiveDays = (count: number): Bar[] =>
  Array.from({ length: count }, (_, i) => ({ t: new Date(Date.UTC(2025, 0, 1 + i)).toISOString(), c: String(100 + i) }))

describe("getHistory 1D / 1W (Alpaca, 15 min delayed)", () => {
  it("1D asks for the current session, drops extended hours and caches for 5 minutes", async () => {
    const getIntradayBars = vi.fn(async (): Promise<Bar[]> => [
      { t: "2026-11-20T13:00:00.000Z", c: "170" }, // 08:00 EST pre-market
      { t: "2026-11-20T14:30:00.000Z", c: "171.2" },
      { t: "2026-11-20T14:35:00.000Z", c: "171.6" },
    ])
    const { service, cache } = makeService({ providers: { intraday: { getIntradayBars } } })
    const result = await service.getHistory("AAPL", "1D")
    expect(result).toEqual({
      symbol: "AAPL", range: "1D", source: "alpaca", stale: false, delayedMinutes: 15, asOf: NOW.toISOString(),
      points: [{ t: "2026-11-20T14:30:00.000Z", c: "171.2" }, { t: "2026-11-20T14:35:00.000Z", c: "171.6" }],
    })
    expect(getIntradayBars).toHaveBeenCalledWith("AAPL", "5Min", new Date("2026-11-20T14:30:00.000Z"), NOW)
    expect(cache.history.get("AAPL:1D")?.expiresAt.toISOString()).toBe("2026-11-20T15:05:00.000Z")
    await service.getHistory("AAPL", "1D")
    expect(getIntradayBars).toHaveBeenCalledTimes(1)
  })

  it("1W spans the last five sessions with 30-minute bars", async () => {
    const getIntradayBars = vi.fn(async (): Promise<Bar[]> => [{ t: "2026-11-16T14:30:00.000Z", c: "168" }])
    const { service } = makeService({ providers: { intraday: { getIntradayBars } } })
    await service.getHistory("AAPL", "1W")
    expect(getIntradayBars).toHaveBeenCalledWith("AAPL", "30Min", new Date("2026-11-16T14:30:00.000Z"), NOW)
  })

  it("steps back past a market holiday (Thanksgiving 2026-11-26) instead of returning 404", async () => {
    const thanksgiving = new Date("2026-11-26T15:00:00.000Z") // Thu 10:00 EST; the calendar has no holiday table
    const wednesdayBar: Bar = { t: "2026-11-25T14:30:00.000Z", c: "170.9" }
    const getIntradayBars = vi.fn(async (_symbol: string, _timeframe: string, start: Date): Promise<Bar[]> =>
      start.toISOString() === "2026-11-25T14:30:00.000Z" ? [wednesdayBar] : [],
    )
    const { service } = makeService({ now: thanksgiving, providers: { intraday: { getIntradayBars } } })
    const result = await service.getHistory("AAPL", "1D")
    expect(result.points).toEqual([wednesdayBar])
    expect(getIntradayBars).toHaveBeenNthCalledWith(1, "AAPL", "5Min", new Date("2026-11-26T14:30:00.000Z"), thanksgiving)
    expect(getIntradayBars).toHaveBeenNthCalledWith(2, "AAPL", "5Min", new Date("2026-11-25T14:30:00.000Z"), new Date("2026-11-26T14:30:00.000Z"))
  })
})

describe("getHistory 1M / 1Y / 5Y (Tiingo daily5y)", () => {
  it("derives every daily range from one cached five-year pull", async () => {
    const getDailyBars = vi.fn(async (): Promise<Bar[]> => consecutiveDays(300))
    const { service, limiter } = makeService({ providers: { daily: { getDailyBars } } })
    const oneMonth = await service.getHistory("AAPL", "1M")
    const oneYear = await service.getHistory("AAPL", "1Y")
    await service.getHistory("AAPL", "5Y")
    expect(getDailyBars).toHaveBeenCalledTimes(1)
    expect(getDailyBars).toHaveBeenCalledWith("AAPL", "2021-11-14", "2026-11-20")
    expect(limiter.takes.map((t) => t.key)).toEqual(["provider:tiingo:hour", "provider:tiingo:day"])
    expect(oneMonth.points).toHaveLength(22)
    expect(oneMonth.points[21]?.c).toBe("399")
    expect(oneYear.points).toHaveLength(252)
    expect(oneYear).toMatchObject({ source: "tiingo", delayedMinutes: null, stale: false })
  })

  it("5Y keeps the last close of each ISO week", () => {
    const bars = ["09", "10", "11", "12", "13", "16", "17", "18", "19", "20"].map((d, i) => day(`2026-11-${d}`, String(i + 1)))
    expect(deriveDailyRange(bars, "5Y")).toEqual([day("2026-11-13", "5"), day("2026-11-20", "10")])
    expect(isoWeekKey("2026-11-16T00:00:00.000Z")).toBe("2026-W47")
    expect(isoWeekKey("2026-11-20T00:00:00.000Z")).toBe("2026-W47")
  })

  it("serves stale cache when Tiingo fails", async () => {
    const { service, cache } = makeService({
      providers: { daily: { getDailyBars: vi.fn(async () => { throw new ProviderError("tiingo", "upstream", undefined, 500) }) } },
    })
    await cache.putHistory("AAPL", "daily5y", { payload: [day("2026-11-19", "171.2")], provider: "tiingo", fetchedAt: new Date(0), expiresAt: new Date(1) })
    expect(await service.getHistory("AAPL", "1M")).toMatchObject({ stale: true, points: [day("2026-11-19", "171.2")] })
  })

  it("throws NOT_FOUND for an unknown symbol and 503 when the bucket is empty", async () => {
    const empty = makeService()
    await expect(empty.service.getHistory("ZZZZ", "1Y")).rejects.toMatchObject({ code: "NOT_FOUND", statusCode: 404 })
    const limited = makeService()
    limited.limiter.denied.add("provider:tiingo:hour")
    await expect(limited.service.getHistory("AAPL", "1Y")).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", retryAfterSec: 72 })
  })
})
