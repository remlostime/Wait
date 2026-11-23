import type { FastifyPluginAsync } from "fastify"
import fjwt from "@fastify/jwt"
import fp from "fastify-plugin"

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { userId: string }
    user: { userId: string }
  }
}

export interface JwtPluginOptions {
  secret: string
}

const jwtPlugin: FastifyPluginAsync<JwtPluginOptions> = async (server, { secret }) => {
  await server.register(fjwt, {
    secret,
    sign: { algorithm: "HS256", expiresIn: "7d" },
    verify: { algorithms: ["HS256"] },
  })
}

// fp: `request.jwtVerify` / `server.jwt` must be visible to every route plugin.
export default fp(jwtPlugin, { name: "wait-jwt" })
