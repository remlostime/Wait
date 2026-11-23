import type { FastifyBaseLogger } from "fastify"
import type { Config } from "./config.js"
import { fixedClock, systemClock, type Clock } from "./lib/clock.js"
import { createLogger } from "./lib/logger.js"

export interface Container {
  clock: Clock
  /** One logger for Fastify and every service (redaction lives in lib/logger.ts). */
  logger: FastifyBaseLogger
}

/** Options every route plugin receives. */
export interface RouteOptions {
  container: Container
}

/** Composition root: build every repository/service exactly once per cold start. */
export function createContainer(config: Config): Container {
  return { clock: systemClock, logger: createLogger(config.logLevel) }
}

/** In-memory container for `app.inject` tests. Defaults to Friday 2026-11-20 10:00 ET (market open). */
export function createMockContainer(overrides: Partial<Container> = {}): Container {
  return {
    clock: fixedClock(new Date("2026-11-20T15:00:00.000Z")),
    logger: createLogger("silent"),
    ...overrides,
  }
}
