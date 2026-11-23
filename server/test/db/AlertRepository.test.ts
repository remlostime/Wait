import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { AlertRepository, NewAlertEvent } from "../../src/db/AlertRepository.js"
import { MockAlertRepository } from "../../src/db/MockAlertRepository.js"
import { NeonAlertRepository } from "../../src/db/NeonAlertRepository.js"
import type { Sql } from "../../src/db/sql.js"
import { insertItem, toEvaluableItem, type ItemFixture } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"

type Status = { lastStatus: string | null; lastEvaluatedPrice: string | null }
type Harness = {
  repo: AlertRepository
  seed: (items: ItemFixture[]) => Promise<void>
  statusOf: (userId: string, symbol: string) => Promise<Status>
  close: () => Promise<void>
}

const harnesses: Array<[string, () => Promise<Harness>]> = [
  [
    "NeonAlertRepository (PGlite)",
    async () => {
      const created = await createTestDb()
      const sql = created.sql
      return {
        repo: new NeonAlertRepository(sql),
        seed: async (items) => {
          for (const item of items) await insertItem(sql, item)
        },
        statusOf: async (userId, symbol) => {
          const [row] = await sql`
            SELECT last_status, trim_scale(last_evaluated_price)::text AS price
            FROM watchlist_items WHERE user_id = ${userId} AND symbol = ${symbol}`
          return { lastStatus: (row?.last_status as string | null) ?? null, lastEvaluatedPrice: (row?.price as string | null) ?? null }
        },
        close: () => created.close(),
      }
    },
  ],
  [
    "MockAlertRepository",
    async () => {
      const repo = new MockAlertRepository()
      return {
        repo,
        seed: async (items) => repo.seedItems(items.map(toEvaluableItem)),
        statusOf: async (userId, symbol) => {
          const item = repo.item(userId, symbol)
          return { lastStatus: item?.lastStatus ?? null, lastEvaluatedPrice: item?.lastEvaluatedPrice ?? null }
        },
        close: async () => {},
      }
    },
  ],
]

const NOW = new Date("2026-11-20T22:00:00.000Z")

function event(overrides: Partial<NewAlertEvent> & Pick<NewAlertEvent, "id">): NewAlertEvent {
  return { userId: "user-1", symbol: "AAPL", tradingDate: "2026-11-20", status: "BUY_ZONE", previousStatus: "WATCH", price: "172.1", ...overrides }
}

const SEED: ItemFixture[] = [
  { userId: "user-1", symbol: "AAPL", buyLow: "150", buyHigh: "175", fair: "210", lastStatus: "WATCH", lastEvaluatedPrice: "180.5" },
  { userId: "user-2", symbol: "AAPL", buyHigh: "160" },
  { userId: "user-1", symbol: "MSFT" },
  { userId: "user-1", symbol: "TSLA", buyHigh: "200", deleted: true },
]

