import { describe, expect, it } from "vitest"
import { ConfigError, loadConfig } from "../src/config.js"
import { TEST_APNS_KEY_BASE64 } from "./support/apnsKey.js"

const validEnv = {
  NODE_ENV: "production",
  DATABASE_URL: "postgres://user:pass@ep-test.neon.tech/wait?sslmode=require",
  JWT_SECRET: "0123456789abcdef0123456789abcdef",
  FINNHUB_API_KEY: "finnhub-key",
  TIINGO_API_KEY: "tiingo-key",
  ALPACA_KEY_ID: "alpaca-id",
  ALPACA_SECRET_KEY: "alpaca-secret",
  MASSIVE_API_KEY: "massive-key",
  CRON_SECRET: "cron-secret-cron-secret-cron-secret",
  APNS_KEY: TEST_APNS_KEY_BASE64,
  APNS_KEY_ID: "ABC123DEFG",
  APNS_TEAM_ID: "5WDN96EM72",
}

describe("loadConfig", () => {
  it("maps a valid environment to a typed config", () => {
    expect(loadConfig(validEnv)).toEqual({
      nodeEnv: "production",
      logLevel: "info",
      databaseUrl: validEnv.DATABASE_URL,
      jwtSecret: validEnv.JWT_SECRET,
      finnhubApiKey: "finnhub-key",
      tiingoApiKey: "tiingo-key",
      alpacaKeyId: "alpaca-id",
      alpacaSecretKey: "alpaca-secret",
      massive: { apiKey: "massive-key", baseUrl: "https://api.massive.com" },
      cronSecret: "cron-secret-cron-secret-cron-secret",
      apns: { key: TEST_APNS_KEY_BASE64, keyId: "ABC123DEFG", teamId: "5WDN96EM72", topic: "com.chenkai.wait" },
    })
  })

  it("defaults NODE_ENV to development and honours LOG_LEVEL", () => {
    const { NODE_ENV: _ignored, ...rest } = validEnv
    const config = loadConfig({ ...rest, LOG_LEVEL: "debug" })
    expect(config.nodeEnv).toBe("development")
    expect(config.logLevel).toBe("debug")
  })

  it("fails fast listing every missing variable by name only", () => {
    const { JWT_SECRET: _a, FINNHUB_API_KEY: _b, ...rest } = validEnv
    expect(() => loadConfig(rest)).toThrow(ConfigError)
    expect(() => loadConfig(rest)).toThrow(/JWT_SECRET.*FINNHUB_API_KEY|FINNHUB_API_KEY.*JWT_SECRET/)
  })

  it("rejects a JWT secret shorter than 32 characters", () => {
    expect(() => loadConfig({ ...validEnv, JWT_SECRET: "short" })).toThrow(/JWT_SECRET/)
  })

  it("never puts secret values in the error message", () => {
    try {
      loadConfig({ ...validEnv, JWT_SECRET: "leaky-secret" })
      expect.unreachable()
    } catch (error) {
      expect(String(error)).not.toContain("leaky-secret")
    }
  })
})

describe("loadConfig (alerts, plan 06)", () => {
  it("accepts a custom Massive base URL (trailing slash removed) and APNs topic", () => {
    const config = loadConfig({ ...validEnv, MASSIVE_BASE_URL: "https://api.polygon.io/", APNS_TOPIC: "com.chenkai.wait.beta" })
    expect(config.massive.baseUrl).toBe("https://api.polygon.io")
    expect(config.apns.topic).toBe("com.chenkai.wait.beta")
  })

  it.each(["MASSIVE_API_KEY", "CRON_SECRET", "APNS_KEY", "APNS_KEY_ID", "APNS_TEAM_ID"])("fails fast, naming %s, when it is missing", (name) => {
    const env: Record<string, string> = { ...validEnv }
    delete env[name]
    expect(() => loadConfig(env)).toThrow(new RegExp(name))
  })

  it("rejects a CRON_SECRET shorter than 16 characters", () => {
    expect(() => loadConfig({ ...validEnv, CRON_SECRET: "short" })).toThrow(/CRON_SECRET/)
  })

  it("does not parse the APNs key at config time (a bad key only breaks push delivery)", () => {
    expect(loadConfig({ ...validEnv, APNS_KEY: "not-a-key" }).apns.key).toBe("not-a-key")
  })
})
