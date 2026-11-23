import type { Sql } from "../../src/db/sql.js"

export type ItemFixture = {
  userId: string
  symbol: string
  buyLow?: string
  buyHigh?: string
  fair?: string
  trim?: string
  sell?: string
  lastStatus?: string
  lastEvaluatedPrice?: string
  deleted?: boolean
  version?: number
}

export async function insertUser(sql: Sql, id: string): Promise<void> {
  await sql`INSERT INTO users (id, anonymous_id) VALUES (${id}, ${`anon-${id}`}) ON CONFLICT (id) DO NOTHING`
}

export async function insertItem(sql: Sql, item: ItemFixture): Promise<void> {
  await insertUser(sql, item.userId)
  await sql`
    INSERT INTO watchlist_items (user_id, symbol, name, buy_low, buy_high, fair, "trim", sell,
      client_updated_at, version, deleted_at, last_status, last_evaluated_price)
    VALUES (${item.userId}, ${item.symbol}, ${item.symbol},
      ${item.buyLow ?? null}::numeric, ${item.buyHigh ?? null}::numeric, ${item.fair ?? null}::numeric,
      ${item.trim ?? null}::numeric, ${item.sell ?? null}::numeric,
      '2026-11-01T00:00:00.000Z'::timestamptz, ${item.version ?? 1},
      ${item.deleted === true ? "2026-11-02T00:00:00.000Z" : null}::timestamptz,
      ${item.lastStatus ?? null}, ${item.lastEvaluatedPrice ?? null}::numeric)`
}
