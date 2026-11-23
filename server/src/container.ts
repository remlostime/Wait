import type { Config } from "./config.js"
import { MockUserRepository } from "./db/MockUserRepository.js"
import { NeonUserRepository } from "./db/NeonUserRepository.js"
import { neonSql, type Sql } from "./db/sql.js"
import type { UserRepository } from "./db/UserRepository.js"
import { fixedClock, systemClock, type Clock } from "./lib/clock.js"
import { createLogger } from "./lib/logger.js"
import type { FastifyBaseLogger } from "fastify"
import { AuthService } from "./services/AuthService.js"
import { MockRateLimiter, PostgresRateLimiter, type RateLimiter } from "./services/RateLimiter.js"

export interface Container {
  clock: Clock
  /** One logger for Fastify and every service (redaction lives in lib/logger.ts). */
  logger: FastifyBaseLogger
  /** Shared by every SQL repository; later plans build their repositories from it. */
  sql: Sql
  users: UserRepository
  rateLimiter: RateLimiter
  auth: AuthService
}

/** Options every route plugin receives. */
export interface RouteOptions {
  container: Container
}

/** Composition root: build every repository/service exactly once per cold start. No I/O happens here. */
export function createContainer(config: Config): Container {
  const sql = neonSql(config.databaseUrl)
  const clock = systemClock
  const users = new NeonUserRepository(sql)
  const rateLimiter = new PostgresRateLimiter(sql, clock)
  return { clock, logger: createLogger(config.logLevel), sql, users, rateLimiter, auth: new AuthService(users, rateLimiter, clock) }
}

/** The mock container has no database unless a test passes `{ sql }` from `createTestDb()`. */
const noDatabase: Sql = async () => {
  throw new Error("createMockContainer has no database; pass { sql } from createTestDb()")
}

/** In-memory container for `app.inject` tests. Defaults to Friday 2026-11-20 10:00 ET (market open). */
export function createMockContainer(overrides: Partial<Container> = {}): Container {
  const clock = overrides.clock ?? fixedClock(new Date("2026-11-20T15:00:00.000Z"))
  const users = overrides.users ?? new MockUserRepository()
  const rateLimiter = overrides.rateLimiter ?? new MockRateLimiter()
  return {
    clock,
    logger: overrides.logger ?? createLogger("silent"),
    sql: overrides.sql ?? noDatabase,
    users,
    rateLimiter,
    auth: overrides.auth ?? new AuthService(users, rateLimiter, clock),
  }
}
