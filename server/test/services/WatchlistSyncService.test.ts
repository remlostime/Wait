import { beforeEach, describe, expect, it } from "vitest"
import { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { WatchlistSyncService } from "../../src/services/WatchlistSyncService.js"
import { at, makeChange } from "../support/watchlist.js"

const now = at(60_000)

describe("WatchlistSyncService.sync", () => {
  let repository: MockWatchlistRepository
  let service: WatchlistSyncService

  beforeEach(() => {
    repository = new MockWatchlistRepository()
    repository.seedUser("u1")
    service = new WatchlistSyncService(repository)
  })

  it("pushes changes, then pulls them back with a cursor", async () => {
    const result = await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" })] }, now)
    expect(result.changes.map((row) => [row.symbol, row.version])).toEqual([["AAPL", 1]])
    expect(result.cursor).toBe("1:AAPL")
    expect(result.hasMore).toBe(false)
  })

  it("pulls nothing new from an up-to-date cursor", async () => {
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" })] }, now)
    const result = await service.sync("u1", { cursor: "1:AAPL", changes: [] }, now)
    expect(result).toEqual({ changes: [], cursor: "1:AAPL", hasMore: false })
  })

  it("returns the current row for a rejected (older) change, even when it is behind the cursor", async () => {
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL", memo: "server", clientUpdatedAt: at(2_000) })] }, now)
    const result = await service.sync(
      "u1",
      { cursor: "1:AAPL", changes: [makeChange({ symbol: "AAPL", memo: "stale", clientUpdatedAt: at(1_000) })] },
      now,
    )
    expect(result.changes.map((row) => [row.symbol, row.memo])).toEqual([["AAPL", "server"]])
    expect(result.cursor).toBe("1:AAPL")
  })

  it("clamps client timestamps to now + 5 minutes", async () => {
    const future = new Date(now.getTime() + 60 * 60 * 1000)
    const result = await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL", clientUpdatedAt: future })] }, now)
    expect(result.changes[0]!.clientUpdatedAt.toISOString()).toBe(new Date(now.getTime() + 5 * 60 * 1000).toISOString())
  })

  it("dedupes repeated symbols, keeping the latest change", async () => {
    const result = await service.sync(
      "u1",
      {
        cursor: null,
        changes: [
          makeChange({ symbol: "AAPL", memo: "late", clientUpdatedAt: at(3_000) }),
          makeChange({ symbol: "AAPL", memo: "early", clientUpdatedAt: at(1_000) }),
        ],
      },
      now,
    )
    expect(result.changes.map((row) => row.memo)).toEqual(["late"])
  })

  it("reports hasMore when a pull fills the 500-row page", async () => {
    const changes = Array.from({ length: 501 }, (_, index) => makeChange({ symbol: `S${String(index).padStart(3, "0")}` }))
    await repository.push("u1", changes, now)
    const first = await service.sync("u1", { cursor: null, changes: [] }, now)
    expect([first.changes.length, first.hasMore, first.cursor]).toEqual([500, true, "1:S499"])
    const second = await service.sync("u1", { cursor: first.cursor, changes: [] }, now)
    expect([second.changes.map((row) => row.symbol), second.hasMore]).toEqual([["S500"], false])
  })

  it("rejects an invalid ladder with INVALID_LADDER naming the symbol", async () => {
    const change = makeChange({ symbol: "NVDA", ladder: { buyLow: "12", buyHigh: "16", fair: "10", trim: null, sell: null } })
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_LADDER",
      statusCode: 400,
      message: "NVDA: buyHigh is above fair",
    })
  })

  it("rejects a non-positive anchor with INVALID_LADDER", async () => {
    const change = makeChange({ symbol: "NVDA", ladder: { buyLow: "0", buyHigh: null, fair: null, trim: null, sell: null } })
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_LADDER",
      message: "NVDA: buyLow must be greater than 0",
    })
  })

  it.each([
    ["memo", makeChange({ symbol: "AAPL", memo: "x".repeat(10_001) }), "AAPL: memo is longer than 10000 characters"],
    ["name", makeChange({ symbol: "AAPL", name: "x".repeat(501) }), "AAPL: name is longer than 500 characters"],
    [
      "checklist size",
      makeChange({ symbol: "AAPL", checklist: Array.from({ length: 101 }, (_, i) => ({ id: `c${i}`, name: "q", isChecked: false })) }),
      "AAPL: checklist has more than 100 items",
    ],
    [
      "checklist name",
      makeChange({ symbol: "AAPL", checklist: [{ id: "c1", name: "q".repeat(501), isChecked: false }] }),
      "AAPL: checklist item name is longer than 500 characters",
    ],
    [
      "history",
      makeChange({
        symbol: "AAPL",
        ladderHistory: Array.from({ length: 201 }, () => ({ date: "2026-01-01T00:00:00.000Z", ladder: { buyHigh: "1" } })),
      }),
      "AAPL: ladderHistory has more than 200 entries",
    ],
  ])("rejects an oversized %s with INVALID_INPUT", async (_label, change, message) => {
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_INPUT",
      statusCode: 400,
      message,
    })
  })

  it("rejects more than 200 changes", async () => {
    const changes = Array.from({ length: 201 }, (_, index) => makeChange({ symbol: `S${index}` }))
    await expect(service.sync("u1", { cursor: null, changes }, now)).rejects.toMatchObject({ code: "INVALID_INPUT" })
  })

  it("rejects a malformed cursor", async () => {
    await expect(service.sync("u1", { cursor: "nope", changes: [] }, now)).rejects.toMatchObject({
      code: "INVALID_INPUT",
      message: "Invalid sync cursor",
    })
  })
})

describe("WatchlistSyncService.list", () => {
  it("returns live items only, with the cursor of the newest row", async () => {
    const repository = new MockWatchlistRepository()
    repository.seedUser("u1")
    const service = new WatchlistSyncService(repository)
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" }), makeChange({ symbol: "MSFT" })] }, now)
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "MSFT", deleted: true, clientUpdatedAt: at(5_000) })] }, now)
    const result = await service.list("u1")
    expect(result.items.map((row) => row.symbol)).toEqual(["AAPL"])
    expect(result.cursor).toBe("2:MSFT")
  })
})
