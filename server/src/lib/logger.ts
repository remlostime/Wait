import type { FastifyBaseLogger } from "fastify"
import { pino, type DestinationStream } from "pino"
import type { LogLevel } from "../config.js"

/** Never log bearer tokens or device tokens (Resignal gap, overview §8.1). */
export const REDACT_PATHS = [
  "token",
  "deviceToken",
  "*.token",
  "*.deviceToken",
  "*.*.token",
  "*.*.deviceToken",
  "req.headers.authorization",
  "headers.authorization",
  "*.headers.authorization",
  '*.headers["x-finnhub-token"]',
  '*.headers["apca-api-key-id"]',
  '*.headers["apca-api-secret-key"]',
]

/** The single pino logger behind Fastify (`loggerInstance`) and every service. */
export function createLogger(level: LogLevel, stream?: DestinationStream): FastifyBaseLogger {
  const options = { level, redact: { paths: REDACT_PATHS, censor: "[redacted]" } }
  return stream ? pino(options, stream) : pino(options)
}
