import { describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import { NeonAlertRepository } from "../../src/db/NeonAlertRepository.js"
import { NeonDeviceTokenRepository } from "../../src/db/NeonDeviceTokenRepository.js"
import { AlertJobService } from "../../src/services/AlertJobService.js"
import { insertItem } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"
import { FakeCloseResolver, SCENARIO_RESOLUTION } from "../support/alertScenario.js"

const NOW = new Date("2026-11-20T22:00:00.000Z")

describe("AlertJobService on PGlite", () => {
  it("runs the scenario end to end and is idempotent on rerun", async () => {
    const { sql, close } = await createTestDb()
    await insertItem(sql, { userId: "user-1", symbol: "AAPL", buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260", lastStatus: "WATCH", lastEvaluatedPrice: "180" })
    await insertItem(sql, { userId: "user-1", symbol: "MSFT", buyHigh: "300", trim: "450" })
    await insertItem(sql, { userId: "user-2", symbol: "NVDA", buyHigh: "100", trim: "180", lastStatus: "WATCH", lastEvaluatedPrice: "170" })
    await insertItem(sql, { userId: "user-2", symbol: "TSLA", buyLow: "100", buyHigh: "120", fair: "200", lastStatus: "WATCH", lastEvaluatedPrice: "300" })
    await insertItem(sql, { userId: "user-1", symbol: "AMD", buyHigh: "100", lastStatus: "BUY_ZONE", lastEvaluatedPrice: "95" })
    await insertItem(sql, { userId: "user-2", symbol: "BRK.B", buyHigh: "400", lastStatus: "WATCH", lastEvaluatedPrice: "470" })
    const devices = new NeonDeviceTokenRepository(sql)
    await devices.upsert({ token: "a".repeat(64), userId: "user-1", environment: "sandbox", bundleId: "com.chenkai.wait" }, NOW)
    const transport = new MockApnsTransport()
    const job = new AlertJobService({
      alerts: new NeonAlertRepository(sql),
      devices,
      closes: new FakeCloseResolver(SCENARIO_RESOLUTION),
      sender: new ApnsSender({ transport, tokens: { token: () => "jwt", invalidate: () => {} }, topic: "com.chenkai.wait", devices, clock: { now: () => NOW } }),
    })

    expect(await job.run(NOW)).toEqual({ tradingDate: "2026-11-20", status: "completed", evaluated: 5, transitions: 3, alertsCreated: 2, alertsSent: 1, pruned: 0 })
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 })

    const rows = await sql`SELECT symbol, last_status, trim_scale(last_evaluated_price)::text AS price FROM watchlist_items ORDER BY symbol`
    expect(rows).toEqual([
      { symbol: "AAPL", last_status: "BUY_ZONE", price: "172.1" },
      { symbol: "AMD", last_status: "BUY_ZONE", price: "90" },
      { symbol: "BRK.B", last_status: "WATCH", price: "470" },
      { symbol: "MSFT", last_status: "WATCH", price: "420" },
      { symbol: "NVDA", last_status: "TRIM", price: "185" },
      { symbol: "TSLA", last_status: "DEEP_BUY", price: "30" },
    ])
    const events = await sql`SELECT symbol, status, sent_at IS NOT NULL AS sent FROM alert_events ORDER BY symbol`
    expect(events).toEqual([
      { symbol: "AAPL", status: "BUY_ZONE", sent: true },
      { symbol: "NVDA", status: "TRIM", sent: true },
    ])
    expect(await sql`SELECT status, (stats->>'splitSkips')::int AS split_skips FROM alert_job_runs`).toEqual([{ status: "completed", split_skips: 1 }])
    expect(transport.calls).toHaveLength(1)
    await close()
  })

  it("does not seed a status over anchors that sync edited between the job's read and its write", async () => {
    const { sql, close } = await createTestDb()
    await insertItem(sql, { userId: "user-1", symbol: "MSFT", buyHigh: "300", trim: "450" }) // never evaluated: last_status NULL
    const devices = new NeonDeviceTokenRepository(sql)
    const repo = new NeonAlertRepository(sql)
    const racing = new Proxy(repo, {
      get(target, property) {
        if (property === "applyEvaluations") {
          return async (...args: Parameters<NeonAlertRepository["applyEvaluations"]>) => {
            await sql`UPDATE watchlist_items SET buy_high = 250, last_status = NULL WHERE symbol = 'MSFT'` // plan 05's sync, mid-run
            return target.applyEvaluations(...args)
          }
        }
        const value = Reflect.get(target, property)
        return typeof value === "function" ? value.bind(target) : value
      },
    })
    const job = new AlertJobService({
      alerts: racing,
      devices,
      closes: new FakeCloseResolver(SCENARIO_RESOLUTION),
      sender: new ApnsSender({ transport: new MockApnsTransport(), tokens: { token: () => "jwt", invalidate: () => {} }, topic: "com.chenkai.wait", devices, clock: { now: () => NOW } }),
    })

    await job.run(NOW)

    expect(await sql`SELECT last_status, last_evaluated_price FROM watchlist_items WHERE symbol = 'MSFT'`).toEqual([{ last_status: null, last_evaluated_price: null }])
    await close()
  })
})
