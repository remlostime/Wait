import { randomUUID } from "node:crypto"
import type { AlertSender } from "../apns/ApnsSender.js"
import { buildPayload } from "../apns/payload.js"
import type { AlertRepository, EvaluationUpdate, NewAlertEvent } from "../db/AlertRepository.js"
import type { DeviceToken, DeviceTokenRepository } from "../db/DeviceTokenRepository.js"
import { classifyStatus, shouldAlert, temperature } from "../domain/ladder.js"
import { easternDate, isWeekend } from "../domain/tradingDate.js"
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
}

export const MAX_SEND_ATTEMPTS = 3
/** A close more than 50% away from the last evaluated price is treated as a split (overview §8.6 step 7). */
export const SPLIT_GUARD_RATIO = 0.5

type Delivery = { sent: number; pruned: number; skipped: number; failed: number }

/** Overview §8.6. Every step is safe to rerun on the same trading day, and only one caller runs a day at a time. */
export class AlertJobService implements AlertJob {
  private readonly deps: AlertJobDependencies
  private readonly newId: () => string

  constructor(deps: AlertJobDependencies) {
    this.deps = deps
    this.newId = deps.newId ?? (() => randomUUID())
  }

  async run(now: Date, log: LogSink = silentLog): Promise<AlertJobResult> {
    const tradingDate = easternDate(now)
    const idle: AlertJobResult = { tradingDate, status: "skipped", evaluated: 0, transitions: 0, alertsCreated: 0, alertsSent: 0, pruned: 0 }
    if (isWeekend(tradingDate)) return idle

    const run = await this.deps.alerts.beginRun(tradingDate, now)
    if (!run.claimed) {
      if (run.status === "holiday") return { ...idle, status: "holiday" }
      if (run.status === "completed") {
        const delivery = await this.deliverPending(tradingDate, now, log)
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
      updates.push({ userId: item.userId, symbol: item.symbol, previousStatus: item.lastStatus, status: next, price: close })
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
    const delivery = await this.deliverPending(tradingDate, now, log)

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

  /** Overview §8.6 step 10. */
  private async deliverPending(tradingDate: string, now: Date, log: LogSink): Promise<Delivery> {
    const delivery: Delivery = { sent: 0, pruned: 0, skipped: 0, failed: 0 }
    const pending = await this.deps.alerts.listPendingEvents(tradingDate, MAX_SEND_ATTEMPTS)
    if (pending.length === 0) return delivery

    const devicesByUser = groupByUser(await this.deps.devices.listByUsers([...new Set(pending.map((event) => event.userId))]))
    for (const event of pending) {
      const targets = devicesByUser.get(event.userId) ?? []
      if (targets.length === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
        continue
      }

      const payload = buildPayload({
        symbol: event.symbol,
        status: event.status,
        price: event.price,
        ladder: event.ladder,
        temperature: temperature(event.ladder, Number(event.price)),
        tradingDate,
      })
      const remaining: DeviceToken[] = []
      let delivered = false
      for (const device of targets) {
        const outcome = await this.deps.sender.send(device, payload, log)
        if (outcome === "pruned") {
          delivery.pruned += 1
          continue
        }
        remaining.push(device)
        if (outcome === "sent") delivered = true
      }
      devicesByUser.set(event.userId, remaining)

      if (delivered) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.sent += 1
      } else if (remaining.length === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
      } else {
        await this.deps.alerts.incrementAttempts(event.id)
        delivery.failed += 1
      }
    }
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
