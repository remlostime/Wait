import type { FastifyBaseLogger } from "fastify"
import { pino, type DestinationStream } from "pino"
import type { LogLevel } from "../config.js"

/** Never log bearer tokens or device tokens (Resignal gap, overview §8.1). */
export const REDACT_PATHS = ["req.headers.authorization", "headers.authorization", "*.token", "*.deviceToken"]

/** The single pino logger behind Fastify (`loggerInstance`) and every service. */
export function createLogger(level: LogLevel, stream?: DestinationStream): FastifyBaseLogger {
  const options = { level, redact: { paths: REDACT_PATHS, censor: "[redacted]" } }
  return stream ? pino(options, stream) : pino(options)
}
