import { parseLadderStatus, type LadderInput, type LadderStatus } from "../domain/ladder.js"
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
import type { Sql } from "./sql.js"

type LadderColumns = { buy_low: string | null; buy_high: string | null; fair: string | null; trim_value: string | null; sell: string | null }
type EvaluableRow = LadderColumns & { user_id: string; symbol: string; last_status: string | null; last_evaluated_price: string | null }
type PendingRow = LadderColumns & {
  id: string
  user_id: string
  symbol: string
  trading_date: string
  status: string
  previous_status: string | null
  price: string
  attempts: number
}
type JobRunRow = { status: string; claimed: boolean }

function toLadder(row: LadderColumns): LadderInput {
  return { buyLow: row.buy_low, buyHigh: row.buy_high, fair: row.fair, trim: row.trim_value, sell: row.sell }
}

function requireStatus(value: unknown): LadderStatus {
  const status = parseLadderStatus(value)
  if (status === null) throw new Error(`Unknown ladder status in alert_events: ${String(value)}`)
  return status
}

function toJobRunStatus(value: string): JobRunStatus {
  if (value === "running" || value === "completed" || value === "holiday") return value
  throw new Error(`Unknown alert_job_runs status: ${value}`)
}

export class NeonAlertRepository implements AlertRepository {
  private readonly sql: Sql

  constructor(sql: Sql) {
    this.sql = sql
  }

  async listEvaluableItems(): Promise<EvaluableItem[]> {
    const rows = await this.sql`
      SELECT user_id, symbol,
        trim_scale(buy_low)::text AS buy_low, trim_scale(buy_high)::text AS buy_high, trim_scale(fair)::text AS fair,
        trim_scale("trim")::text AS trim_value, trim_scale(sell)::text AS sell,
        last_status, trim_scale(last_evaluated_price)::text AS last_evaluated_price
      FROM watchlist_items
      WHERE deleted_at IS NULL
        AND (buy_low IS NOT NULL OR buy_high IS NOT NULL OR fair IS NOT NULL OR "trim" IS NOT NULL OR sell IS NOT NULL)
      ORDER BY symbol, user_id`
    return rows.map((raw) => {
      const row = raw as EvaluableRow
      return {
        userId: row.user_id,
        symbol: row.symbol,
        ladder: toLadder(row),
        lastStatus: parseLadderStatus(row.last_status),
        lastEvaluatedPrice: row.last_evaluated_price,
      }
    })
  }

