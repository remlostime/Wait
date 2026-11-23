import path from "node:path"
import dotenv from "dotenv"
import { Pool } from "@neondatabase/serverless"
import { applyMigrations, poolExecutor, readMigrationFiles } from "../src/db/migrations.js"

// A URL set in the shell (e.g. a disposable Neon branch) wins over the files loaded below.
const fromShell = process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL
dotenv.config({ path: ".env.development.local" })
dotenv.config({ path: ".env.local", override: true })

// Prefer the direct (unpooled) URL for DDL when the Vercel ↔ Neon integration provides it.
const url = fromShell ?? process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL
if (!url) {
  console.error("DATABASE_URL is not set. Run `vercel env pull .env.local --environment=production` inside server/ first.")
  process.exit(1)
}
console.log(`migrating ${new URL(url).host}${fromShell ? " (from the shell)" : ""}`)

const pool = new Pool({ connectionString: url })
const client = await pool.connect()
try {
  const files = await readMigrationFiles(path.resolve(import.meta.dirname, "../migrations"))
  const { applied, skipped } = await applyMigrations(poolExecutor({ query: (text, params) => client.query(text, params) }), files)
  console.log(`migrations applied: [${applied.join(", ")}] skipped: [${skipped.join(", ")}]`)
} finally {
  client.release()
  await pool.end()
}
