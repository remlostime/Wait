import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { RouteOptions } from "../../container.js"
import { AppError } from "../../lib/errors.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema, SYMBOL_REGEX } from "../../schemas/common.js"
import {
  HistoryQuerySchema,
  HistoryResponseSchema,
  ProfileQuerySchema,
  ProfileResponseSchema,
  QuotesQuerySchema,
  QuotesResponseSchema,
  SearchQuerySchema,
  SearchResponseSchema,
} from "../../schemas/market.js"

const MAX_SYMBOLS = 50

export function parseSymbols(raw: string): string[] {
  const symbols = [...new Set(raw.split(",").map((s) => s.trim().toUpperCase()).filter((s) => s.length > 0))]
  if (symbols.length === 0 || symbols.length > MAX_SYMBOLS) {
    throw new AppError("INVALID_INPUT", `symbols must list 1 to ${MAX_SYMBOLS} tickers`, 400)
  }
  const invalid = symbols.find((symbol) => !SYMBOL_REGEX.test(symbol))
  if (invalid) throw new AppError("INVALID_INPUT", `Invalid symbol: ${invalid}`, 400)
  return symbols
}

const errors = { 400: ErrorResponseSchema, 401: ErrorResponseSchema, 404: ErrorResponseSchema, 502: ErrorResponseSchema, 503: ErrorResponseSchema }

const marketRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)
  // onRequest, not preHandler: 401 comes before querystring validation.
  app.addHook("onRequest", authenticate)

  app.get("/quotes", { schema: { querystring: QuotesQuerySchema, response: { 200: QuotesResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getQuotes(parseSymbols(request.query.symbols)),
  )

  app.get("/history", { schema: { querystring: HistoryQuerySchema, response: { 200: HistoryResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getHistory(request.query.symbol, request.query.range),
  )

  app.get("/search", { schema: { querystring: SearchQuerySchema, response: { 200: SearchResponseSchema, ...errors } } }, async (request) => ({
    results: await container.marketData.search(request.query.q),
  }))

  app.get("/profile", { schema: { querystring: ProfileQuerySchema, response: { 200: ProfileResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getProfile(request.query.symbol),
  )
}

export default marketRoutes
