import { describe, expect, it } from "vitest"
import { createTestDb } from "../support/pglite.js"

const EXPECTED_COLUMNS = [
  "user_id", "symbol", "name", "buy_low", "buy_high", "fair", "trim", "sell", "memo", "is_favorite", "sort_index",
  "checklist", "ladder_history", "client_updated_at", "version", "deleted_at", "last_status", "last_status_at",
  "last_evaluated_price", "created_at", "server_updated_at",
]

describe("003_watchlist.sql", () => {
  it("creates watchlist_items with the overview §8.3 columns", async () => {
    const { sql, close } = await createTestDb()
    const rows = await sql`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'watchlist_items' ORDER BY ordinal_position`
    expect(rows.map((row) => row.column_name)).toEqual(EXPECTED_COLUMNS)
    await close()
  })

  it("cascades a user delete to their watchlist items", async () => {
    const { sql, close } = await createTestDb()
    await sql`INSERT INTO users (id, anonymous_id) VALUES ('u1', 'anon-u1')`
    await sql`
      INSERT INTO watchlist_items (user_id, symbol, name, client_updated_at, version)
      VALUES ('u1', 'AAPL', 'Apple', '2026-11-20T15:00:00.000Z', 1)`
    await sql`DELETE FROM users WHERE id = 'u1'`
    const rows = await sql`SELECT count(*)::int AS n FROM watchlist_items`
    expect(Number(rows[0]!.n)).toBe(0)
    await close()
  })
})
