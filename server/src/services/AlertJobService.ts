import { randomUUID } from "node:crypto"
import type { AlertSender } from "../apns/ApnsSender.js"
import { buildPayload } from "../apns/payload.js"
import type { AlertRepository, EvaluationUpdate, NewAlertEvent } from "../db/AlertRepository.js"
import type { DeviceToken, DeviceTokenRepository } from "../db/DeviceTokenRepository.js"
import { classifyStatus, shouldAlert, temperature } from "../domain/ladder.js"
import { easternDate, isWeekend } from "../domain/tradingDate.js"
import { systemClock, type Clock } from "../lib/clock.js"
import { mapLimit } from "../lib/concurrency.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import { SYMBOL_REGEX } from "../schemas/common.js"
import type { CloseResolver } from "./DailyCloseResolver.js"

export type AlertJobStatus = "completed" | "holiday" | "skipped" | "resent"

export type AlertJobResult = {
  tradingDate: string
  status: AlertJobStatus
  evaluated: number
  transitions: number
  alertsCreated: number
  alertsSent: number
  pruned: number
}

/** What the cron route needs; `Container.alertJob` is typed with this so tests can stub it. */
export interface AlertJob {
  run(now: Date, log?: LogSink): Promise<AlertJobResult>
}

export type AlertJobDependencies = {
  alerts: AlertRepository
  devices: Pick<DeviceTokenRepository, "listByUsers">
  closes: CloseResolver
  sender: AlertSender
  newId?: () => string
  /** Measures the delivery budget; defaults to the system clock. */
  clock?: Clock
  /** Events delivered in parallel; default 5. */
  deliveryConcurrency?: number
  /** No new send starts this long after the run began; the rest wait for the catch-up run. Default 45 s. */
  deliveryBudgetMs?: number
}

export const MAX_SEND_ATTEMPTS = 3
/** A close more than 50% away from the last evaluated price is treated as a split (overview §8.6 step 7). */
export const SPLIT_GUARD_RATIO = 0.5

/** Vercel gives the function 60 s (README); stop starting sends at 45 s so in-flight ones (3 s timeout, 1 s retry) finish in time. */
export const DEFAULT_DELIVERY_BUDGET_MS = 45_000
export const DEFAULT_DELIVERY_CONCURRENCY = 5

type Delivery = { sent: number; pruned: number; skipped: number; failed: number; deferred: number; contended: number }

/** Overview §8.6. Every step is safe to rerun on the same trading day, and only one caller runs a day at a time. */
export class AlertJobService implements AlertJob {
  private readonly deps: AlertJobDependencies
  private readonly newId: () => string
  private readonly clock: Clock
  private readonly concurrency: number
  private readonly budgetMs: number

  constructor(deps: AlertJobDependencies) {
    this.deps = deps
    this.newId = deps.newId ?? (() => randomUUID())
    this.clock = deps.clock ?? systemClock
    this.concurrency = deps.deliveryConcurrency ?? DEFAULT_DELIVERY_CONCURRENCY
    this.budgetMs = deps.deliveryBudgetMs ?? DEFAULT_DELIVERY_BUDGET_MS
  }

  async run(now: Date, log: LogSink = silentLog): Promise<AlertJobResult> {
    const startedAt = this.clock.now().getTime()
    try {
      return await this.execute(now, log, startedAt)
    } finally {
      // A warm Vercel instance can be frozen between invocations; a kept-open HTTP/2 session would be dead on thaw.
      await this.deps.sender.close().catch((error: unknown) => log.warn({ error: error instanceof Error ? error.message : String(error) }, "alerts.sender_close_failed"))
    }
  }

