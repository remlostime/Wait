import type { FastifyReply } from "fastify"

export class AppError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly statusCode: number,
    readonly retryAfterSec?: number,
  ) {
    super(message)
    this.name = "AppError"
  }
}

export function sendError(reply: FastifyReply, statusCode: number, code: string, message: string) {
  return reply.status(statusCode).send({ error: { code, message } })
}

export function sendAppError(reply: FastifyReply, error: AppError) {
  if (error.retryAfterSec !== undefined) {
    reply.header("Retry-After", String(Math.max(1, Math.ceil(error.retryAfterSec))))
  }
  return sendError(reply, error.statusCode, error.code, error.message)
}
