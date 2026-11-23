import { describe, expect, it } from "vitest"
import { TiingoProvider } from "../../src/providers/tiingo.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const KEY = "tiingo-test-key"

describe("TiingoProvider", () => {
  it("maps daily bars to adjusted closes, oldest first", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json(fixture("tiingo-daily-aapl.json")) }])
    const bars = await new TiingoProvider(KEY, fake.fetch).getDailyBars("AAPL", "2021-11-13", "2026-11-20")
    expect(bars).toEqual([
      { t: "2026-11-18T00:00:00.000Z", c: "169.9" },
      { t: "2026-11-19T00:00:00.000Z", c: "171.2" },
      { t: "2026-11-20T00:00:00.000Z", c: "172.1" },
    ])
    expect(fake.calls[0]?.url.toString()).toBe(
      "https://api.tiingo.com/tiingo/daily/aapl/prices?startDate=2021-11-13&endDate=2026-11-20&resampleFreq=daily",
    )
    expect(headerOf(fake.calls[0]?.init, "authorization")).toBe(`Token ${KEY}`)
    expect(fake.calls[0]?.url.toString()).not.toContain(KEY)
  })

  it("uses Tiingo's dash form for class shares and returns [] for unknown tickers", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => new Response("{}", { status: 404 }) }])
    expect(await new TiingoProvider(KEY, fake.fetch).getDailyBars("BRK.B", "2026-01-01", "2026-11-20")).toEqual([])
    expect(fake.calls[0]?.url.pathname).toBe("/tiingo/daily/brk-b/prices")
  })

  it("treats a non-array body as bad_response", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json({ detail: "Error: Ticker 'ZZZZ' not found" }) }])
    await expect(new TiingoProvider(KEY, fake.fetch).getDailyBars("ZZZZ", "2026-01-01", "2026-11-20")).rejects.toMatchObject({
      provider: "tiingo",
      kind: "bad_response",
    })
  })
})
