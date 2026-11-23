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

/** APNs device tokens are 64+ hex characters; `DELETE /api/devices/:token` carries one in the URL path. */
const DEVICE_TOKEN_SEGMENT = /[0-9a-f]{64,}/gi

/** Redacts anything token-shaped from a request URL before it is logged (Fastify logs `req.url`). */
export function redactUrl(url: string | undefined): string | undefined {
  return url?.replace(DEVICE_TOKEN_SEGMENT, "[redacted]")
}

type LoggedRequest = {
  method?: string
  url?: string
  headers?: Record<string, unknown>
  host?: string
  ip?: string
  socket?: { remotePort?: number }
}

/**
 * Replaces Fastify's default `req` serializer (an instance's serializers win over Fastify's) with the same
 * fields, minus device tokens in the URL.
 */
export function serializeRequest(request: LoggedRequest) {
  return {
    method: request.method,
    url: redactUrl(request.url),
    version: request.headers?.["accept-version"],
    host: request.host,
    remoteAddress: request.ip,
    remotePort: request.socket?.remotePort,
  }
}

/** The single pino logger behind Fastify (`loggerInstance`) and every service. */
export function createLogger(level: LogLevel, stream?: DestinationStream): FastifyBaseLogger {
  const options = { level, redact: { paths: REDACT_PATHS, censor: "[redacted]" }, serializers: { req: serializeRequest } }
  return stream ? pino(options, stream) : pino(options)
}
