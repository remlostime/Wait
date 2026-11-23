import { describe, expect, it } from "vitest"
import { fixedClock } from "../../src/lib/clock.js"
import { AlpacaProvider } from "../../src/providers/alpaca.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const clock = () => fixedClock(new Date("2026-11-20T15:00:00.000Z"))

describe("AlpacaProvider", () => {
  it("requests SIP split-adjusted bars ending at least 16 minutes ago", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json(fixture("alpaca-bars-aapl-5min.json")) }])
    const alpaca = new AlpacaProvider("id-1", "secret-1", clock(), fake.fetch)
    const bars = await alpaca.getIntradayBars("AAPL", "5Min", new Date("2026-11-20T14:30:00.000Z"), new Date("2026-11-20T15:00:00.000Z"))
    expect(bars).toEqual([
      { t: "2026-11-20T14:30:00.000Z", c: "171.2" },
      { t: "2026-11-20T14:35:00.000Z", c: "171.6" },
    ])
    const url = fake.calls[0]?.url
    expect(url?.origin + (url?.pathname ?? "")).toBe("https://data.alpaca.markets/v2/stocks/AAPL/bars")
    expect(Object.fromEntries(url?.searchParams ?? [])).toEqual({
      timeframe: "5Min",
      start: "2026-11-20T14:30:00.000Z",
      end: "2026-11-20T14:44:00.000Z",
      feed: "sip",
      adjustment: "split",
      limit: "10000",
      sort: "asc",
    })
    expect(headerOf(fake.calls[0]?.init, "apca-api-key-id")).toBe("id-1")
    expect(headerOf(fake.calls[0]?.init, "apca-api-secret-key")).toBe("secret-1")
  })

  it("follows next_page_token and tolerates bars: null", async () => {
    const fake = fakeFetch([
      {
        match: (url) => !url.searchParams.has("page_token"),
        respond: () => json({ bars: [{ t: "2026-11-19T14:30:00Z", c: 170 }], symbol: "AAPL", next_page_token: "p2" }),
      },
      { match: (url) => url.searchParams.get("page_token") === "p2", respond: () => json({ bars: null, symbol: "AAPL", next_page_token: null }) },
    ])
    const alpaca = new AlpacaProvider("id-1", "secret-1", clock(), fake.fetch)
    const bars = await alpaca.getIntradayBars("AAPL", "30Min", new Date("2026-11-13T14:30:00.000Z"), new Date("2026-11-20T14:00:00.000Z"))
    expect(bars).toEqual([{ t: "2026-11-19T14:30:00.000Z", c: "170" }])
    expect(fake.calls).toHaveLength(2)
  })
})
