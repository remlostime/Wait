import type { LadderInput, LadderStatus } from "../domain/ladder.js"

/** A live watchlist item with at least one anchor, plus the server-owned evaluation columns. */
export type EvaluableItem = {
  userId: string
  symbol: string
  ladder: LadderInput
  lastStatus: LadderStatus | null
  lastEvaluatedPrice: string | null
}

/** `previousStatus` is the `last_status` the job read; the update applies only if the row still has it. */
export type EvaluationUpdate = { userId: string; symbol: string; previousStatus: LadderStatus | null; status: LadderStatus; price: string }

export type NewAlertEvent = {
  id: string
  userId: string
  symbol: string
  tradingDate: string
  status: LadderStatus
  previousStatus: LadderStatus | null
  price: string
}

export type PendingAlertEvent = NewAlertEvent & { attempts: number; ladder: LadderInput }

export type JobRunStatus = "running" | "completed" | "holiday"
/** `claimed` = this caller owns the day's run (new row, or a stale `running` row taken over). */
export type JobRun = { tradingDate: string; status: JobRunStatus; claimed: boolean }
export type JobStats = Record<string, number>

/** A `running` row older than this is treated as a crashed run and may be taken over. */
export const RUN_STALE_AFTER_MS = 10 * 60 * 1000

export interface AlertRepository {
  listEvaluableItems(): Promise<EvaluableItem[]>
  /** Inserts with ON CONFLICT DO NOTHING; returns the ids that were actually inserted. */
  insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]>
  /** Sets last_status / last_status_at / last_evaluated_price where last_status is still `previousStatus`. Never touches version. */
  applyEvaluations(updates: EvaluationUpdate[], now: Date): Promise<void>
  listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]>
  markSent(eventId: string, now: Date): Promise<void>
  incrementAttempts(eventId: string): Promise<void>
  /** Atomically claims the day: inserts the run row, or takes over a `running` row older than RUN_STALE_AFTER_MS. */
  beginRun(tradingDate: string, now: Date): Promise<JobRun>
  finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats, now: Date): Promise<void>
}
