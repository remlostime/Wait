import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import { Type } from "@sinclair/typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../container.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"
import { DEFAULT_BUNDLE_ID, DeviceTokenParamsSchema, RegisterDeviceBodySchema } from "../../schemas/devices.js"

const deviceRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)
  const errors = { 400: ErrorResponseSchema, 401: ErrorResponseSchema, 500: ErrorResponseSchema }

  // onRequest, not preHandler: a request without a valid token gets 401 before body/param validation (plan 04).
  app.post(
    "/",
    { onRequest: [authenticate], schema: { body: RegisterDeviceBodySchema, response: { 204: Type.Null(), ...errors } } },
    async (request, reply) => {
      const { token, environment, bundleId } = request.body
      await container.deviceTokens.upsert(
        { token, userId: request.authenticatedUser.id, environment, bundleId: bundleId ?? DEFAULT_BUNDLE_ID },
        container.clock.now(),
      )
      return reply.status(204).send(null)
    },
  )

  app.delete(
    "/:token",
    { onRequest: [authenticate], schema: { params: DeviceTokenParamsSchema, response: { 204: Type.Null(), ...errors } } },
    async (request, reply) => {
      await container.deviceTokens.removeForUser(request.params.token, request.authenticatedUser.id)
      return reply.status(204).send(null)
    },
  )
}

export default deviceRoutes
