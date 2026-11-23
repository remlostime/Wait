import Fastify, { type FastifyError } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { Config } from "./config.js"
import type { Container } from "./container.js"
import { AppError, sendAppError, sendError } from "./lib/errors.js"
import jwtPlugin from "./plugins/jwt.js"
import authRoutes from "./routes/api/auth.js"
import deviceRoutes from "./routes/api/devices.js"
import dailyAlertsRoutes from "./routes/api/internal/dailyAlerts.js"
import marketRoutes from "./routes/api/market.js"
import watchlistRoutes from "./routes/api/watchlist.js"
import healthRoutes from "./routes/health.js"

/** Codes from the overview §8.4 table for framework/plugin 4xx errors; anything else is INVALID_INPUT. */
const CLIENT_ERROR_CODES: Record<number, string> = { 401: "UNAUTHORIZED", 404: "NOT_FOUND", 429: "RATE_LIMITED" }

export interface BuildAppOptions {
  config: Config
  container: Container
}

export async function buildApp({ config, container }: BuildAppOptions) {
  const app = Fastify({
    loggerInstance: container.logger,
    bodyLimit: 1024 * 1024,
    // Overview §8.1 "Request validation (Ajv)": Fastify's defaults coerce `null` to "" inside
    // nullable unions and silently strip unknown fields. Validate exactly what the client sent.
    ajv: { customOptions: { coerceTypes: false, removeAdditional: false } },
  }).withTypeProvider<TypeBoxTypeProvider>()

  app.addHook("onSend", async (_request, reply) => {
    reply.header("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
    reply.header("X-Content-Type-Options", "nosniff")
    reply.header("X-Frame-Options", "DENY")
    reply.header("Referrer-Policy", "no-referrer")
  })

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (error instanceof AppError) return sendAppError(reply, error)
    if (error.validation) return sendError(reply, 400, "VALIDATION_ERROR", error.message)
    if (typeof error.statusCode === "number" && error.statusCode >= 400 && error.statusCode < 500) {
      return sendError(reply, error.statusCode, CLIENT_ERROR_CODES[error.statusCode] ?? "INVALID_INPUT", error.message)
    }
    request.log.error({ err: error }, "unhandled_error")
    return sendError(reply, 500, "INTERNAL_ERROR", "An unexpected error occurred")
  })

  app.setNotFoundHandler((_request, reply) => sendError(reply, 404, "NOT_FOUND", "The requested resource was not found"))

  await app.register(jwtPlugin, { secret: config.jwtSecret })
  await app.register(healthRoutes, { container })
  await app.register(authRoutes, { prefix: "/api/auth", container })
  await app.register(marketRoutes, { prefix: "/api/market", container })
  await app.register(watchlistRoutes, { prefix: "/api/watchlist", container })
  await app.register(deviceRoutes, { prefix: "/api/devices", container })
  await app.register(dailyAlertsRoutes, { prefix: "/api/internal", container, cronSecret: config.cronSecret })

  return app
}

export type App = Awaited<ReturnType<typeof buildApp>>
