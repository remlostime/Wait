import { describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import type { AlertRepository, EvaluableItem } from "../../src/db/AlertRepository.js"
import { MockAlertRepository } from "../../src/db/MockAlertRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { ProviderError } from "../../src/providers/types.js"
import { AlertJobService } from "../../src/services/AlertJobService.js"
import type { CloseResolution, CloseResolver } from "../../src/services/DailyCloseResolver.js"
import { RecordingLogger } from "../support/alertFakes.js"
import { FakeCloseResolver, SCENARIO_RESOLUTION, scenarioItems } from "../support/alertScenario.js"

const NOW = new Date("2026-11-20T22:00:00.000Z") // Friday, 5pm ET
const ELEVEN_MINUTES_LATER = new Date(NOW.getTime() + 11 * 60_000) // a crashed run's claim is stale by then
const DEVICE = "a".repeat(64)

/** Wraps a repository so that the first call to `method` throws (simulates a crash mid-job). */
function failOnce<T extends object>(target: T, method: keyof T): T {
  let failed = false
  return new Proxy(target, {
    get(object, property, receiver) {
      const value = Reflect.get(object, property, receiver)
      if (typeof value !== "function") return value
      if (property === method && !failed) {
        return async () => {
          failed = true
          throw new Error(`injected failure in ${String(property)}`)
        }
      }
      return value.bind(object)
    },
  })
}

/** Simulates plan 05's sync resetting `last_status` (an anchor edit) between the job's read and its write. */
function resetBeforeApply(target: MockAlertRepository, userId: string, symbol: string): AlertRepository {
  return new Proxy(target, {
    get(object, property, receiver) {
      const value = Reflect.get(object, property, receiver)
      if (typeof value !== "function") return value
      if (property === "applyEvaluations") {
        return async (...args: Parameters<MockAlertRepository["applyEvaluations"]>) => {
          object.resetStatus(userId, symbol)
          return object.applyEvaluations(...args)
        }
      }
      return value.bind(object)
    },
  })
}

/** Simulates plan 05's sync editing the anchors (and resetting `last_status`) between the job's read and its write. */
function editAnchorsBeforeApply(target: MockAlertRepository, userId: string, symbol: string): AlertRepository {
  return new Proxy(target, {
    get(object, property, receiver) {
      const value = Reflect.get(object, property, receiver)
      if (typeof value !== "function") return value
      if (property === "applyEvaluations") {
        return async (...args: Parameters<MockAlertRepository["applyEvaluations"]>) => {
          object.seedItems([{ ...(object.item(userId, symbol) as EvaluableItem), ladder: { buyLow: null, buyHigh: "250", fair: null, trim: "500", sell: null }, lastStatus: null }])
          return object.applyEvaluations(...args)
        }
      }
      return value.bind(object)
    },
  })
}

function makeJob(options: { resolution?: CloseResolution; closes?: CloseResolver; wrap?: (repo: MockAlertRepository) => AlertRepository } = {}) {
  const alertsRepo = new MockAlertRepository()
  alertsRepo.seedItems(scenarioItems())
  const devices = new MockDeviceTokenRepository()
  devices.seed([{ token: DEVICE, userId: "user-1", environment: "sandbox", bundleId: "com.chenkai.wait", createdAt: NOW, updatedAt: NOW, lastSuccessAt: null }])
  const transport = new MockApnsTransport()
  const sender = new ApnsSender({
    transport,
    tokens: { token: () => "provider-jwt", invalidate: () => {} },
    topic: "com.chenkai.wait",
    devices,
    clock: { now: () => NOW },
    sleep: async () => {},
  })
  const closes = options.closes ?? new FakeCloseResolver(options.resolution ?? SCENARIO_RESOLUTION)
  let counter = 0
  const job = new AlertJobService({
    alerts: options.wrap ? options.wrap(alertsRepo) : alertsRepo,
    devices,
    closes,
    sender,
    newId: () => `event-${(counter += 1)}`,
  })
  return { job, alertsRepo, devices, transport, closes: closes as FakeCloseResolver }
}

const statuses = (repo: MockAlertRepository) =>
  ["AAPL", "MSFT", "NVDA", "TSLA", "AMD", "BRK.B"].map((symbol) => {
    const item = repo.item(symbol === "NVDA" || symbol === "TSLA" || symbol === "BRK.B" ? "user-2" : "user-1", symbol)
    return [symbol, item?.lastStatus ?? null, item?.lastEvaluatedPrice ?? null]
  })

describe("AlertJobService", () => {
  it("evaluates, seeds, guards splits, records events and pushes once", async () => {
    const { job, alertsRepo, transport, closes } = makeJob()
    const log = new RecordingLogger()

    expect(await job.run(NOW, log)).toEqual({
      tradingDate: "2026-11-20",
      status: "completed",
      evaluated: 5,
      transitions: 3,
      alertsCreated: 2,
      alertsSent: 1,
      pruned: 0,
    })
    expect(closes.calls).toEqual([{ tradingDate: "2026-11-20", symbols: ["AAPL", "AMD", "BRK.B", "MSFT", "NVDA", "TSLA"] }])
    expect(alertsRepo.allEvents().map((event) => [event.id, event.symbol, event.previousStatus, event.status, event.price, event.sentAt !== null])).toEqual([
      ["event-1", "AAPL", "WATCH", "BUY_ZONE", "172.1", true],
      ["event-2", "NVDA", "WATCH", "TRIM", "185", true],
    ])
    expect(statuses(alertsRepo)).toEqual([
      ["AAPL", "BUY_ZONE", "172.1"],
      ["MSFT", "WATCH", "420"],
      ["NVDA", "TRIM", "185"],
      ["TSLA", "DEEP_BUY", "30"],
      ["AMD", "BUY_ZONE", "90"],
      ["BRK.B", "WATCH", "470"],
    ])
    expect(transport.calls).toHaveLength(1)
    expect((JSON.parse(transport.calls[0]?.body ?? "{}") as { aps: { alert: unknown } }).aps.alert).toEqual({
      title: "AAPL · BUY ZONE",
      body: "Closed $172.10, at or below buy-high $175.00 · 28°",
    })
    expect(alertsRepo.runStatus("2026-11-20")).toBe("completed")
    expect(log.entries).toContainEqual({
      level: "warn",
      message: "alerts.split_guard",
      details: { tradingDate: "2026-11-20", symbol: "TSLA", previousPrice: "300", close: "30" },
    })
  })

  it("returns skipped while another delivery of the same cron is still running", async () => {
    const { job, closes } = makeJob({ wrap: (repo) => failOnce(repo, "applyEvaluations") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure")
    expect(await job.run(new Date(NOW.getTime() + 60_000))).toMatchObject({ status: "skipped", evaluated: 0 })
    expect(closes.calls).toHaveLength(1)
  })

  it("only evaluates US market symbols (plan 04's SYMBOL_REGEX)", async () => {
    const { job, alertsRepo, closes } = makeJob()
    alertsRepo.seedItems([{ userId: "user-1", symbol: "0700.HK", ladder: { buyHigh: "300" }, lastStatus: "WATCH", lastEvaluatedPrice: "320" }])
    expect(await job.run(NOW)).toMatchObject({ status: "completed", evaluated: 5 })
    expect(closes.calls[0]?.symbols).not.toContain("0700.HK")
    expect(alertsRepo.item("user-1", "0700.HK")?.lastStatus).toBe("WATCH")
  })

  it("does not overwrite a status that sync reset while the job was running", async () => {
    const { job, alertsRepo } = makeJob({ wrap: (repo) => resetBeforeApply(repo, "user-1", "AAPL") })
    await job.run(NOW)
    expect(alertsRepo.item("user-1", "AAPL")?.lastStatus).toBeNull()
  })

  it("does not overwrite a freshly seeded status when the anchors changed while the job was running", async () => {
    // MSFT is unseeded (last_status NULL), so the status guard alone cannot tell that sync edited its anchors mid-run.
    const { job, alertsRepo } = makeJob({ wrap: (repo) => editAnchorsBeforeApply(repo, "user-1", "MSFT") })
    await job.run(NOW)
    expect(alertsRepo.item("user-1", "MSFT")).toMatchObject({ lastStatus: null, lastEvaluatedPrice: null })
    expect(alertsRepo.item("user-1", "AMD")?.lastStatus).toBe("BUY_ZONE")
  })

  it("does not record a holiday, or finish the run, when the holiday check could not be answered", async () => {
    let calls = 0
    const closes: CloseResolver = {
      resolve: async () => {
        calls += 1
        if (calls === 1) throw new ProviderError("finnhub", "bad_response")
        return SCENARIO_RESOLUTION
      },
    }
    const { job, alertsRepo } = makeJob({ closes })
    await expect(job.run(NOW)).rejects.toThrow("finnhub:bad_response")
    expect(alertsRepo.runStatus("2026-11-20")).toBe("running")
    // The catch-up cron: the stale claim is taken over and the day is evaluated for real.
    expect(await job.run(ELEVEN_MINUTES_LATER)).toMatchObject({ status: "completed", evaluated: 5, alertsSent: 1 })
  })

  it("skips weekends without touching the database", async () => {
    const { job, alertsRepo, closes } = makeJob()
    expect(await job.run(new Date("2026-11-21T22:00:00.000Z"))).toEqual({
      tradingDate: "2026-11-21",
      status: "skipped",
      evaluated: 0,
      transitions: 0,
      alertsCreated: 0,
      alertsSent: 0,
      pruned: 0,
    })
    expect(closes.calls).toEqual([])
    expect(alertsRepo.runStatus("2026-11-21")).toBeUndefined()
  })

  it("records a holiday once and does not re-resolve it", async () => {
    const { job, alertsRepo, closes } = makeJob({ resolution: { kind: "holiday" } })
    const thanksgiving = new Date("2026-11-26T22:00:00.000Z")
    expect((await job.run(thanksgiving)).status).toBe("holiday")
    expect((await job.run(thanksgiving)).status).toBe("holiday")
    expect(closes.calls).toHaveLength(1)
    expect(alertsRepo.runStatus("2026-11-26")).toBe("holiday")
    expect(alertsRepo.item("user-1", "AAPL")?.lastStatus).toBe("WATCH")
  })

  it("only re-sends pending events when the day already completed", async () => {
    const { job, transport, closes } = makeJob()
    await job.run(NOW)
    expect(await job.run(NOW)).toEqual({
      tradingDate: "2026-11-20",
      status: "resent",
      evaluated: 0,
      transitions: 0,
      alertsCreated: 0,
      alertsSent: 0,
      pruned: 0,
    })
    expect(transport.calls).toHaveLength(1)
    expect(closes.calls).toHaveLength(1)
  })

  it("recovers from a crash after inserting events without duplicating them", async () => {
    const { job, alertsRepo, transport } = makeJob({ wrap: (repo) => failOnce(repo, "applyEvaluations") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure in applyEvaluations")
    expect(await job.run(ELEVEN_MINUTES_LATER)).toMatchObject({ status: "completed", transitions: 3, alertsCreated: 0, alertsSent: 1 })
    expect(alertsRepo.allEvents()).toHaveLength(2)
    expect(transport.calls).toHaveLength(1)
  })

  it("recovers from a crash after updating statuses by sending the pending events", async () => {
    const { job, transport } = makeJob({ wrap: (repo) => failOnce(repo, "listPendingEvents") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure in listPendingEvents")
    expect(await job.run(ELEVEN_MINUTES_LATER)).toMatchObject({ status: "completed", transitions: 0, alertsCreated: 0, alertsSent: 1 })
    expect(transport.calls).toHaveLength(1)
  })

  it("retries failed deliveries on the next run of the same day", async () => {
    const { job, transport, alertsRepo } = makeJob()
    transport.script({ status: 500 }, { status: 500 })
    expect(await job.run(NOW)).toMatchObject({ status: "completed", alertsCreated: 2, alertsSent: 0 })
    expect(alertsRepo.allEvents()[0]?.attempts).toBe(1)
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
  })

  it("stops retrying an event after three failed attempts", async () => {
    const { job, transport } = makeJob()
    transport.script(...Array.from({ length: 6 }, () => ({ status: 500 })))
    await job.run(NOW)
    await job.run(NOW)
    await job.run(NOW)
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 })
    expect(transport.calls).toHaveLength(6)
  })

  it("prunes dead tokens and stops retrying an event that has no devices left", async () => {
    const { job, transport, devices, alertsRepo } = makeJob()
    transport.script({ status: 410, reason: "Unregistered" })
    expect(await job.run(NOW)).toMatchObject({ status: "completed", alertsSent: 0, pruned: 1 })
    expect(devices.all()).toEqual([])
    expect(alertsRepo.allEvents().every((event) => event.sentAt !== null)).toBe(true)
  })
})
