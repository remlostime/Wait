import { afterEach, describe, expect, it, vi } from "vitest"
import type { Bar } from "../../src/providers/types.js"
import { buildTestApp } from "../support/app.js"
import { makeService } from "../support/market.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup(market = makeService()) {
  const built = await buildTestApp({ rateLimiter: market.limiter, marketData: market.service })
  app = built.app
  const headers = built.authHeaders()
  const get = (url: string) => built.app.inject({ method: "GET", url, headers })
  return { get, market }
}

describe("GET /api/market/quotes", () => {
  it("requires auth", async () => {
    await setup()
    const response = await app!.inject({ method: "GET", url: "/api/market/quotes?symbols=AAPL" })
    expect(response.statusCode).toBe(401)
  })

  it("authenticates before validating, so a bad query without a token is 401, not 400", async () => {
    await setup()
    const response = await app!.inject({ method: "GET", url: "/api/market/history?symbol=lower&range=2Y" })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("uppercases, trims and dedupes symbols and returns the wire shape", async () => {
    const { get } = await setup()
    const response = await get("/api/market/quotes?symbols=aapl,%20MSFT,AAPL")
    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(body.quotes.map((q: { symbol: string }) => q.symbol)).toEqual(["AAPL", "MSFT"])
    expect(Object.keys(body.quotes[0]).sort()).toEqual(
      ["asOf", "change", "changePercent", "fiftyTwoWeekHigh", "fiftyTwoWeekLow", "high", "low", "open", "previousClose", "price", "source", "stale", "symbol", "volume"],
    )
    expect(body.missing).toEqual([])
  })

  it("rejects invalid tickers and more than 50 symbols", async () => {
    const { get } = await setup()
    expect((await get("/api/market/quotes?symbols=AAPL,%24%24%24")).json().error.code).toBe("INVALID_INPUT")
    const tooMany = Array.from({ length: 51 }, (_, i) => `A${String.fromCharCode(65 + (i % 26))}${String.fromCharCode(65 + Math.floor(i / 26))}`).join(",")
    const response = await get(`/api/market/quotes?symbols=${tooMany}`)
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("INVALID_INPUT")
  })

  it("returns 503 with Retry-After when rate limited and nothing is cached", async () => {
    const market = makeService()
    market.limiter.denied.add("provider:finnhub")
    const { get } = await setup(market)
    const response = await get("/api/market/quotes?symbols=AAPL")
    expect(response.statusCode).toBe(503)
    expect(response.headers["retry-after"]).toBe("1")
    expect(response.json().error.code).toBe("UPSTREAM_RATE_LIMITED")
  })
})

describe("GET /api/market/history, /search, /profile", () => {
  it("serves history and validates the range", async () => {
    const bars: Bar[] = [{ t: "2026-11-19T00:00:00.000Z", c: "171.2" }, { t: "2026-11-20T00:00:00.000Z", c: "172.1" }]
    const { get } = await setup(makeService({ providers: { daily: { getDailyBars: vi.fn(async () => bars) } } }))
    const response = await get("/api/market/history?symbol=AAPL&range=1Y")
    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({ symbol: "AAPL", range: "1Y", points: bars, source: "tiingo", stale: false, delayedMinutes: null })
    expect((await get("/api/market/history?symbol=AAPL&range=2Y")).json().error.code).toBe("VALIDATION_ERROR")
  })

  it("serves search results and bounds the query length", async () => {
    const results = [{ symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" }]
    const { get } = await setup(makeService({ providers: { search: { search: vi.fn(async () => results) } } }))
    expect((await get("/api/market/search?q=app")).json()).toEqual({ results })
    expect((await get(`/api/market/search?q=${"a".repeat(31)}`)).statusCode).toBe(400)
    expect((await get("/api/market/search?q=%20%20")).statusCode).toBe(400)
  })

  it("returns 404 NOT_FOUND for an unknown profile", async () => {
    const { get } = await setup()
    const response = await get("/api/market/profile?symbol=ZZZZ")
    expect(response.statusCode).toBe(404)
    expect(response.json().error.code).toBe("NOT_FOUND")
  })
})
