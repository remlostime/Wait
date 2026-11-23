import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { WatchlistRepository } from "../../src/db/WatchlistRepository.js"
import { START_CURSOR } from "../../src/db/watchlistTypes.js"
import { at, makeChange } from "../support/watchlist.js"

export type WatchlistRepositoryHarness = {
  repository: WatchlistRepository
  close(): Promise<void>
  seedUser(userId: string): Promise<void>
  /** Simulates the plan 06 alert job writing a server-owned status. */
  setLastStatus(userId: string, symbol: string, status: string): Promise<void>
}

export function describeWatchlistRepositoryContract(name: string, makeHarness: () => Promise<WatchlistRepositoryHarness>) {
  describe(`${name} satisfies the WatchlistRepository contract`, () => {
    let harness: WatchlistRepositoryHarness
    const now = at(60_000)

    beforeEach(async () => {
      harness = await makeHarness()
      await harness.seedUser("u1")
      await harness.seedUser("u2")
    })

    afterEach(async () => {
      await harness.close()
    })

    it("inserts new items, reports them as applied and returns them from pull", async () => {
      const applied = await harness.repository.push(
        "u1",
        [makeChange({ symbol: "MSFT" }), makeChange({ symbol: "AAPL", ladder: { buyLow: "12", buyHigh: "14.2", fair: null, trim: null, sell: null } })],
        now,
      )
      expect(applied).toEqual(["AAPL", "MSFT"])
      const rows = await harness.repository.pull("u1", START_CURSOR, 100)
      expect(rows.map((row) => [row.symbol, row.version, row.deleted])).toEqual([
        ["AAPL", 1, false],
        ["MSFT", 1, false],
      ])
      expect(rows[0]!.ladder).toEqual({ buyLow: "12", buyHigh: "14.2", fair: null, trim: null, sell: null })
      expect(rows[0]!.clientUpdatedAt.toISOString()).toBe("2026-11-20T15:00:00.000Z")
    })

    it("rejects an older edit and keeps the stored row", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "newer", clientUpdatedAt: at(2_000) })], now)
      const applied = await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "older", clientUpdatedAt: at(1_000) })], now)
      expect(applied).toEqual([])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.memo).toBe("newer")
    })

    it("keeps the stored row when timestamps tie (server wins)", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "first", clientUpdatedAt: at(1_000) })], now)
      const applied = await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "second", clientUpdatedAt: at(1_000) })], now)
      expect(applied).toEqual([])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.memo).toBe("first")
    })

    it("stores a tombstone and resurrects the item on a newer re-add", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      expect(await harness.repository.push("u1", [makeChange({ symbol: "AAPL", deleted: true, clientUpdatedAt: at(2_000) })], now)).toEqual(["AAPL"])
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.deleted).toBe(true)
      expect(await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "back", clientUpdatedAt: at(3_000) })], now)).toEqual(["AAPL"])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect([row!.deleted, row!.memo]).toEqual([false, "back"])
    })

    it("assigns a new, increasing version to every push", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "MSFT", clientUpdatedAt: at(1_000) })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(2_000) })], now)
      const rows = await harness.repository.pull("u1", START_CURSOR, 100)
      expect(rows.map((row) => [row.symbol, row.version])).toEqual([
        ["MSFT", 2],
        ["AAPL", 3],
      ])
    })

    it("pages through rows with the (version, symbol) cursor", async () => {
      await harness.repository.push(
        "u1",
        ["NVDA", "AAPL", "MSFT"].map((symbol) => makeChange({ symbol })),
        now,
      )
      const page1 = await harness.repository.pull("u1", START_CURSOR, 2)
      expect(page1.map((row) => row.symbol)).toEqual(["AAPL", "MSFT"])
      const page2 = await harness.repository.pull("u1", { version: page1[1]!.version, symbol: page1[1]!.symbol }, 2)
      expect(page2.map((row) => row.symbol)).toEqual(["NVDA"])
      const page3 = await harness.repository.pull("u1", { version: page2[0]!.version, symbol: page2[0]!.symbol }, 2)
      expect(page3).toEqual([])
    })

    it("resets last_status only when an anchor value changes", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      await harness.setLastStatus("u1", "AAPL", "BUY_ZONE")
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "note only", clientUpdatedAt: at(2_000) })], now)
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBe("BUY_ZONE")
      await harness.repository.push(
        "u1",
        [makeChange({ symbol: "AAPL", ladder: { buyLow: null, buyHigh: "100.000", fair: null, trim: null, sell: null }, clientUpdatedAt: at(3_000) })],
        now,
      )
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBe("BUY_ZONE")
      await harness.repository.push(
        "u1",
        [makeChange({ symbol: "AAPL", ladder: { buyLow: null, buyHigh: "90", fair: null, trim: null, sell: null }, clientUpdatedAt: at(4_000) })],
        now,
      )
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBeNull()
    })

    it("isolates users from each other", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL" })], now)
      expect(await harness.repository.pull("u2", START_CURSOR, 100)).toEqual([])
      expect(await harness.repository.findBySymbols("u2", ["AAPL"])).toEqual([])
    })

    it("findBySymbols returns current rows, tombstones included, and ignores unknown symbols", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL" }), makeChange({ symbol: "MSFT" })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "MSFT", deleted: true, clientUpdatedAt: at(5_000) })], now)
      const rows = await harness.repository.findBySymbols("u1", ["MSFT", "TSLA"])
      expect(rows.map((row) => [row.symbol, row.deleted])).toEqual([["MSFT", true]])
      expect(await harness.repository.findBySymbols("u1", [])).toEqual([])
    })

    it("stores checklist and ladder history verbatim", async () => {
      const checklist = [{ id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true }]
      const ladderHistory = [{ date: "2026-01-02T00:00:00.000Z", ladder: { buyHigh: "120" } }]
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", checklist, ladderHistory })], now)
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.checklist).toEqual(checklist)
      expect(row!.ladderHistory).toEqual(ladderHistory)
    })

    it("applies nothing for an unknown user", async () => {
      expect(await harness.repository.push("ghost", [makeChange({ symbol: "AAPL" })], now)).toEqual([])
    })
  })
}