  private async execute(now: Date, log: LogSink, startedAt: number): Promise<AlertJobResult> {
    const tradingDate = easternDate(now)
    const idle: AlertJobResult = { tradingDate, status: "skipped", evaluated: 0, transitions: 0, alertsCreated: 0, alertsSent: 0, pruned: 0 }
    if (isWeekend(tradingDate)) return idle

    const run = await this.deps.alerts.beginRun(tradingDate, now)
    if (!run.claimed) {
      if (run.status === "holiday") return { ...idle, status: "holiday" }
      if (run.status === "completed") {
        const delivery = await this.deliverPending(tradingDate, now, log, startedAt)
        return { ...idle, status: "resent", alertsSent: delivery.sent, pruned: delivery.pruned }
      }
      log.info({ tradingDate }, "alerts.in_progress")
      return idle
    }

    // Only US market symbols (overview §8.4): synced HK/OTC items would otherwise eat the 25-call Finnhub fallback.
    const listed = await this.deps.alerts.listEvaluableItems()
    const items = listed.filter((item) => SYMBOL_REGEX.test(item.symbol))
    const symbols = [...new Set(items.map((item) => item.symbol))]
    const resolution = await this.deps.closes.resolve(tradingDate, symbols, log)
    if (resolution.kind === "holiday") {
      await this.deps.alerts.finishRun(tradingDate, "holiday", { items: items.length }, now)
      log.info({ tradingDate }, "alerts.holiday")
      return { ...idle, status: "holiday" }
    }

    const updates: EvaluationUpdate[] = []
    const events: NewAlertEvent[] = []
    let transitions = 0
    let splitSkips = 0
    for (const item of items) {
      const close = resolution.closes.get(item.symbol)
      if (close === undefined) continue
      const next = classifyStatus(item.ladder, Number(close))
      if (next === "NO_ANCHORS") continue
      updates.push({ userId: item.userId, symbol: item.symbol, previousStatus: item.lastStatus, ladder: item.ladder, status: next, price: close })
      if (item.lastStatus === null || item.lastStatus === next) continue
      transitions += 1
      if (!shouldAlert(item.lastStatus, next)) continue
      if (looksLikeSplit(item.lastEvaluatedPrice, close)) {
        splitSkips += 1
        log.warn({ tradingDate, symbol: item.symbol, previousPrice: item.lastEvaluatedPrice, close }, "alerts.split_guard")
        continue
      }
      events.push({ id: this.newId(), userId: item.userId, symbol: item.symbol, tradingDate, status: next, previousStatus: item.lastStatus, price: close })
    }

    const created = await this.deps.alerts.insertEvents(events, now)
    await this.deps.alerts.applyEvaluations(updates, now)
    const delivery = await this.deliverPending(tradingDate, now, log, startedAt)

    const result: AlertJobResult = {
      tradingDate,
      status: "completed",
      evaluated: updates.length,
      transitions,
      alertsCreated: created.length,
      alertsSent: delivery.sent,
      pruned: delivery.pruned,
    }
    await this.deps.alerts.finishRun(
      tradingDate,
      "completed",
      {
        evaluated: result.evaluated,
        transitions,
        alertsCreated: result.alertsCreated,
        alertsSent: delivery.sent,
        pruned: delivery.pruned,
        skippedNoDevice: delivery.skipped,
        failed: delivery.failed,
        deferred: delivery.deferred,
        contended: delivery.contended,
        splitSkips,
        grouped: resolution.groupedCount,
        fallback: resolution.fallbackCount,
        missing: resolution.missing.length,
        nonMarketSymbols: listed.length - items.length,
      },
      now,
    )
    log.info({ ...result, splitSkips, missing: resolution.missing.length }, "alerts.completed")
    return result
  }

  /**
   * Overview §8.6 step 10, with bounded concurrency and a deadline: once the budget is spent no new send starts, and the events
   * left unclaimed stay pending for the catch-up cron (same day, `resent` path). Each event is claimed atomically first, so
   * overlapping runs never deliver one twice.
   */
  private async deliverPending(tradingDate: string, now: Date, log: LogSink, startedAt: number): Promise<Delivery> {
    const delivery: Delivery = { sent: 0, pruned: 0, skipped: 0, failed: 0, deferred: 0, contended: 0 }
    const pending = await this.deps.alerts.listPendingEvents(tradingDate, MAX_SEND_ATTEMPTS)
    if (pending.length === 0) return delivery

    const devicesByUser = groupByUser(await this.deps.devices.listByUsers([...new Set(pending.map((event) => event.userId))]))
    const prunedTokens = new Set<string>()
    await mapLimit(pending, this.concurrency, async (event) => {
      if (this.clock.now().getTime() - startedAt >= this.budgetMs) {
        delivery.deferred += 1
        return
      }
      if (!(await this.deps.alerts.claimForSend(event.id, event.attempts))) {
        delivery.contended += 1
        return
      }

      const targets = (devicesByUser.get(event.userId) ?? []).filter((device) => !prunedTokens.has(device.token))
      if (targets.length === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
        return
      }

      const payload = buildPayload({
        symbol: event.symbol,
        status: event.status,
        price: event.price,
        ladder: event.ladder,
        temperature: temperature(event.ladder, Number(event.price)),
        tradingDate,
      })
      let delivered = false
      let remaining = targets.length
      for (const device of targets) {
        const outcome = await this.deps.sender.send(device, payload, log)
        if (outcome === "pruned") {
          // Events of the same user run in parallel and may both see the dead token: count it once.
          if (!prunedTokens.has(device.token)) delivery.pruned += 1
          prunedTokens.add(device.token)
          remaining -= 1
        } else if (outcome === "sent") {
          delivered = true
        }
      }

      if (delivered) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.sent += 1
      } else if (remaining === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
      } else {
        // The claim already counted this attempt.
        delivery.failed += 1
      }
    })
    if (delivery.deferred > 0) log.warn({ tradingDate, deferred: delivery.deferred }, "alerts.delivery_deadline")
    return delivery
  }
}

function looksLikeSplit(previousPrice: string | null, close: string): boolean {
  if (previousPrice === null) return false
  const previous = Number(previousPrice)
  if (!Number.isFinite(previous) || previous <= 0) return false
  return Math.abs(Number(close) / previous - 1) > SPLIT_GUARD_RATIO
}

function groupByUser(devices: DeviceToken[]): Map<string, DeviceToken[]> {
  const byUser = new Map<string, DeviceToken[]>()
  for (const device of devices) byUser.set(device.userId, [...(byUser.get(device.userId) ?? []), device])
  return byUser
}
