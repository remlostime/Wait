import type { Row, Sql } from "./sql.js"
import type { WatchlistRepository } from "./WatchlistRepository.js"
import {
  normalizeDecimal,
  normalizeLadder,
  type ChecklistEntry,
  type LadderHistoryEntry,
  type SyncCursor,
  type WatchlistChange,
  type WatchlistRow,
} from "./watchlistTypes.js"

type IncomingRecord = {
  symbol: string
  name: string
  buy_low: string | null
  buy_high: string | null
  fair: string | null
  trim: string | null
  sell: string | null
  memo: string
  is_favorite: boolean
  sort_index: number
  checklist: ChecklistEntry[]
  ladder_history: LadderHistoryEntry[]
  client_updated_at: string
  deleted: boolean
}

function toIncomingRecord(change: WatchlistChange): IncomingRecord {
  return {
    symbol: change.symbol,
    name: change.name,
    buy_low: change.ladder.buyLow,
    buy_high: change.ladder.buyHigh,
    fair: change.ladder.fair,
    trim: change.ladder.trim,
    sell: change.ladder.sell,
    memo: change.memo,
    is_favorite: change.isFavorite,
    sort_index: change.sortIndex,
    checklist: change.checklist,
    ladder_history: change.ladderHistory,
    client_updated_at: change.clientUpdatedAt.toISOString(),
    deleted: change.deleted,
  }
}

function jsonValue<T>(value: unknown): T {
  return (typeof value === "string" ? JSON.parse(value) : value) as T
}

function dateValue(value: unknown): Date {
  return value instanceof Date ? value : new Date(String(value))
}

function mapRow(row: Row): WatchlistRow {
  return {
    symbol: String(row.symbol),
    name: String(row.name),
    ladder: normalizeLadder({
      buyLow: row.buy_low as string | null,
      buyHigh: row.buy_high as string | null,
      fair: row.fair as string | null,
      trim: row.trim as string | null,
      sell: row.sell as string | null,
    }),
    memo: String(row.memo),
    isFavorite: Boolean(row.is_favorite),
    sortIndex: Number(row.sort_index),
    checklist: jsonValue<ChecklistEntry[]>(row.checklist),
    ladderHistory: jsonValue<LadderHistoryEntry[]>(row.ladder_history),
    clientUpdatedAt: dateValue(row.client_updated_at),
    deleted: row.deleted_at !== null && row.deleted_at !== undefined,
    version: Number(row.version),
    lastStatus: row.last_status === null || row.last_status === undefined ? null : String(row.last_status),
    lastEvaluatedPrice: normalizeDecimal(row.last_evaluated_price),
  }
}

export class NeonWatchlistRepository implements WatchlistRepository {
  constructor(private readonly sql: Sql) {}

  async push(userId: string, changes: WatchlistChange[], now: Date): Promise<string[]> {
    if (changes.length === 0) return []
    const incoming = JSON.stringify(changes.map(toIncomingRecord))
    const nowIso = now.toISOString()
    // One statement: bumping users.watchlist_version takes the user's row lock, so pushes from one user
    // serialize, and their versions become visible in commit order (overview §8.5).
    const rows = await this.sql`
      WITH bump AS (
        UPDATE users SET watchlist_version = watchlist_version + 1, updated_at = ${nowIso}::timestamptz
        WHERE id = ${userId}
        RETURNING watchlist_version AS v
      ),
      incoming AS (
        SELECT * FROM jsonb_to_recordset(${incoming}::jsonb) AS x(
          symbol text, name text, buy_low numeric, buy_high numeric, fair numeric, "trim" numeric, sell numeric,
          memo text, is_favorite boolean, sort_index int, checklist jsonb, ladder_history jsonb,
          client_updated_at timestamptz, deleted boolean)
      )
      INSERT INTO watchlist_items AS w (
        user_id, symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index,
        checklist, ladder_history, client_updated_at, version, deleted_at, server_updated_at)
      SELECT ${userId}::text, i.symbol, i.name, i.buy_low, i.buy_high, i.fair, i."trim", i.sell, i.memo, i.is_favorite,
        i.sort_index, i.checklist, i.ladder_history, i.client_updated_at, bump.v,
        CASE WHEN i.deleted THEN ${nowIso}::timestamptz END, ${nowIso}::timestamptz
      FROM incoming i CROSS JOIN bump
      ON CONFLICT (user_id, symbol) DO UPDATE SET
        name = EXCLUDED.name,
        buy_low = EXCLUDED.buy_low, buy_high = EXCLUDED.buy_high, fair = EXCLUDED.fair,
        "trim" = EXCLUDED."trim", sell = EXCLUDED.sell,
        memo = EXCLUDED.memo, is_favorite = EXCLUDED.is_favorite, sort_index = EXCLUDED.sort_index,
        checklist = EXCLUDED.checklist, ladder_history = EXCLUDED.ladder_history,
        client_updated_at = EXCLUDED.client_updated_at, version = EXCLUDED.version,
        deleted_at = EXCLUDED.deleted_at, server_updated_at = EXCLUDED.server_updated_at,
        last_status = CASE
          WHEN (w.buy_low, w.buy_high, w.fair, w."trim", w.sell)
               IS DISTINCT FROM (EXCLUDED.buy_low, EXCLUDED.buy_high, EXCLUDED.fair, EXCLUDED."trim", EXCLUDED.sell)
          THEN NULL ELSE w.last_status END,
        last_status_at = CASE
          WHEN (w.buy_low, w.buy_high, w.fair, w."trim", w.sell)
               IS DISTINCT FROM (EXCLUDED.buy_low, EXCLUDED.buy_high, EXCLUDED.fair, EXCLUDED."trim", EXCLUDED.sell)
          THEN NULL ELSE w.last_status_at END
      WHERE w.client_updated_at < EXCLUDED.client_updated_at
      RETURNING w.symbol`
    return rows.map((row) => String(row.symbol)).sort()
  }

  async pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]> {
    const rows = await this.sql`
      SELECT symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index, checklist,
        ladder_history, client_updated_at, version, deleted_at, last_status, last_evaluated_price
      FROM watchlist_items
      WHERE user_id = ${userId} AND (version, symbol) > (${after.version}::bigint, ${after.symbol}::text)
      ORDER BY version, symbol
      LIMIT ${limit}`
    return rows.map(mapRow)
  }

  async findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]> {
    if (symbols.length === 0) return []
    const rows = await this.sql`
      SELECT symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index, checklist,
        ladder_history, client_updated_at, version, deleted_at, last_status, last_evaluated_price
      FROM watchlist_items
      WHERE user_id = ${userId} AND symbol IN (SELECT jsonb_array_elements_text(${JSON.stringify(symbols)}::jsonb))
      ORDER BY symbol`
    return rows.map(mapRow)
  }
}
