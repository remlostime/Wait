import { z } from "zod"

export type LogLevel = "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent"

export interface Config {
  nodeEnv: "development" | "test" | "production"
  logLevel: LogLevel
  databaseUrl: string
  jwtSecret: string
  finnhubApiKey: string
  tiingoApiKey: string
  alpacaKeyId: string
  alpacaSecretKey: string
}

export class ConfigError extends Error {
  constructor(readonly variables: string[]) {
    super(`Invalid or missing environment variables: ${variables.join(", ")}`)
    this.name = "ConfigError"
  }
}

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  FINNHUB_API_KEY: z.string().trim().min(1),
  TIINGO_API_KEY: z.string().trim().min(1),
  ALPACA_KEY_ID: z.string().trim().min(1),
  ALPACA_SECRET_KEY: z.string().trim().min(1),
})

/** Pure: validates `env` and returns a typed config. Throws `ConfigError` naming (never echoing) bad variables. */
export function loadConfig(env: Record<string, string | undefined>): Config {
  const parsed = EnvSchema.safeParse(env)
  if (!parsed.success) {
    const names = [...new Set(parsed.error.issues.map((issue) => String(issue.path[0])))].sort()
    throw new ConfigError(names)
  }
  const e = parsed.data
  return {
    nodeEnv: e.NODE_ENV,
    logLevel: e.LOG_LEVEL,
    databaseUrl: e.DATABASE_URL,
    jwtSecret: e.JWT_SECRET,
    finnhubApiKey: e.FINNHUB_API_KEY,
    tiingoApiKey: e.TIINGO_API_KEY,
    alpacaKeyId: e.ALPACA_KEY_ID,
    alpacaSecretKey: e.ALPACA_SECRET_KEY,
  }
}
