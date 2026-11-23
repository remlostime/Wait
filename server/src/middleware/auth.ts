import type { FastifyReply, FastifyRequest } from "fastify"
import type { User } from "../db/types.js"
import type { UserRepository } from "../db/UserRepository.js"
import { sendError } from "../lib/errors.js"

declare module "fastify" {
  interface FastifyRequest {
    authenticatedUser: User
  }
}

/**
 * Register `authenticate` as an **onRequest** hook (`app.addHook("onRequest", authenticate)` or
 * `onRequest: [authenticate]`) so an unauthenticated request gets 401 before body/query validation.
 */
export function buildAuthMiddleware(users: UserRepository) {
  const authenticate = async (request: FastifyRequest, reply: FastifyReply) => {
    let userId: unknown
    try {
      userId = (await request.jwtVerify<{ userId?: unknown }>()).userId
    } catch {
      return sendError(reply, 401, "UNAUTHORIZED", "Invalid or expired token")
    }
    if (typeof userId !== "string" || userId.length === 0) return sendError(reply, 401, "UNAUTHORIZED", "Invalid or expired token")
    // Database errors propagate to the global handler (500), unlike Resignal, which reported them as 401.
    const user = await users.getById(userId)
    if (!user) return sendError(reply, 401, "USER_NOT_FOUND", "User associated with token no longer exists")
    request.authenticatedUser = user
  }
  return { authenticate }
}
