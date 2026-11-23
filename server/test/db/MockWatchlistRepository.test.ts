import { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { describeWatchlistRepositoryContract } from "./watchlistRepositoryContract.js"

describeWatchlistRepositoryContract("MockWatchlistRepository", async () => {
  const repository = new MockWatchlistRepository()
  return {
    repository,
    async close() {},
    async seedUser(userId) {
      repository.seedUser(userId)
    },
    async setLastStatus(userId, symbol, status) {
      repository.setLastStatus(userId, symbol, status)
    },
  }
})
