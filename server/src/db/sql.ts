import { neon } from "@neondatabase/serverless"

export type Row = Record<string, unknown>

/**
 * The only database surface repositories see. Rules (overview §8.1): plain value interpolation only,
 * no `sql.unsafe`, no composed fragments, every write a single statement. Pass JSON as
 * `${JSON.stringify(value)}::jsonb` so Neon HTTP and PGlite serialize identically.
 */
export type Sql = (strings: TemplateStringsArray, ...values: unknown[]) => Promise<Row[]>

export function neonSql(databaseUrl: string): Sql {
  const query = neon(databaseUrl)
  return async (strings, ...values) => (await query(strings, ...values)) as Row[]
}

export function toParameterized(strings: TemplateStringsArray, values: unknown[]): { text: string; values: unknown[] } {
  let text = strings[0] ?? ""
  for (let i = 1; i < strings.length; i += 1) {
    text += `$${i}${strings[i] ?? ""}`
  }
  return { text, values }
}

/** Structural type so `src/` never imports the PGlite dev dependency. */
export interface QueryableDb {
  query<T>(text: string, params?: unknown[]): Promise<{ rows: T[] }>
}

export function pgliteSql(db: QueryableDb): Sql {
  return async (strings, ...values) => {
    const { text, values: params } = toParameterized(strings, values)
    return (await db.query<Row>(text, params)).rows
  }
}
