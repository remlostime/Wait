import { mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import { PGlite } from "@electric-sql/pglite"
import { afterEach, describe, expect, it } from "vitest"
import { applyMigrations, readMigrationFiles } from "../../src/db/migrations.js"
import { MIGRATIONS_DIR, pgliteExecutor } from "../support/pglite.js"

let db: PGlite | undefined

afterEach(async () => {
  await db?.close()
  db = undefined
})

describe("readMigrationFiles", () => {
  it("reads NNN_name.sql files in version order", async () => {
    const files = await readMigrationFiles(MIGRATIONS_DIR)
    expect(files[0]).toMatchObject({ version: 1, name: "users_and_rate_limits" })
    expect(files.map((f) => f.version)).toEqual([...files.map((f) => f.version)].sort((a, b) => a - b))
  })

  it("rejects badly named files", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "wait-migrations-"))
    await writeFile(path.join(dir, "1_bad.sql"), "SELECT 1;")
    await expect(readMigrationFiles(dir)).rejects.toThrow(/001_name\.sql/)
  })
})

describe("applyMigrations", () => {
  it("applies every file once and is a no-op on the second run", async () => {
    db = new PGlite()
    const files = await readMigrationFiles(MIGRATIONS_DIR)
    const first = await applyMigrations(pgliteExecutor(db), files)
    expect(first).toEqual({ applied: files.map((f) => f.version), skipped: [] })
    const tables = await db.query<{ users: string | null; buckets: string | null }>(
      "SELECT to_regclass('public.users')::text AS users, to_regclass('public.rate_buckets')::text AS buckets",
    )
    expect(tables.rows[0]).toEqual({ users: "users", buckets: "rate_buckets" })

    const second = await applyMigrations(pgliteExecutor(db), files)
    expect(second).toEqual({ applied: [], skipped: files.map((f) => f.version) })
  })

  it("rolls back a failing migration and does not record it", async () => {
    db = new PGlite()
    const broken = [{ version: 900, name: "broken", sql: "CREATE TABLE half_done (id INT); SELECT * FROM missing_table;" }]
    await expect(applyMigrations(pgliteExecutor(db), broken)).rejects.toThrow(/missing_table/)
    const leftovers = await db.query<{ t: string | null }>("SELECT to_regclass('public.half_done')::text AS t")
    expect(leftovers.rows[0]?.t).toBeNull()
    const recorded = await db.query("SELECT version FROM schema_migrations WHERE version = 900")
    expect(recorded.rows).toEqual([])
  })
})