describe.each(harnesses)("%s", (_name, makeHarness) => {
  let harness: Harness

  beforeEach(async () => {
    harness = await makeHarness()
    await harness.seed(SEED)
  })

  afterEach(async () => {
    await harness.close()
  })

  it("lists live items with at least one anchor, ordered by symbol then user", async () => {
    expect(await harness.repo.listEvaluableItems()).toEqual([
      {
        userId: "user-1",
        symbol: "AAPL",
        ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
        lastStatus: "WATCH",
        lastEvaluatedPrice: "180.5",
      },
      {
        userId: "user-2",
        symbol: "AAPL",
        ladder: { buyLow: null, buyHigh: "160", fair: null, trim: null, sell: null },
        lastStatus: null,
        lastEvaluatedPrice: null,
      },
    ])
  })

  it("inserts events once per user, symbol, day and status", async () => {
    expect(await harness.repo.insertEvents([event({ id: "e1" })], NOW)).toEqual(["e1"])
    expect(await harness.repo.insertEvents([event({ id: "e2" }), event({ id: "e3", userId: "user-2" })], NOW)).toEqual(["e3"])
    expect(await harness.repo.insertEvents([], NOW)).toEqual([])
  })

  it("applies evaluated statuses and prices", async () => {
    await harness.repo.applyEvaluations(
      [
        { userId: "user-1", symbol: "AAPL", previousStatus: "WATCH", status: "BUY_ZONE", price: "172.1" },
        { userId: "user-2", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "158" },
      ],
      NOW,
    )
    expect(await harness.statusOf("user-1", "AAPL")).toEqual({ lastStatus: "BUY_ZONE", lastEvaluatedPrice: "172.1" })
    expect(await harness.statusOf("user-2", "AAPL")).toEqual({ lastStatus: "BUY_ZONE", lastEvaluatedPrice: "158" })
    await harness.repo.applyEvaluations([], NOW)
  })

  it("leaves a row alone when its status changed since the job read it (e.g. sync reset it to NULL)", async () => {
    await harness.repo.applyEvaluations([{ userId: "user-1", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "172.1" }], NOW)
    expect(await harness.statusOf("user-1", "AAPL")).toEqual({ lastStatus: "WATCH", lastEvaluatedPrice: "180.5" })
  })

  it("lists only unsent events of the day under the attempt limit, with the item's ladder", async () => {
    await harness.repo.insertEvents([event({ id: "e1" })], NOW)
    await harness.repo.insertEvents([event({ id: "e2", userId: "user-2" })], NOW)
    await harness.repo.insertEvents([event({ id: "e3", tradingDate: "2026-11-19" })], NOW)
    await harness.repo.insertEvents([event({ id: "e4", status: "DEEP_BUY", previousStatus: "BUY_ZONE" })], NOW)
    await harness.repo.markSent("e2", NOW)
    await harness.repo.claimForSend("e1", 0)
    await harness.repo.claimForSend("e1", 1)
    for (let attempt = 0; attempt < 3; attempt += 1) await harness.repo.claimForSend("e4", attempt)

    expect(await harness.repo.listPendingEvents("2026-11-20", 3)).toEqual([
      {
        id: "e1",
        userId: "user-1",
        symbol: "AAPL",
        tradingDate: "2026-11-20",
        status: "BUY_ZONE",
        previousStatus: "WATCH",
        price: "172.1",
        attempts: 2,
        ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
      },
    ])
  })

  it("lets exactly one caller claim an event for a given attempt count, and counts the claim as an attempt", async () => {
    await harness.repo.insertEvents([event({ id: "e1" })], NOW)
    expect(await Promise.all([harness.repo.claimForSend("e1", 0), harness.repo.claimForSend("e1", 0)])).toEqual(expect.arrayContaining([true, false]))
    expect(await harness.repo.claimForSend("e1", 0)).toBe(false)
    expect((await harness.repo.listPendingEvents("2026-11-20", 3))[0]?.attempts).toBe(1)
    expect(await harness.repo.claimForSend("e1", 1)).toBe(true)
    await harness.repo.markSent("e1", NOW)
    expect(await harness.repo.claimForSend("e1", 2)).toBe(false)
    expect(await harness.repo.claimForSend("missing", 0)).toBe(false)
  })

  it("claims a day once, refuses a fresh running claim, and takes over a stale one", async () => {
    const nineMinutesLater = new Date(NOW.getTime() + 9 * 60_000)
    const elevenMinutesLater = new Date(NOW.getTime() + 11 * 60_000)
    expect(await harness.repo.beginRun("2026-11-20", NOW)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: true })
    expect(await harness.repo.beginRun("2026-11-20", nineMinutesLater)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: false })
    expect(await harness.repo.beginRun("2026-11-20", elevenMinutesLater)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: true })
    await harness.repo.finishRun("2026-11-20", "completed", { evaluated: 2 }, elevenMinutesLater)
    expect(await harness.repo.beginRun("2026-11-20", new Date(NOW.getTime() + 60 * 60_000))).toEqual({
      tradingDate: "2026-11-20",
      status: "completed",
      claimed: false,
    })
  })
})

describe("NeonAlertRepository (PGlite only)", () => {
  it("does not bump the sync version or server_updated_at when applying evaluations", async () => {
    const created = await createTestDb()
    const sql: Sql = created.sql
    await insertItem(sql, { userId: "user-1", symbol: "AAPL", buyHigh: "175", version: 7 })
    const [before] = await sql`SELECT version, server_updated_at FROM watchlist_items WHERE symbol = 'AAPL'`
    await new NeonAlertRepository(sql).applyEvaluations([{ userId: "user-1", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "170" }], NOW)
    const [after] = await sql`SELECT version, server_updated_at, last_status_at FROM watchlist_items WHERE symbol = 'AAPL'`
    expect(String(after?.version)).toBe("7")
    expect(after?.server_updated_at).toEqual(before?.server_updated_at)
    expect(after?.last_status_at).toEqual(NOW)
    await created.close()
  })
})
