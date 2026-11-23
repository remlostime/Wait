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
    expect(quotes.calls[0]).toBe("SPY")
    expect([...quotes.calls.slice(1)].sort()).toEqual(["AAPL", "MSFT"])
  })

  it("fetches at most 25 fallback symbols", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" })))
    const others = Array.from({ length: 30 }, (_, index) => `S${String(index + 1).padStart(2, "0")}`)
    for (const symbol of others) quotes.answer(symbol, "10", "2026-11-20T21:00:00.000Z")

    const result = await resolver.resolve(TRADING_DAY, ["AAPL", ...others])

    expect(quotes.calls).toHaveLength(25)
    expect(result).toMatchObject({ kind: "closes", groupedCount: 1, fallbackCount: 25 })
    if (result.kind !== "closes") throw new Error("expected closes")
    expect(result.missing).toHaveLength(5)
    expect(result.missing).toEqual([...result.missing].sort())
    expect([...quotes.calls, ...result.missing].sort()).toEqual(others)
  })

  describe("when more than 25 symbols are missing from the grouped data", () => {
    const symbols = Array.from({ length: 30 }, (_, index) => `S${String(index + 1).padStart(2, "0")}`)

    async function fetchedOn(tradingDate: string): Promise<string[]> {
      const { quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(tradingDate, { AAPL: "172.1" })))
      for (const symbol of symbols) quotes.answer(symbol, "10", `${tradingDate}T21:00:00.000Z`)
      await resolver.resolve(tradingDate, ["AAPL", ...symbols])
      return [...quotes.calls].sort()
    }

    it("picks the same 25 for the same day (a rerun or the catch-up run must not change the set)", async () => {
      expect(await fetchedOn("2026-11-18")).toEqual(await fetchedOn("2026-11-18"))
    })

    it("rotates the starting point by trading date so different symbols are covered on different days", async () => {
      const days = ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-23", "2026-11-24", "2026-11-25"]
      const sets = await Promise.all(days.map(fetchedOn))
      expect(new Set(sets.map((set) => set.join(","))).size).toBeGreaterThan(1)
      expect(new Set(sets.flat()).size).toBe(30) // nobody is starved across the week
      expect(sets.some((set) => set.join(",") !== symbols.slice(0, 25).join(","))).toBe(true)
    })
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

  it("does not call it a holiday when the SPY quote is missing: the run must be retried", async () => {
    const { resolver } = setup(new FakeGroupedProvider())
    await expect(resolver.resolve(THANKSGIVING, ["AAPL"])).rejects.toMatchObject({ kind: "bad_response" })
  })

  it("does not call it a holiday when the SPY quote has no usable date", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.answer("SPY", "590.12", "not-a-date")
    await expect(resolver.resolve(THANKSGIVING, ["AAPL"])).rejects.toMatchObject({ kind: "bad_response" })
  })

  it("fails instead of guessing a holiday when the SPY check errors", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.fail("SPY", new ProviderError("finnhub", "upstream"))
    await expect(resolver.resolve(TRADING_DAY, ["AAPL"])).rejects.toMatchObject({ kind: "upstream" })
  })
})
