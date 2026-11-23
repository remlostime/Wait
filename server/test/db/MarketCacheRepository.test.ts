import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { MarketCacheRepository } from "../../src/db/MarketCacheRepository.js"
import { MockMarketCacheRepository } from "../../src/db/MockMarketCacheRepository.js"
import { NeonMarketCacheRepository } from "../../src/db/NeonMarketCacheRepository.js"
import type { ProviderQuote } from "../../src/providers/types.js"
import { createTestDb } from "../support/pglite.js"

const fetchedAt = new Date("2026-11-20T15:00:00.000Z")
const expiresAt = new Date("2026-11-20T15:03:00.000Z")
const quote = (symbol: string, price: string): ProviderQuote => ({
  symbol, price, previousClose: "170", open: "171", high: "173", low: "170.5", change: "2.1", changePercent: 1.235, asOf: "2026-11-20T14:59:00.000Z",
})

const implementations: Array<[string, () => Promise<{ repo: MarketCacheRepository; close: () => Promise<void> }>]> = [
  ["NeonMarketCacheRepository (PGlite)", async () => {
    const db = await createTestDb()
    return { repo: new NeonMarketCacheRepository(db.sql), close: db.close }
  }],
  ["MockMarketCacheRepository", async () => ({ repo: new MockMarketCacheRepository(), close: async () => {} })],
]

describe.each(implementations)("%s", (_name, make) => {
  let repo: MarketCacheRepository
  let close: () => Promise<void>
  beforeEach(async () => {
    ;({ repo, close } = await make())
  })
  afterEach(async () => {
    await close()
  })

  it("round-trips quotes and returns only requested symbols", async () => {
    await repo.putQuotes([
      { symbol: "AAPL", payload: quote("AAPL", "172.1"), provider: "finnhub", fetchedAt, expiresAt },
      { symbol: "MSFT", payload: quote("MSFT", "410"), provider: "finnhub", fetchedAt, expiresAt },
    ])
    const found = await repo.getQuotes(["AAPL", "NVDA"])
    expect([...found.keys()]).toEqual(["AAPL"])
    expect(found.get("AAPL")).toEqual({ payload: quote("AAPL", "172.1"), provider: "finnhub", fetchedAt, expiresAt })
  })

  it("upserts quotes and ignores an empty batch", async () => {
    await repo.putQuotes([{ symbol: "AAPL", payload: quote("AAPL", "1"), provider: "finnhub", fetchedAt, expiresAt }])
    await repo.putQuotes([{ symbol: "AAPL", payload: quote("AAPL", "2"), provider: "finnhub", fetchedAt, expiresAt }])
    await repo.putQuotes([])
    expect((await repo.getQuotes(["AAPL"])).get("AAPL")?.payload.price).toBe("2")
  })

  it("round-trips history per (symbol, series)", async () => {
    const bars = [{ t: "2026-11-19T00:00:00.000Z", c: "171.2" }, { t: "2026-11-20T00:00:00.000Z", c: "172.1" }]
    await repo.putHistory("AAPL", "daily5y", { payload: bars, provider: "tiingo", fetchedAt, expiresAt })
    expect(await repo.getHistory("AAPL", "daily5y")).toEqual({ payload: bars, provider: "tiingo", fetchedAt, expiresAt })
    expect(await repo.getHistory("AAPL", "1D")).toBeNull()
  })

  it("round-trips profile and search payloads", async () => {
    const profile = { profile: null, metrics: null, profileFetchedAt: fetchedAt.toISOString() }
    await repo.putProfile("AAPL", { payload: profile, provider: "finnhub", fetchedAt, expiresAt })
    expect((await repo.getProfile("AAPL"))?.payload).toEqual(profile)
    const matches = [{ symbol: "AAPL", name: "Apple Inc", exchange: null, type: "Common Stock" }]
    await repo.putSearch("app", { payload: matches, provider: "finnhub", fetchedAt, expiresAt })
    expect((await repo.getSearch("app"))?.payload).toEqual(matches)
    expect(await repo.getSearch("zzz")).toBeNull()
  })
})
