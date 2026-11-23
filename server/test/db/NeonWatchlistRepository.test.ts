import { NeonWatchlistRepository } from "../../src/db/NeonWatchlistRepository.js"
import { createTestDb } from "../support/pglite.js"
import { describeWatchlistRepositoryContract } from "./watchlistRepositoryContract.js"

describeWatchlistRepositoryContract("NeonWatchlistRepository (PGlite)", async () => {
  const { sql, close } = await createTestDb()
  return {
    repository: new NeonWatchlistRepository(sql),
    close,
    async seedUser(userId) {
      await sql`INSERT INTO users (id, anonymous_id) VALUES (${userId}, ${`anon-${userId}`})`
    },
    async setLastStatus(userId, symbol, status) {
      await sql`
        UPDATE watchlist_items SET last_status = ${status}, last_status_at = now()
        WHERE user_id = ${userId} AND symbol = ${symbol}`
    },
  }
})
