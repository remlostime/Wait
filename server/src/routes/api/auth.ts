import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { RouteOptions } from "../../container.js"
import { RegisterBodySchema, RegisterResponseSchema } from "../../schemas/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"

const authRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()

  app.post("/register", {
    schema: {
      body: RegisterBodySchema,
      response: { 200: RegisterResponseSchema, 400: ErrorResponseSchema, 429: ErrorResponseSchema, 500: ErrorResponseSchema },
    },
  }, async (request) => {
    const clientIp = (request.headers["x-real-ip"] as string | undefined) ?? request.ip
    const user = await container.auth.register(request.body.anonymousId, clientIp)
    return { token: server.jwt.sign({ userId: user.id }), user: { id: user.id } }
  })
}

export default authRoutes
