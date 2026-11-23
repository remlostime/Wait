import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../../container.js"
import { sendError } from "../../../lib/errors.js"
import { safeEqual } from "../../../lib/safeEqual.js"
import { DailyAlertsResponseSchema } from "../../../schemas/alerts.js"
import { ErrorResponseSchema } from "../../../schemas/common.js"

export type DailyAlertsRouteOptions = RouteOptions & { cronSecret: string }

/** Vercel Cron sends `Authorization: Bearer $CRON_SECRET` (overview §8.6). */
const dailyAlertsRoutes: FastifyPluginAsync<DailyAlertsRouteOptions> = async (server, { container, cronSecret }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()

  app.get(
    "/daily-alerts",
    { schema: { response: { 200: DailyAlertsResponseSchema, 401: ErrorResponseSchema, 500: ErrorResponseSchema } } },
    async (request, reply) => {
      if (!safeEqual(request.headers.authorization ?? "", `Bearer ${cronSecret}`)) {
        return sendError(reply, 401, "UNAUTHORIZED", "Missing or invalid cron secret")
      }
      const result = await container.alertJob.run(container.clock.now(), request.log)
      request.log.info(result, "alerts.daily")
      return result
    },
  )
}

export default dailyAlertsRoutes
