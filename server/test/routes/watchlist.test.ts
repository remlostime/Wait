import type { FastifyInstance } from "fastify"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { fixedClock } from "../../src/lib/clock.js"
import { buildTestApp } from "../support/app.js"

const LADDER = { buyLow: null, buyHigh: "175", fair: null, trim: null, sell: null }

function change(overrides: Record<string, unknown> = {}) {
  return {
    symbol: "AAPL",
    name: "Apple Inc.",
    ladder: LADDER,
    memo: "Wait for 175\nthen re-check margins",
    isFavorite: true,
    sortIndex: 0,
    checklist: [{ id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true }],
    ladderHistory: [{ date: "2026-11-01T00:00:00.000Z", ladder: { buyHigh: "180" } }],
    clientUpdatedAt: "2026-11-20T15:00:00.000Z",
    deleted: false,
    ...overrides,
  }
}

describe("watchlist routes", () => {
  let app: FastifyInstance
  let headers: Record<string, string>

  beforeEach(async () => {
    // Every clientUpdatedAt below is earlier than this, so the +5 min clamp never rewrites one.
    const built = await buildTestApp({ clock: fixedClock(new Date("2026-11-22T12:00:00.000Z")) })
    app = built.app
    headers = built.authHeaders()
    ;(built.container.watchlist as MockWatchlistRepository).seedUser(built.user.id)
  })

  afterEach(async () => {
    await app.close()
  })

  async function sync(payload: unknown) {
    return app.inject({ method: "POST", url: "/api/watchlist/sync", headers, payload: payload as Record<string, unknown> })
  }

  it("requires a bearer token", async () => {
    const response = await app.inject({ method: "POST", url: "/api/watchlist/sync", payload: { cursor: null, changes: [] } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("rejects an invalid body without a token with 401, not 400 (auth runs onRequest, before validation)", async () => {
    const response = await app.inject({ method: "POST", url: "/api/watchlist/sync", payload: { changes: "not-an-array", extra: 1 } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("round-trips a change with its version and cursor", async () => {
    const response = await sync({ cursor: null, changes: [change()] })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ changes: [{ ...change(), version: 1 }], cursor: "1:AAPL", hasMore: false })
  })

  it("accepts an omitted cursor and a legacy non-US symbol", async () => {
    const response = await sync({ changes: [change({ symbol: "0700.HK" })] })
    expect(response.statusCode).toBe(200)
    expect(response.json().changes[0].symbol).toBe("0700.HK")
  })

  it("returns 400 INVALID_LADDER naming the symbol", async () => {
    const response = await sync({ cursor: null, changes: [change({ ladder: { ...LADDER, buyLow: "200" } })] })
    expect(response.statusCode).toBe(400)
    expect(response.json()).toEqual({ error: { code: "INVALID_LADDER", message: "AAPL: buyLow is above buyHigh" } })
  })

  // The unknown-field case depends on plan 04's buildApp Ajv options (removeAdditional: false, overview §8.1).
  // With Fastify's defaults, the extra field would be stripped silently and the request would return 200.
  it("returns 400 VALIDATION_ERROR for a lowercase symbol, an unknown field or a malformed timestamp", async () => {
    expect((await sync({ cursor: null, changes: [change({ symbol: "aapl" })] })).json().error.code).toBe("VALIDATION_ERROR")
    expect((await sync({ cursor: null, changes: [change({ extra: true })] })).json().error.code).toBe("VALIDATION_ERROR")
    expect((await sync({ cursor: null, changes: [change({ clientUpdatedAt: "yesterday" })] })).json().error.code).toBe("VALIDATION_ERROR")
  })

  it("returns the stored row when an older change loses", async () => {
    await sync({ cursor: null, changes: [change({ memo: "server copy", clientUpdatedAt: "2026-11-20T16:00:00.000Z" })] })
    const response = await sync({ cursor: "1:AAPL", changes: [change({ memo: "stale", clientUpdatedAt: "2026-11-20T15:00:00.000Z" })] })
    expect(response.json().changes.map((row: { memo: string }) => row.memo)).toEqual(["server copy"])
  })

  it("GET /api/watchlist lists live items only", async () => {
    await sync({ cursor: null, changes: [change(), change({ symbol: "MSFT" })] })
    await sync({ cursor: null, changes: [change({ symbol: "MSFT", deleted: true, clientUpdatedAt: "2026-11-21T15:00:00.000Z" })] })
    const response = await app.inject({ method: "GET", url: "/api/watchlist", headers })
    expect(response.statusCode).toBe(200)
    expect(response.json().items.map((row: { symbol: string }) => row.symbol)).toEqual(["AAPL"])
    expect(response.json().cursor).toBe("2:MSFT")
  })
})
