import type { Config } from "../../src/config.js"
import { buildApp } from "../../src/app.js"
import { createMockContainer, type Container } from "../../src/container.js"

export const testConfig: Config = {
  nodeEnv: "test",
  logLevel: "silent",
  databaseUrl: "postgres://test:test@localhost:5432/wait_test",
  jwtSecret: "test-secret-test-secret-test-secret-0001",
  finnhubApiKey: "finnhub-test-key",
  tiingoApiKey: "tiingo-test-key",
  alpacaKeyId: "alpaca-test-id",
  alpacaSecretKey: "alpaca-test-secret",
}

export const TEST_ANONYMOUS_ID = "00000000-0000-4000-8000-000000000001"

/**
 * Builds the app over `createMockContainer(overrides)` and seeds one default user.
 * `authHeaders(userId?)` signs a token exactly like /api/auth/register (default: the seeded user).
 * `app.jwt` exists as soon as `buildApp` resolves (the fp-wrapped plugin was awaited), so tests may
 * still add ad-hoc routes before the first `inject`.
 */
export async function buildTestApp(overrides: Partial<Container> = {}) {
  const container = createMockContainer(overrides)
  const app = await buildApp({ config: testConfig, container })
  const user = await container.users.findOrCreateByAnonymousId(TEST_ANONYMOUS_ID, container.clock.now())
  const authHeaders = (userId: string = user.id): Record<string, string> => ({
    authorization: `Bearer ${app.jwt.sign({ userId })}`,
  })
  return { app, container, user, authHeaders }
}
