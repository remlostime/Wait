import dotenv from "dotenv"

// Shell variables win over both files; `.env.local` wins over `.env.development.local` (same as scripts/migrate.ts).
dotenv.config({ path: [".env.local", ".env.development.local"] })

const { app } = await import("./server.js")
const port = Number(process.env.PORT) || 3000

try {
  await app.listen({ port, host: "0.0.0.0" })
} catch (error) {
  app.log.error(error)
  process.exit(1)
}
