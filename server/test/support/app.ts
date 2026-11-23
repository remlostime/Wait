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

/** Builds the app over `createMockContainer(overrides)`. Task 8 extends it with a default user and `authHeaders`. */
export async function buildTestApp(overrides: Partial<Container> = {}) {
  const container = createMockContainer(overrides)
  const app = await buildApp({ config: testConfig, container })
  return { app, container }
}
