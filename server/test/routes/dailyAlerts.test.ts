import { afterEach, describe, expect, it } from "vitest"
import type { LogSink } from "../../src/lib/logSink.js"
import type { AlertJob, AlertJobResult } from "../../src/services/AlertJobService.js"
import { buildTestApp, testConfig } from "../support/app.js"

const RESULT: AlertJobResult = { tradingDate: "2026-11-20", status: "completed", evaluated: 5, transitions: 3, alertsCreated: 2, alertsSent: 1, pruned: 0 }

class FakeAlertJob implements AlertJob {
  readonly runs: Array<{ now: Date; hasLogger: boolean }> = []

  async run(now: Date, log?: LogSink): Promise<AlertJobResult> {
    this.runs.push({ now, hasLogger: log !== undefined })
    return RESULT
  }
}

describe("GET /api/internal/daily-alerts", () => {
  let close: (() => Promise<void>) | undefined

  afterEach(async () => {
    await close?.()
    close = undefined
  })

  async function setup() {
    const alertJob = new FakeAlertJob()
    const harness = await buildTestApp({ alertJob })
    close = () => harness.app.close()
    return { ...harness, alertJob }
  }

  it.each([
    { name: "no header", headers: {} },
    { name: "wrong secret", headers: { authorization: `Bearer ${"x".repeat(32)}` } },
    { name: "missing Bearer prefix", headers: { authorization: testConfig.cronSecret } },
  ])("rejects $name with 401 and does not run the job", async ({ headers }) => {
    const { app, alertJob } = await setup()
    const response = await app.inject({ method: "GET", url: "/api/internal/daily-alerts", headers })
    expect(response.statusCode).toBe(401)
    expect(response.json()).toEqual({ error: { code: "UNAUTHORIZED", message: "Missing or invalid cron secret" } })
    expect(alertJob.runs).toEqual([])
  })

  it("runs the job at the container clock's now with the request logger, and returns its stats", async () => {
    const { app, alertJob, container } = await setup()
    const response = await app.inject({
      method: "GET",
      url: "/api/internal/daily-alerts",
      headers: { authorization: `Bearer ${testConfig.cronSecret}` },
    })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual(RESULT)
    expect(alertJob.runs).toEqual([{ now: container.clock.now(), hasLogger: true }])
  })

  it("is wired with the real mock-container job by default", async () => {
    const harness = await buildTestApp()
    close = () => harness.app.close()
    const response = await harness.app.inject({
      method: "GET",
      url: "/api/internal/daily-alerts",
      headers: { authorization: `Bearer ${testConfig.cronSecret}` },
    })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({ tradingDate: "2026-11-20", status: "holiday" })
  })
})
