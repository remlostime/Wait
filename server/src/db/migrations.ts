import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import type { Row } from "./sql.js"

export interface MigrationExecutor {
  query(text: string, params?: unknown[]): Promise<Row[]>
  /** Multi-statement text, no parameters (simple query protocol). */
  exec(text: string): Promise<void>
  transaction<T>(fn: (tx: MigrationExecutor) => Promise<T>): Promise<T>
}

export interface MigrationFile {
  version: number
  name: string
  sql: string
}

/** Arbitrary constant key for `pg_advisory_xact_lock`, shared by every migration runner. */
const MIGRATION_LOCK_KEY = 7_340_201

const FILE_PATTERN =/^(\d{3})_([a-z0-9_]+)\.sql$/

export async function readMigrationFiles(dir: string): Promise<MigrationFile[]> {
  const entries = (await readdir(dir)).filter((entry) => entry.endsWith(".sql")).sort()
  const files: MigrationFile[] = []
  for (const entry of entries) {
    const match = FILE_PATTERN.exec(entry)
    if (!match) throw new Error(`Migration file name must look like 001_name.sql: ${entry}`)
    files.push({ version: Number(match[1]), name: match[2] ?? "", sql: await readFile(path.join(dir, entry), "utf8") })
  }
  const versions = files.map((file) => file.version)
  if (new Set(versions).size !== versions.length) throw new Error(`Duplicate migration version in ${dir}`)
  return files
}

export async function applyMigrations(
  executor: MigrationExecutor,
  files: MigrationFile[],
): Promise<{ applied: number[]; skipped: number[] }> {
  await executor.exec(
    "CREATE TABLE IF NOT EXISTS schema_migrations (version INT PRIMARY KEY, name TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())",
  )
  const done = new Set((await executor.query("SELECT version FROM schema_migrations")).map((row) => Number(row.version)))
  const applied: number[] = []
  const skipped: number[] = []
  for (const file of [...files].sort((a, b) => a.version - b.version)) {
    if (done.has(file.version)) {
      skipped.push(file.version)
      continue
    }
    const didApply = await executor.transaction(async (tx) => {
      // Serialize concurrent runners (e.g. a manual run overlapping CI), then re-check under the lock.
      await tx.query("SELECT pg_advisory_xact_lock($1)", [MIGRATION_LOCK_KEY])
      const existing = await tx.query("SELECT 1 FROM schema_migrations WHERE version = $1", [file.version])
      if (existing.length > 0) return false
      await tx.exec(file.sql)
      await tx.query("INSERT INTO schema_migrations (version, name) VALUES ($1, $2)", [file.version, file.name])
      return true
    })
    if (didApply) applied.push(file.version)
    else skipped.push(file.version)
  }
  return { applied, skipped }
}

/** Adapts a Neon `Pool` client (pg-compatible) for `scripts/migrate.ts` and `npm run test:neon`. */
export interface PoolClientLike {
  query(text: string, params?: unknown[]): Promise<{ rows: Row[] }>
}

export function poolExecutor(client: PoolClientLike): MigrationExecutor {
  const executor: MigrationExecutor = {
    query: async (text, params) => (await client.query(text, params)).rows,
    exec: async (text) => {
      await client.query(text)
    },
    transaction: async (fn) => {
      await client.query("BEGIN")
      try {
        const result = await fn(executor)
        await client.query("COMMIT")
        return result
      } catch (error) {
        // A failed ROLLBACK (e.g. dropped connection) must not mask the migration's own error.
        await client.query("ROLLBACK").catch(() => {})
        throw error
      }
    },
  }
  return executor
}
