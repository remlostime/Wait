import { describe, expect, it } from "vitest"
import { FinnhubProvider } from "../../src/providers/finnhub.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const KEY = "finnhub-test-key"

function provider(routes: Record<string, unknown>) {
  const fake = fakeFetch(
    Object.entries(routes).map(([path, body]) => ({ match: (url: URL) => url.pathname === path, respond: () => json(body) })),
  )
  return { finnhub: new FinnhubProvider(KEY, fake.fetch), calls: fake.calls }
}

describe("FinnhubProvider", () => {
  it("maps /quote and sends the key as X-Finnhub-Token", async () => {
    const { finnhub, calls } = provider({ "/api/v1/quote": fixture("finnhub-quote-aapl.json") })
    expect(await finnhub.getQuote("AAPL")).toEqual({
      symbol: "AAPL", price: "172.1", previousClose: "170", open: "171", high: "173", low: "170.5",
      change: "2.1", changePercent: 1.2353, asOf: "2026-11-20T15:00:00.000Z",
    })
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/quote?symbol=AAPL")
    expect(headerOf(calls[0]?.init, "x-finnhub-token")).toBe(KEY)
    expect(calls[0]?.url.toString()).not.toContain(KEY)
  })

  it("returns null for an unknown symbol (all-zero quote)", async () => {
    const { finnhub } = provider({ "/api/v1/quote": fixture("finnhub-quote-unknown.json") })
    expect(await finnhub.getQuote("ZZZZ")).toBeNull()
  })

  it("searches US listings and keeps common stock, ETP and ADR with plain tickers", async () => {
    const { finnhub, calls } = provider({ "/api/v1/search": fixture("finnhub-search-app.json") })
    expect(await finnhub.search("app")).toEqual([
      { symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" },
      { symbol: "AMAT", name: "APPLIED MATERIALS INC", exchange: null, type: "Common Stock" },
      { symbol: "SPY", name: "SPDR S&P 500 ETF TRUST", exchange: null, type: "ETP" },
    ])
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/search?q=app&exchange=US")
  })

  it("maps profile2 (market cap from millions) and returns null for {}", async () => {
    const { finnhub } = provider({ "/api/v1/stock/profile2": fixture("finnhub-profile2-aapl.json") })
    expect(await finnhub.getProfile("AAPL")).toEqual({
      symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ NMS - GLOBAL MARKET", industry: "Technology",
      logoUrl: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/AAPL.png", marketCap: "2650000500000",
    })
    const empty = provider({ "/api/v1/stock/profile2": {} })
    expect(await empty.finnhub.getProfile("ZZZZ")).toBeNull()
  })

  it("maps metric=all and returns null when every metric is missing", async () => {
    const { finnhub, calls } = provider({ "/api/v1/stock/metric": fixture("finnhub-metric-aapl.json") })
    expect(await finnhub.getMetrics("AAPL")).toEqual({
      peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
      fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29,
    })
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/stock/metric?symbol=AAPL&metric=all")
    const empty = provider({ "/api/v1/stock/metric": { metric: {}, metricType: "all", symbol: "ZZZZ" } })
    expect(await empty.finnhub.getMetrics("ZZZZ")).toBeNull()
  })
})
