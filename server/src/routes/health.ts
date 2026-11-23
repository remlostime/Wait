import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import { Type } from "@sinclair/typebox"
import type { RouteOptions } from "../container.js"

const HealthResponseSchema = Type.Object({ status: Type.Literal("ok"), timestamp: Type.String() })

const healthRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  app.get("/health", { schema: { response: { 200: HealthResponseSchema } } }, async () => ({
    status: "ok" as const,
    timestamp: container.clock.now().toISOString(),
  }))
}

export default healthRoutes
