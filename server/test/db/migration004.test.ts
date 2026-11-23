import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { Sql } from "../../src/db/sql.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

describe("004_alerts.sql", () => {
  let created: TestDb
  let sql: Sql

  beforeEach(async () => {
    created = await createTestDb()
    sql = created.sql
    await sql`INSERT INTO users (id, anonymous_id) VALUES ('user-1', 'anon-1')`
  })

  afterEach(async () => {
    await created.close()
  })

  it("creates the alert tables", async () => {
    const rows = await sql`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('device_tokens', 'alert_events', 'alert_job_runs')
      ORDER BY table_name`
    expect(rows.map((row) => row.table_name)).toEqual(["alert_events", "alert_job_runs", "device_tokens"])
  })

  it("only accepts sandbox or production device tokens", async () => {
    await expect(sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'development')`).rejects.toThrow()
    await sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'sandbox')`
    expect(await sql`SELECT bundle_id FROM device_tokens WHERE token = 't1'`).toEqual([{ bundle_id: "com.chenkai.wait" }])
  })

  it("keeps one event per user, symbol, trading day and status", async () => {
    const insert = (id: string) => sql`
      INSERT INTO alert_events (id, user_id, symbol, trading_date, status, price)
      VALUES (${id}, 'user-1', 'AAPL', '2026-11-20', 'BUY_ZONE', 172.1)
      ON CONFLICT (user_id, symbol, trading_date, status) DO NOTHING
      RETURNING id`
    expect(await insert("e1")).toEqual([{ id: "e1" }])
    expect(await insert("e2")).toEqual([])
  })

  it("cascades device tokens and events when the user is deleted", async () => {
    await sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'sandbox')`
    await sql`INSERT INTO alert_events (id, user_id, symbol, trading_date, status, price) VALUES ('e1', 'user-1', 'AAPL', '2026-11-20', 'BUY_ZONE', 172.1)`
    await sql`DELETE FROM users WHERE id = 'user-1'`
    const counts = await sql`SELECT (SELECT count(*)::int FROM device_tokens) AS devices, (SELECT count(*)::int FROM alert_events) AS events`
    expect(counts).toEqual([{ devices: 0, events: 0 }])
  })
})
