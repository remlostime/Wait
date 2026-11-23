import dotenv from "dotenv"

dotenv.config({ path: ".env.development.local" })
dotenv.config({ path: ".env.local", override: true })

const { app } = await import("./server.js")
const port = Number(process.env.PORT) || 3000

try {
  await app.listen({ port, host: "0.0.0.0" })
} catch (error) {
  app.log.error(error)
  process.exit(1)
}
