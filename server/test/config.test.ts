import { describe, expect, it } from "vitest"
import { ConfigError, loadConfig } from "../src/config.js"

const validEnv = {
  NODE_ENV: "production",
  DATABASE_URL: "postgres://user:pass@ep-test.neon.tech/wait?sslmode=require",
  JWT_SECRET: "0123456789abcdef0123456789abcdef",
  FINNHUB_API_KEY: "finnhub-key",
  TIINGO_API_KEY: "tiingo-key",
  ALPACA_KEY_ID: "alpaca-id",
  ALPACA_SECRET_KEY: "alpaca-secret",
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
