import { describe, expect, it } from "vitest"
import { ProviderError } from "../../src/providers/types.js"
import { DailyCloseResolver } from "../../src/services/DailyCloseResolver.js"
import { FakeGroupedProvider, FakeQuoteProvider, FakeRateLimiter, groupedCloses, RecordingLogger } from "../support/alertFakes.js"

const TRADING_DAY = "2026-11-20"
const THANKSGIVING = "2026-11-26"

function setup(grouped: FakeGroupedProvider) {
  const rateLimiter = new FakeRateLimiter()
  const quotes = new FakeQuoteProvider()
  const resolver = new DailyCloseResolver({ grouped, quotes, rateLimiter })
  return { rateLimiter, quotes, resolver }
}

describe("DailyCloseResolver", () => {
  it("uses grouped closes and never calls Finnhub when every symbol is present", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1", NVDA: "185" })))
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "NVDA"])).toEqual({
      kind: "closes",
      closes: new Map([["AAPL", "172.1"], ["NVDA", "185"]]),
      groupedCount: 2,
      fallbackCount: 0,
      missing: [],
    })
    expect(quotes.calls).toEqual([])
    expect(rateLimiter.taken).toEqual(["provider:massive"])
  })

  it("reports a holiday when Massive is empty and SPY last traded on an earlier day", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.answer("SPY", "590.12", "2026-11-25T21:00:00.000Z")
    expect(await resolver.resolve(THANKSGIVING, ["AAPL"])).toEqual({ kind: "holiday" })
    expect(quotes.calls).toEqual(["SPY"])
  })

  it("falls back to same-day Finnhub quotes when grouped data is not published yet", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes
      .answer("SPY", "590.12", "2026-11-20T21:00:00.000Z")
      .answer("AAPL", "172.1", "2026-11-20T21:00:00.000Z")
      .answer("MSFT", "415", "2026-11-19T21:00:00.000Z")
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "MSFT"])).toEqual({
      kind: "closes",
      closes: new Map([["AAPL", "172.1"]]),
      groupedCount: 0,
      fallbackCount: 1,
      missing: ["MSFT"],
    })
    expect(quotes.calls).toEqual(["SPY", "AAPL", "MSFT"])
  })

  it("fetches at most 25 fallback symbols", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" })))
    const others = Array.from({ length: 30 }, (_, index) => `S${String(index + 1).padStart(2, "0")}`)
    for (const symbol of others) quotes.answer(symbol, "10", "2026-11-20T21:00:00.000Z")

    const result = await resolver.resolve(TRADING_DAY, ["AAPL", ...others])

    expect(quotes.calls).toHaveLength(25)
    expect(result).toMatchObject({ kind: "closes", groupedCount: 1, fallbackCount: 25, missing: ["S26", "S27", "S28", "S29", "S30"] })
  })

  it("treats an exhausted Massive bucket as missing grouped data", async () => {
    const grouped = new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" }))
    const { rateLimiter, quotes, resolver } = setup(grouped)
    rateLimiter.denied.add("provider:massive")
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z").answer("AAPL", "172.3", "2026-11-20T20:59:00.000Z")

    expect(await resolver.resolve(TRADING_DAY, ["AAPL"])).toMatchObject({ kind: "closes", closes: new Map([["AAPL", "172.3"]]), fallbackCount: 1 })
    expect(grouped.calls).toEqual([])
  })

  it("blocks the Massive bucket after a 429 and falls back", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(new ProviderError("massive", "rate_limited", 120)))
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z").answer("AAPL", "172.1", "2026-11-20T21:00:00.000Z")

    await resolver.resolve(TRADING_DAY, ["AAPL"])

    expect(rateLimiter.blocked).toEqual([{ key: "provider:massive", seconds: 120 }])
  })

  it("marks symbols missing when the Finnhub bucket is exhausted", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" })))
    rateLimiter.denied.add("provider:finnhub")
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "MSFT"])).toMatchObject({ kind: "closes", missing: ["MSFT"], fallbackCount: 0 })
    expect(quotes.calls).toEqual([])
  })

  it("logs Massive failures through the logger passed to resolve()", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider(new ProviderError("massive", "upstream", undefined, 502)))
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z")
    const log = new RecordingLogger()
    await resolver.resolve(TRADING_DAY, [], log)
    expect(log.entries).toContainEqual({ level: "warn", message: "alerts.massive.failed", details: { tradingDate: TRADING_DAY, kind: "upstream", status: 502 } })
  })

  it("fails instead of guessing a holiday when the SPY check errors", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.fail("SPY", new ProviderError("finnhub", "upstream"))
    await expect(resolver.resolve(TRADING_DAY, ["AAPL"])).rejects.toMatchObject({ kind: "upstream" })
  })
})