  async insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]> {
    if (events.length === 0) return []
    const records = events.map((event) => ({
      id: event.id,
      user_id: event.userId,
      symbol: event.symbol,
      trading_date: event.tradingDate,
      status: event.status,
      previous_status: event.previousStatus,
      price: event.price,
    }))
    const rows = await this.sql`
      INSERT INTO alert_events (id, user_id, symbol, trading_date, status, previous_status, price, created_at)
      SELECT e.id, e.user_id, e.symbol, e.trading_date::date, e.status, e.previous_status, e.price::numeric, ${now.toISOString()}::timestamptz
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb)
        AS e(id text, user_id text, symbol text, trading_date text, status text, previous_status text, price text)
      ON CONFLICT (user_id, symbol, trading_date, status) DO NOTHING
      RETURNING id`
    return rows.map((row) => String(row.id))
  }

  async applyEvaluations(updates: EvaluationUpdate[], now: Date): Promise<void> {
    if (updates.length === 0) return
    const records = updates.map((update) => ({
      user_id: update.userId,
      symbol: update.symbol,
      prev_status: update.previousStatus,
      buy_low: update.ladder.buyLow ?? null,
      buy_high: update.ladder.buyHigh ?? null,
      fair: update.ladder.fair ?? null,
      trim_value: update.ladder.trim ?? null,
      sell: update.ladder.sell ?? null,
      status: update.status,
      price: update.price,
    }))
    await this.sql`
      UPDATE watchlist_items AS w
      SET last_status = u.status, last_status_at = ${now.toISOString()}::timestamptz, last_evaluated_price = u.price::numeric
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb) AS u(
        user_id text, symbol text, prev_status text, buy_low text, buy_high text, fair text, trim_value text, sell text, status text, price text)
      WHERE w.user_id = u.user_id AND w.symbol = u.symbol AND w.deleted_at IS NULL
        AND w.last_status IS NOT DISTINCT FROM u.prev_status
        AND w.buy_low IS NOT DISTINCT FROM u.buy_low::numeric AND w.buy_high IS NOT DISTINCT FROM u.buy_high::numeric
        AND w.fair IS NOT DISTINCT FROM u.fair::numeric AND w."trim" IS NOT DISTINCT FROM u.trim_value::numeric
        AND w.sell IS NOT DISTINCT FROM u.sell::numeric`
  }

  async listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]> {
    const rows = await this.sql`
      SELECT e.id, e.user_id, e.symbol, to_char(e.trading_date, 'YYYY-MM-DD') AS trading_date, e.status, e.previous_status,
        trim_scale(e.price)::text AS price, e.attempts,
        trim_scale(w.buy_low)::text AS buy_low, trim_scale(w.buy_high)::text AS buy_high, trim_scale(w.fair)::text AS fair,
        trim_scale(w."trim")::text AS trim_value, trim_scale(w.sell)::text AS sell
      FROM alert_events e
      JOIN watchlist_items w ON w.user_id = e.user_id AND w.symbol = e.symbol AND w.deleted_at IS NULL
      WHERE e.sent_at IS NULL AND e.trading_date = ${tradingDate}::date AND e.attempts < ${maxAttempts}
      ORDER BY e.created_at, e.id`
    return rows.map((raw) => {
      const row = raw as PendingRow
      return {
        id: row.id,
        userId: row.user_id,
        symbol: row.symbol,
        tradingDate: row.trading_date,
        status: requireStatus(row.status),
        previousStatus: parseLadderStatus(row.previous_status),
        price: row.price,
        attempts: Number(row.attempts),
        ladder: toLadder(row),
      }
    })
  }

  async markSent(eventId: string, now: Date): Promise<void> {
    await this.sql`UPDATE alert_events SET sent_at = ${now.toISOString()}::timestamptz WHERE id = ${eventId}`
  }

  async claimForSend(eventId: string, expectedAttempts: number): Promise<boolean> {
    const rows = await this.sql`
      UPDATE alert_events SET attempts = attempts + 1
      WHERE id = ${eventId} AND sent_at IS NULL AND attempts = ${expectedAttempts}
      RETURNING id`
    return rows.length > 0
  }

  async beginRun(tradingDate: string, now: Date): Promise<JobRun> {
    const staleSeconds = RUN_STALE_AFTER_MS / 1000
    const rows = await this.sql`
      WITH claimed AS (
        INSERT INTO alert_job_runs (trading_date, status, started_at)
        VALUES (${tradingDate}::date, 'running', ${now.toISOString()}::timestamptz)
        ON CONFLICT (trading_date) DO UPDATE SET started_at = EXCLUDED.started_at
        WHERE alert_job_runs.status = 'running'
          AND alert_job_runs.started_at <= EXCLUDED.started_at - make_interval(secs => ${staleSeconds})
        RETURNING status
      )
      SELECT status, true AS claimed FROM claimed
      UNION ALL
      SELECT status, false AS claimed FROM alert_job_runs
      WHERE trading_date = ${tradingDate}::date AND NOT EXISTS (SELECT 1 FROM claimed)`
    const row = rows[0] as JobRunRow | undefined
    if (row !== undefined) return { tradingDate, status: toJobRunStatus(row.status), claimed: row.claimed === true }
    // A truly concurrent delivery: the other insert committed after this statement's snapshot, so the UNION saw
    // neither row. Read again (new snapshot) and report it as someone else's run.
    const [existing] = await this.sql`SELECT status FROM alert_job_runs WHERE trading_date = ${tradingDate}::date`
    if (existing === undefined) throw new Error(`alert_job_runs row for ${tradingDate} was neither claimed nor found`)
    return { tradingDate, status: toJobRunStatus(String(existing.status)), claimed: false }
  }

  async finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats, now: Date): Promise<void> {
    await this.sql`
      UPDATE alert_job_runs
      SET status = ${status}, finished_at = ${now.toISOString()}::timestamptz, stats = ${JSON.stringify(stats)}::jsonb
      WHERE trading_date = ${tradingDate}::date`
  }
}
