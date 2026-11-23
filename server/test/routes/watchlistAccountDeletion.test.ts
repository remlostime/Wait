import { afterEach, describe, expect, it } from "vitest"
import { NeonUserRepository } from "../../src/db/NeonUserRepository.js"
import { NeonWatchlistRepository } from "../../src/db/NeonWatchlistRepository.js"
import { createTestDb } from "../support/pglite.js"
import { buildTestApp } from "../support/app.js"
import { makeChange } from "../support/watchlist.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined
let closeDb: (() => Promise<void>) | undefined

afterEach(async () => {
  await app?.close()
  await closeDb?.()
  app = undefined
  closeDb = undefined
})

describe("DELETE /api/auth/account with a SQL-backed watchlist", () => {
  it("removes the user's watchlist rows (tombstones included) and leaves other users alone", async () => {
    const { sql, close } = await createTestDb()
    closeDb = close
    const watchlist = new NeonWatchlistRepository(sql)
    const built = await buildTestApp({ sql, users: new NeonUserRepository(sql), watchlist })
    app = built.app
    await sql`INSERT INTO users (id, anonymous_id) VALUES ('other', 'anon-other')`
    const now = new Date("2026-11-22T12:00:00.000Z")
    await watchlist.push(built.user.id, [makeChange({ symbol: "AAPL" }), makeChange({ symbol: "MSFT", deleted: true })], now)
    await watchlist.push("other", [makeChange({ symbol: "AAPL" })], now)

    const response = await app.inject({ method: "DELETE", url: "/api/auth/account", headers: built.authHeaders() })

    expect(response.statusCode).toBe(204)
    const rows = await sql`SELECT user_id, symbol FROM watchlist_items ORDER BY user_id, symbol`
    expect(rows.map((row) => [row.user_id, row.symbol])).toEqual([["other", "AAPL"]])
  })
})
