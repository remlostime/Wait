import { afterAll, describe, expect, it } from "vitest"
import { TEST_APNS_KEY_BASE64 } from "./support/apnsKey.js"

const env = {
  NODE_ENV: "test",
  LOG_LEVEL: "silent",
  DATABASE_URL: "postgres://test:test@localhost:5432/wait_test",
  JWT_SECRET: "test-secret-test-secret-test-secret-0001",
  FINNHUB_API_KEY: "finnhub-test-key",
  TIINGO_API_KEY: "tiingo-test-key",
  ALPACA_KEY_ID: "alpaca-test-id",
  ALPACA_SECRET_KEY: "alpaca-test-secret",
  MASSIVE_API_KEY: "massive-test-key",
  CRON_SECRET: "cron-test-secret-cron-test-secret",
  APNS_KEY: TEST_APNS_KEY_BASE64,
  APNS_KEY_ID: "ABC123DEFG",
  APNS_TEAM_ID: "5WDN96EM72",
}
Object.assign(process.env, env)
const mod = await import("../src/server.js")

afterAll(async () => {
  await mod.app.close()
})

describe("src/server.ts (Vercel entry)", () => {
  it("builds the app from process.env without connecting to the database", async () => {
    expect(typeof mod.default).toBe("function")
    const response = await mod.app.inject({ method: "GET", url: "/health" })
    expect(response.statusCode).toBe(200)
    expect(response.json().status).toBe("ok")
  })
})
