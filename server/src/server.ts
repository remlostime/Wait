import type { IncomingMessage, ServerResponse } from "node:http"
import { buildApp } from "./app.js"
import { loadConfig } from "./config.js"
import { createContainer } from "./container.js"

// Fail fast at cold start: a missing env var crashes the function with the variable's name.
const config = loadConfig(process.env)
const app = await buildApp({ config, container: createContainer(config) })

export { app }

export default async (req: IncomingMessage, res: ServerResponse) => {
  await app.ready()
  app.server.emit("request", req, res)
}
