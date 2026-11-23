import { describe, expect, it } from "vitest"
import type { AlertSender, SendOutcome } from "../../src/apns/ApnsSender.js"
import { MockAlertRepository } from "../../src/db/MockAlertRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { fixedClock } from "../../src/lib/clock.js"
import { AlertJobService } from "../../src/services/AlertJobService.js"
import { FakeCloseResolver, SCENARIO_RESOLUTION } from "../support/alertScenario.js"

const NOW = new Date("2026-11-20T22:00:00.000Z") // Friday, 5pm ET
const TRADING_DATE = "2026-11-20"

class StubSender implements AlertSender {
  readonly sentTo: string[] = []
  closeCalls = 0
  inFlight = 0
  maxInFlight = 0
  outcome: SendOutcome = "sent"
  /** Runs inside each send; lets a test advance the clock or hold the send open. */
  onSend: () => Promise<void> = async () => {}

  async send(device: { token: string }): Promise<SendOutcome> {
    this.inFlight += 1
    this.maxInFlight = Math.max(this.maxInFlight, this.inFlight)
    try {
      await this.onSend()
      this.sentTo.push(device.token)
      return this.outcome
    } finally {
      this.inFlight -= 1
    }
  }

  async close(): Promise<void> {
    this.closeCalls += 1
  }
}

/** A day that already completed with `users` unsent events, so `run` takes the `resent` path straight into delivery. */
async function pendingDay(users: number, options: { deliveryConcurrency?: number; deliveryBudgetMs?: number } = {}) {
  const alerts = new MockAlertRepository()
  const devices = new MockDeviceTokenRepository()
  const clock = fixedClock(NOW)
  const sender = new StubSender()
  const ids = Array.from({ length: users }, (_, index) => index + 1)
  alerts.seedItems(ids.map((n) => ({ userId: `user-${n}`, symbol: "AAPL", ladder: { buyLow: null, buyHigh: "175", fair: null, trim: null, sell: null }, lastStatus: "BUY_ZONE" as const, lastEvaluatedPrice: "172" })))
  devices.seed(ids.map((n) => ({ token: `token-${n}`, userId: `user-${n}`, environment: "sandbox" as const, bundleId: "com.chenkai.wait", createdAt: NOW, updatedAt: NOW, lastSuccessAt: null })))
  await alerts.insertEvents(
    ids.map((n) => ({ id: `event-${n}`, userId: `user-${n}`, symbol: "AAPL", tradingDate: TRADING_DATE, status: "BUY_ZONE" as const, previousStatus: "WATCH" as const, price: "172" })),
    NOW,
  )
  await alerts.beginRun(TRADING_DATE, NOW)
  await alerts.finishRun(TRADING_DATE, "completed", {})
  const job = new AlertJobService({ alerts, devices, closes: new FakeCloseResolver(SCENARIO_RESOLUTION), sender, clock, ...options })
  return { job, alerts, sender, clock }
}

const yieldToEventLoop = () => new Promise<void>((resolve) => setImmediate(resolve))

describe("AlertJobService delivery", () => {
  it("sends with bounded concurrency (5 in flight at most)", async () => {
    const { job, sender } = await pendingDay(12)
    sender.onSend = yieldToEventLoop
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 12 })
    expect(sender.maxInFlight).toBe(5)
  })

  it("stops starting new sends once the delivery deadline passes and leaves the rest pending for the catch-up run", async () => {
    const { job, alerts, sender, clock } = await pendingDay(3, { deliveryConcurrency: 1, deliveryBudgetMs: 45_000 })
    sender.onSend = async () => clock.advance(30_000) // each send "takes" 30 s: starts at 0 s and 30 s, the third would start at 60 s

    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 2 })
    expect(alerts.allEvents().map((event) => [event.id, event.sentAt !== null, event.attempts])).toEqual([
      ["event-1", true, 1],
      ["event-2", true, 1],
      ["event-3", false, 0],
    ])

    // The catch-up cron: the day is already completed, so it only delivers what is still pending.
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
    expect(alerts.allEvents().every((event) => event.sentAt !== null)).toBe(true)
    expect(sender.sentTo).toEqual(["token-1", "token-2", "token-3"])
  })

  it("lets a catch-up run deliver events whose earlier attempts failed, until they hit the attempt limit", async () => {
    const { job, alerts, sender } = await pendingDay(1)
    sender.outcome = "failed"
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 })
    expect(alerts.allEvents()[0]?.attempts).toBe(1)
    sender.outcome = "sent"
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
  })

  it("does not push for an item the user deleted after the event was created", async () => {
    const { job, alerts, sender } = await pendingDay(2)
    alerts.seedItems([{ userId: "user-1", symbol: "AAPL", ladder: { buyLow: null, buyHigh: "175", fair: null, trim: null, sell: null }, lastStatus: "BUY_ZONE", lastEvaluatedPrice: "172", deleted: true }])
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
    expect(sender.sentTo).toEqual(["token-2"])
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 }) // and it is not retried forever
  })

  it("closes the sender's connections after every run, including one that throws", async () => {
    const { job, alerts, sender } = await pendingDay(1)
    await job.run(NOW)
    expect(sender.closeCalls).toBe(1)

    alerts.listPendingEvents = async () => {
      throw new Error("db down")
    }
    await expect(job.run(NOW)).rejects.toThrow("db down")
    expect(sender.closeCalls).toBe(2)
  })

  it("does not fail the run when closing the connections fails", async () => {
    const { job, sender } = await pendingDay(1)
    sender.close = async () => {
      throw new Error("socket already gone")
    }
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
  })

  it("never delivers the same event twice when two resent callers overlap", async () => {
    const { job, sender } = await pendingDay(3)
    sender.onSend = yieldToEventLoop

    const results = await Promise.all([job.run(NOW), job.run(NOW)])

    expect(sender.sentTo.sort()).toEqual(["token-1", "token-2", "token-3"])
    expect(results.reduce((total, result) => total + result.alertsSent, 0)).toBe(3)
  })
})
