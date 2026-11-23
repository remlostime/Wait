import type { LadderInput } from "../domain/ladder.js"
import {
  RUN_STALE_AFTER_MS,
  type AlertRepository,
  type EvaluableItem,
  type EvaluationUpdate,
  type JobRun,
  type JobRunStatus,
  type JobStats,
  type NewAlertEvent,
  type PendingAlertEvent,
} from "./AlertRepository.js"

type StoredItem = EvaluableItem & { deleted: boolean }
export type StoredAlertEvent = NewAlertEvent & { createdAt: Date; sentAt: Date | null; attempts: number }

const EMPTY_LADDER: LadderInput = { buyLow: null, buyHigh: null, fair: null, trim: null, sell: null }

function key(userId: string, symbol: string): string {
  return `${userId}\u0000${symbol}`
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

/** Same anchor, compared as numbers like the SQL `numeric` columns ("160" equals "160.000"; null only equals null). */
function sameAnchors(a: LadderInput, b: LadderInput): boolean {
  const same = (x: string | null | undefined, y: string | null | undefined): boolean =>
    x === null || x === undefined || y === null || y === undefined ? (x ?? null) === (y ?? null) : Number(x) === Number(y)
  return same(a.buyLow, b.buyLow) && same(a.buyHigh, b.buyHigh) && same(a.fair, b.fair) && same(a.trim, b.trim) && same(a.sell, b.sell)
}

function hasAnchor(ladder: LadderInput): boolean {
  return [ladder.buyLow, ladder.buyHigh, ladder.fair, ladder.trim, ladder.sell].some((value) => value !== null && value !== undefined)
}

export class MockAlertRepository implements AlertRepository {
  private readonly items = new Map<string, StoredItem>()
  private events: StoredAlertEvent[] = []
  private readonly runs = new Map<string, { status: JobRunStatus; startedAt: Date; stats: JobStats }>()

  seedItems(items: Array<EvaluableItem & { deleted?: boolean }>): void {
    for (const item of items) this.items.set(key(item.userId, item.symbol), { ...item, ladder: { ...item.ladder }, deleted: item.deleted ?? false })
  }

  item(userId: string, symbol: string): EvaluableItem | undefined {
    const stored = this.items.get(key(userId, symbol))
    if (stored === undefined) return undefined
    const { deleted: _deleted, ...item } = stored
    return { ...item, ladder: { ...item.ladder } }
  }

  allEvents(): StoredAlertEvent[] {
    return this.events.map((event) => ({ ...event }))
  }

  runStatus(tradingDate: string): JobRunStatus | undefined {
    return this.runs.get(tradingDate)?.status
  }

  clear(): void {
    this.items.clear()
    this.events = []
    this.runs.clear()
  }

  async listEvaluableItems(): Promise<EvaluableItem[]> {
    return [...this.items.values()]
      .filter((item) => !item.deleted && hasAnchor(item.ladder))
      .sort((a, b) => compare(a.symbol, b.symbol) || compare(a.userId, b.userId))
      .map(({ deleted: _deleted, ...item }) => ({ ...item, ladder: { ...item.ladder } }))
  }

  async insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]> {
    const inserted: string[] = []
    for (const event of events) {
      const duplicate = this.events.some(
        (existing) =>
          existing.userId === event.userId &&
          existing.symbol === event.symbol &&
          existing.tradingDate === event.tradingDate &&
          existing.status === event.status,
      )
      if (duplicate) continue
      this.events.push({ ...event, createdAt: now, sentAt: null, attempts: 0 })
      inserted.push(event.id)
    }
    return inserted
  }

  async applyEvaluations(updates: EvaluationUpdate[]): Promise<void> {
    for (const update of updates) {
      const stored = this.items.get(key(update.userId, update.symbol))
      if (stored === undefined || stored.deleted || stored.lastStatus !== update.previousStatus || !sameAnchors(stored.ladder, update.ladder)) continue
      this.items.set(key(update.userId, update.symbol), { ...stored, lastStatus: update.status, lastEvaluatedPrice: update.price })
    }
  }

  /** Test hook: simulates plan 05's sync resetting `last_status` after an anchor change. */
  resetStatus(userId: string, symbol: string): void {
    const stored = this.items.get(key(userId, symbol))
    if (stored) this.items.set(key(userId, symbol), { ...stored, lastStatus: null })
  }

  async listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]> {
    return this.events
      .filter((event) => {
        const item = this.items.get(key(event.userId, event.symbol))
        return event.sentAt === null && event.tradingDate === tradingDate && event.attempts < maxAttempts && item !== undefined && !item.deleted
      })
      .map(({ createdAt: _createdAt, sentAt: _sentAt, ...event }) => ({
        ...event,
        ladder: { ...(this.items.get(key(event.userId, event.symbol))?.ladder ?? EMPTY_LADDER) },
      }))
  }

  async markSent(eventId: string, now: Date): Promise<void> {
    this.events = this.events.map((event) => (event.id === eventId ? { ...event, sentAt: now } : event))
  }

  async claimForSend(eventId: string, expectedAttempts: number): Promise<boolean> {
    const index = this.events.findIndex((event) => event.id === eventId && event.sentAt === null && event.attempts === expectedAttempts)
    if (index < 0) return false
    this.events = this.events.map((event, i) => (i === index ? { ...event, attempts: event.attempts + 1 } : event))
    return true
  }

  async beginRun(tradingDate: string, now: Date): Promise<JobRun> {
    const existing = this.runs.get(tradingDate)
    const stale = existing?.status === "running" && now.getTime() - existing.startedAt.getTime() >= RUN_STALE_AFTER_MS
    if (existing === undefined || stale) {
      this.runs.set(tradingDate, { status: "running", startedAt: now, stats: {} })
      return { tradingDate, status: "running", claimed: true }
    }
    return { tradingDate, status: existing.status, claimed: false }
  }

  async finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats): Promise<void> {
    const existing = this.runs.get(tradingDate)
    this.runs.set(tradingDate, { status, startedAt: existing?.startedAt ?? new Date(0), stats })
  }
}
