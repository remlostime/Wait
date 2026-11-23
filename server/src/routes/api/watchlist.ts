import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../container.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"
import {
  SyncBodySchema,
  SyncResponseSchema,
  WatchlistListResponseSchema,
  toWatchlistChange,
  toWatchlistItemDto,
} from "../../schemas/watchlist.js"

/** Vercel caps request bodies at 4.5 MB. The iOS client sends at most 50 changes per request. */
const SYNC_BODY_LIMIT = 4 * 1024 * 1024

const watchlistRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)

  app.post(
    "/sync",
    {
      // onRequest, as in plan 04: an unauthenticated request gets 401 before the body is validated.
      onRequest: [authenticate],
      bodyLimit: SYNC_BODY_LIMIT,
      schema: {
        body: SyncBodySchema,
        response: { 200: SyncResponseSchema, 400: ErrorResponseSchema, 401: ErrorResponseSchema },
      },
    },
    async (request) => {
      const result = await container.watchlistSync.sync(
        request.authenticatedUser.id,
        { cursor: request.body.cursor ?? null, changes: request.body.changes.map(toWatchlistChange) },
        container.clock.now(),
      )
      return { changes: result.changes.map(toWatchlistItemDto), cursor: result.cursor, hasMore: result.hasMore }
    },
  )

  app.get(
    "/",
    { onRequest: [authenticate], schema: { response: { 200: WatchlistListResponseSchema, 401: ErrorResponseSchema } } },
    async (request) => {
      const result = await container.watchlistSync.list(request.authenticatedUser.id)
      return { items: result.items.map(toWatchlistItemDto), cursor: result.cursor }
    },
  )
}

export default watchlistRoutes
