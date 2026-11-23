import path from "node:path"
import { PGlite } from "@electric-sql/pglite"
import { Pool } from "@neondatabase/serverless"
import { applyMigrations, poolExecutor, readMigrationFiles, type MigrationExecutor } from "../../src/db/migrations.js"
import { neonSql, pgliteSql, type Row, type Sql } from "../../src/db/sql.js"

export const MIGRATIONS_DIR = path.resolve(import.meta.dirname, "../../migrations")

/** Raw handle for assertions: the PGlite instance, or a Neon pool adapter under `npm run test:neon`. */
export interface TestDatabase {
  query<T = Row>(text: string, params?: unknown[]): Promise<{ rows: T[] }>
  exec(text: string): Promise<unknown>
  close(): Promise<void>
}

export interface TestDb {
  db: TestDatabase
  sql: Sql
  close(): Promise<void>
}

export function pgliteExecutor(db: PGlite): MigrationExecutor {
  return {
    query: async (text, params) => (await db.query<Row>(text, params ?? [])).rows,
    exec: async (text) => {
      await db.exec(text)
    },
    transaction: (fn) =>
      db.transaction((tx) =>
        fn({
          query: async (text, params) => (await tx.query<Row>(text, params ?? [])).rows,
          exec: async (text) => {
            await tx.exec(text)
          },
          transaction: () => Promise.reject(new Error("Nested transactions are not supported")),
        }),
      ),
  }
}

/**
 * Fresh, fully migrated database per call. Default: in-process PGlite (no credentials).
 * `npm run test:neon` sets TEST_DB=neon and runs the same suites against TEST_DATABASE_URL
 * (a disposable Neon branch), truncating every table first.
 */
export async function createTestDb(): Promise<TestDb> {
  const files = await readMigrationFiles(MIGRATIONS_DIR)
  if (process.env.TEST_DB === "neon") {
    const url = process.env.TEST_DATABASE_URL
    if (!url) throw new Error("TEST_DB=neon requires TEST_DATABASE_URL (a disposable Neon branch)")
    // This path truncates every table: refuse anything that could be the real database.
    if (url === process.env.DATABASE_URL || url === process.env.DATABASE_URL_UNPOOLED) {
      throw new Error("TEST_DATABASE_URL must not equal DATABASE_URL; point it at a disposable Neon branch")
    }
    const pool = new Pool({ connectionString: url })
    const client = await pool.connect()
    try {
      await applyMigrations(poolExecutor({ query: (text, params) => client.query(text, params) }), files)
      const tables = await client.query(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'",
      )
      const names = tables.rows.map((row: { tablename: string }) => `"${row.tablename}"`)
      if (names.length > 0) await client.query(`TRUNCATE ${names.join(", ")} CASCADE`)
    } finally {
      client.release()
    }
    const db: TestDatabase = {
      query: async <T>(text: string, params?: unknown[]) => (await pool.query(text, params)) as unknown as { rows: T[] },
      exec: (text) => pool.query(text),
      close: () => pool.end(),
    }
    return { db, sql: neonSql(url), close: () => db.close() }
  }
  const db = new PGlite()
  await applyMigrations(pgliteExecutor(db), files)
  return { db, sql: pgliteSql(db), close: () => db.close() }
}
