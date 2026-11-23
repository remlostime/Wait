# Wait Backend: Auth and Market Data Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Stand up the Wait backend in `/Users/ckai/code/Wait/server`, deployed on Vercel with Neon Postgres.
- The backend provides anonymous auth and a cached, rate-limited market-data proxy.
- The iOS app then gets every quote, chart, search and profile from this proxy, so no provider key ships in the app.

**Architecture:**
- **Framework:** Fastify 5 with TypeBox route schemas, in TypeScript ESM, built as one function by `buildApp({ config, container })`.
- **Composition root:** `container.ts` builds the repositories (raw SQL through an injected `Sql` function), the services and the market-data providers (Finnhub, Tiingo, Alpaca) once.
- **Rate limiting and caching:** a token bucket in Postgres and cache tables in Postgres protect the free provider quotas.
- **iOS:** a new `APIClient` WaitKit target (Keychain identity, JWT session, DTOs). `MarketDataClient.backend` replaces the Twelve Data stopgap behind the existing caching decorator.

**Tech Stack:**
- **Server runtime:** Node ≥ 22, Fastify ^5.7.1, @fastify/type-provider-typebox ^6.1.0, @sinclair/typebox ^0.34.49, @fastify/jwt ^10, fastify-plugin ^5.1, @neondatabase/serverless ^1.0.2, zod ^3.25.
- **Server testing:** vitest ^4.1, @electric-sql/pglite, tsx.
- **iOS:** Swift 6, swift-dependencies, TCA 1.26, Swift Testing.

**Source of truth:** `/Users/ckai/code/Wait/docs/superpowers/plans/2026-11-22-wait-00-overview.md`. This plan implements:
- §6.3 items 1–5 (except the Massive job)
- §8.1–§8.4 rows tagged "04"
- §9 APIClient
- §12.3 "04" extension points

**Reference implementation (read-only):** `/Users/ckai/code/Resignal-backend`. Its patterns are copied here and its known gaps are fixed (overview §8.1). Never print values from its `.env*` files or `certs/`.

---

## Prerequisites

1. **Worktree.** Use @superpowers:using-git-worktrees to create a worktree off `ck/new-version` (for example `../Wait-plan04`, branch `ck/plan-04-backend`). Never work on `master`.
2. **Ordering.**
   - The canonical order is 01 → 02 → 03 → 04 → 05 → 06 (overview §4).
   - **Server chunks 1–8** have no dependency on the iOS plans. They may start in parallel with plans 01–03.
   - **iOS chunks 9–12** need plans 01–03 finished: `Domain`, `MarketDataClient` (with `.cached(...)` and the Twelve Data adapter), `StockDetailsFeature`, `SettingsFeature`, `AppFeature` (its `AppDelegate` is in `Sources/AppFeature/AppDelegate.swift`), `Connectivity`, and `Config/Base.xcconfig`.
   - Before starting Chunk 9, confirm these paths exist:
     ```bash
     ls /Users/ckai/code/Wait/Wait/Packages/WaitKit/Sources/MarketDataClient/CachingMarketDataClient.swift \
        /Users/ckai/code/Wait/Wait/Packages/WaitKit/Sources/StockDetailsFeature/StatsSection.swift \
        /Users/ckai/code/Wait/Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift \
        /Users/ckai/code/Wait/Wait/Config/Base.xcconfig
     ```
     Expected: all four paths are printed, with no "No such file" errors.
3. **Accounts `(manual: user)`**, needed before Chunk 8 (deploy). Tests never call real providers.
   - Finnhub: free API key from https://finnhub.io/register.
   - Tiingo: free API token from https://www.tiingo.com (Account → API → Token).
   - Alpaca: a free **paper** account at https://app.alpaca.markets. Use Paper Trading → API Keys to get a Key ID and Secret; the Basic market-data plan comes with it.
   - Vercel: a project with **Root Directory `server`**, plus the **Neon** integration, which adds `DATABASE_URL`.
4. **Tools.** Node ≥ 22 (local v26 is fine), npm, and Xcode 27 for Chunks 9–12. Network access for `npm install`.
5. **Skills.**
   - @superpowers:test-driven-development for every task.
   - @swiftui-expert:swiftui-expert-skill for the SwiftUI views in Chunks 11–12.
   - @ios-code-best-practice:ios-code-best-practice for its Swift concurrency guidance only (skip the Pinterest-only parts).
6. **Assumptions about plan 02's `Domain` types.**
   - The public memberwise-style initializers in `MarketTypes.swift` take parameters in the field order of overview §7.5:
     - `Quote(symbol:price:previousClose:open:high:low:change:changePercent:volume:fiftyTwoWeekHigh:fiftyTwoWeekLow:asOf:isStale:)`
     - `PricePoint(date:close:)`
     - `PriceSeries(symbol:range:points:asOf:delayedMinutes:isStale:)`
     - `SymbolSearchResult(symbol:name:exchange:type:)`
     - `CompanyProfile(symbol:name:exchange:industry:logoURL:marketCap:peRatio:pbRatio:dividendYield:roe:roa:profitMargin:fiftyTwoWeekHigh:fiftyTwoWeekLow:beta:asOf:)`
   - If plan 02 used different argument labels, keep plan 02's labels. Change only the call sites in this plan.
   - The same applies to these plan 02 shapes from the design (overview §12):
     - `WatchlistItem(symbol:name:ladder:memo:isFavorite:sortIndex:checklist:ladderHistory:createdAt:updatedAt:)`
     - `MarketDataClient` closures `quotes(symbols, policy)`, `series(symbol, range, policy)`, `search(query)`, `profile(symbol)`
     - `MarketDataError` cases `rateLimited(retryAfter: Duration?)`, `notFound`, `notCached`, `network(String)`, `decoding(String)`, `unavailable`, plus `init(_ error: any Error)`
     - `StockDetailsFeature.State(item: Shared<WatchlistItem>)`
     - `SettingsFeature.State()`
   - Before Chunk 9, read the actual files and adapt only the call sites.

All server commands run from `/Users/ckai/code/Wait/server` unless a step says otherwise.

---

## File Structure

### Server (`/Users/ckai/code/Wait/server`, all new)

| Path | Responsibility |
|---|---|
| `package.json`, `tsconfig.json`, `tsconfig.test.json`, `vitest.config.ts`, `.gitignore`, `.env.example` | Tooling. `tsconfig.json` builds `src` only; `tsconfig.test.json` typechecks `src`, `test` and `scripts`. |
| `vercel.json` | Legacy `builds` config: `src/server.ts` → `@vercel/node`, with routes for `/api/*` and `/health` |
| `migrations/001_users_and_rate_limits.sql`, `migrations/002_market_cache.sql` | Schema from overview §8.3 |
| `scripts/migrate.ts` | Applies migrations to `$DATABASE_URL` through the Neon `Pool` |
| `src/config.ts` | `loadConfig(env)`: zod validation, fail-fast, pure |
| `src/lib/errors.ts` | `AppError`, `sendError`, `sendAppError` (sets `Retry-After`) |
| `src/lib/safeEqual.ts` | Timing-safe string comparison (used by plan 06) |
| `src/lib/clock.ts` | `Clock`, `systemClock`, `fixedClock` |
| `src/lib/time.ts` | Row-mapper helpers: `asDate`, `asNullableDate`, `asNumber`, `asNullableString` |
| `src/lib/decimal.ts` | `toDecimalString(number)`, `nullableDecimal(number?)` |
| `src/lib/concurrency.ts` | `mapLimit(items, limit, fn)` |
| `src/lib/logger.ts` | `createLogger(level, stream?)` and `REDACT_PATHS`: the one pino logger for Fastify and every service |
| `src/app.ts` | `buildApp({ config, container })`: Fastify instance, error and not-found handlers, plugins and routes |
| `src/container.ts` | `Container`, `createContainer(config)`, `createMockContainer(overrides)` |
| `src/server.ts` | Vercel entry (default export handler) |
| `src/index.ts` | Local dev entry: dotenv, then listen on :3000 |
| `src/plugins/jwt.ts` | fp-wrapped `@fastify/jwt`: HS256, 7 days, payload `{ userId }` |
| `src/middleware/auth.ts` | `buildAuthMiddleware(users)`, which sets `request.authenticatedUser` |
| `src/db/sql.ts` | `Sql` type, `neonSql`, `pgliteSql`, `toParameterized` |
| `src/db/migrations.ts` | `readMigrationFiles`, `applyMigrations`, `poolExecutor` |
| `src/db/types.ts` | `User` |
| `src/db/UserRepository.ts`, `src/db/NeonUserRepository.ts`, `src/db/MockUserRepository.ts` | Users |
| `src/db/MarketCacheRepository.ts`, `src/db/NeonMarketCacheRepository.ts`, `src/db/MockMarketCacheRepository.ts` | The 4 cache tables |
| `src/services/RateLimiter.ts` | `RateLimiter` interface (`tryTake`, `block`, optional `retryAfterSec`), `PostgresRateLimiter`, `MockRateLimiter`, bucket policies |
| `src/services/AuthService.ts` | Register (with buckets) and delete account |
| `src/services/MarketDataService.ts` | Quotes, history, search, profile: cache, providers, coalescing, stale fallback |
| `src/domain/marketCalendar.ts` | ET calendar: `etParts`, `etDateString`, `isMarketOpen`, `nextOpen`, `nextClose`, `lastSessionOpen`, `isRegularSessionTime` |
| `src/domain/ttl.ts` | `expiresAt(kind, fetchedAt)` |
| `src/providers/types.ts` | Provider interfaces, value types, `ProviderError` |
| `src/providers/http.ts` | `FetchLike`, `getJson` (timeout and error mapping) |
| `src/providers/finnhub.ts`, `src/providers/tiingo.ts`, `src/providers/alpaca.ts` | Adapters |
| `src/schemas/common.ts`, `src/schemas/auth.ts`, `src/schemas/market.ts` | TypeBox schemas |
| `src/routes/health.ts`, `src/routes/api/auth.ts`, `src/routes/api/market.ts` | Thin route plugins |
| `test/support/app.ts`, `test/support/pglite.ts`, `test/support/fakeFetch.ts`, `test/support/market.ts`, `test/support/fixtures/*.json` | Test helpers and fixtures. `buildTestApp(overrides)` returns `{ app, container, user, authHeaders }`; `createTestDb()` returns `{ db, sql, close }` with migrations applied. |
| `test/**/*.test.ts` | Tests that mirror `src/` |
| `README.md` | How to run, test, migrate and deploy |

### iOS (`/Users/ckai/code/Wait/Wait`, Chunks 9–12)

| Path | Change |
|---|---|
| `Packages/WaitKit/Package.swift` | Add the `APIClient` target and `APIClientTests`. Add `APIClient` to the dependencies of `MarketDataClient` and `SettingsFeature`. |
| `Packages/WaitKit/Sources/APIClient/WireDates.swift` | ISO 8601 with milliseconds, plus a JSON encoder and decoder |
| `Packages/WaitKit/Sources/APIClient/APIError.swift` | `APIError`, and decoding of the error envelope |
| `Packages/WaitKit/Sources/APIClient/KeychainClient.swift` | `KeychainClient` (live and in-memory) |
| `Packages/WaitKit/Sources/APIClient/IdentityClient.swift` | `IdentityClient` (get-or-create the synchronizable UUID) |
| `Packages/WaitKit/Sources/APIClient/HTTPSession.swift` | `APIRequest`; `HTTPSession` actor (register on first use, re-register on 401) |
| `Packages/WaitKit/Sources/APIClient/DTOs/AuthDTOs.swift`, `DTOs/MarketDTOs.swift` | Wire DTOs |
| `Packages/WaitKit/Sources/APIClient/APIClient.swift` | `@DependencyClient APIClient` plus its live value |
| `Packages/WaitKit/Sources/MarketDataClient/Backend/BackendMarketData.swift` | `MarketDataClient.backend(_:)`, mapping DTOs to Domain types |
| `Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift` | Live value becomes `.cached(.backend(...))` |
| `Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsFeature.swift`, `StatsSection.swift`, `StockDetailsView.swift` | Profile and fundamentals |
| `Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`, `AccountSection.swift`, `SettingsView.swift` | Account section, Delete Account, attribution |
| `Packages/WaitKit/Sources/MarketDataClient/TwelveData/` | Deleted |
| `Config/Base.xcconfig`, `Config/Secrets.example.xcconfig`, `Wait/Info.plist` | `WAIT_API_BASE_URL`; `TWELVE_DATA_API_KEY` removed |
| `/Users/ckai/code/Wait/scripts/check-client-has-no-provider-keys.sh` | Grep guard |
| `/Users/ckai/code/Wait/CLAUDE.md`, `Packages/WaitKit/README.md` | Docs |

---

## Chunk 1: Server scaffold

### Task 1: Package, TypeScript config, vitest, and `loadConfig`

**Files:**
- Create: `server/package.json`, `server/tsconfig.json`, `server/tsconfig.test.json`, `server/vitest.config.ts`, `server/.gitignore`
- Create: `server/src/config.ts`
- Test: `server/test/config.test.ts`

- [x] **Step 1: Create the package skeleton**

```bash
mkdir -p /Users/ckai/code/Wait/server/{src,test,migrations,scripts}
cd /Users/ckai/code/Wait/server
```

Create `server/package.json`:
```json
{
  "name": "wait-server",
  "version": "0.1.0",
  "private": true,
  "description": "Wait backend: anonymous auth, market-data proxy, watchlist sync, daily ladder alerts",
  "type": "module",
  "engines": { "node": ">=22" },
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc -p tsconfig.json",
    "typecheck": "tsc -p tsconfig.test.json --noEmit",
    "test": "vitest run",
    "test:neon": "TEST_DB=neon vitest run --no-file-parallelism test/db test/services",
    "migrate": "tsx scripts/migrate.ts"
  },
  "dependencies": {
    "@fastify/jwt": "^10.0.0",
    "@fastify/type-provider-typebox": "^6.1.0",
    "@neondatabase/serverless": "^1.0.2",
    "@sinclair/typebox": "^0.34.49",
    "fastify": "^5.7.1",
    "fastify-plugin": "^5.1.0",
    "zod": "^3.25.76"
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.3.0",
    "@types/node": "^22.15.0",
    "dotenv": "^17.2.3",
    "tsx": "^4.21.0",
    "typescript": "^5.9.3",
    "vitest": "^4.1.1"
  }
}
```

Create `server/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "types": ["node"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "noUncheckedIndexedAccess": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

Create `server/tsconfig.test.json`:
```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "rootDir": ".",
    "noEmit": true
  },
  "include": ["src/**/*", "test/**/*", "scripts/**/*", "vitest.config.ts"]
}
```

Create `server/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
})
```

Create `server/.gitignore`:
```gitignore
node_modules/
dist/
.env
.env*.local
.vercel/
coverage/
```

- [x] **Step 2: Install dependencies**

Run: `cd /Users/ckai/code/Wait/server && npm install`
Expected: `added N packages` with no `ERR!` lines, and `package-lock.json` is created. If `@electric-sql/pglite@^0.3.0` doesn't resolve, run `npm view @electric-sql/pglite version` and pin `^<major.minor>.0` of the version it prints.

- [x] **Step 3: Write the failing config test**

Create `server/test/config.test.ts`:
```ts
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
```

- [x] **Step 4: Run the test to verify it fails**

Run: `npx vitest run test/config.test.ts`
Expected: FAIL with `Failed to load url ../src/config.js` (or `Cannot find module`).

- [x] **Step 5: Implement `loadConfig`**

Create `server/src/config.ts`:
```ts
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
  FINNHUB_API_KEY: z.string().min(1),
  TIINGO_API_KEY: z.string().min(1),
  ALPACA_KEY_ID: z.string().min(1),
  ALPACA_SECRET_KEY: z.string().min(1),
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
```

- [x] **Step 6: Run the test to verify it passes**

Run: `npx vitest run test/config.test.ts && npm run typecheck`
Expected: `5 passed`, and `tsc` prints nothing (exit 0).

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/package.json server/package-lock.json server/tsconfig.json server/tsconfig.test.json server/vitest.config.ts server/.gitignore server/src/config.ts server/test/config.test.ts
git commit -m "feat(server): scaffold wait-server package with fail-fast config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Library helpers: errors, safeEqual, clock, time, decimal, concurrency

**Files:**
- Create: `server/src/lib/errors.ts`, `server/src/lib/safeEqual.ts`, `server/src/lib/clock.ts`, `server/src/lib/time.ts`, `server/src/lib/decimal.ts`, `server/src/lib/concurrency.ts`
- Test: `server/test/lib/lib.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/lib/lib.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { AppError } from "../../src/lib/errors.js"
import { safeEqual } from "../../src/lib/safeEqual.js"
import { fixedClock } from "../../src/lib/clock.js"
import { asDate, asNullableString, asNumber } from "../../src/lib/time.js"
import { toDecimalString } from "../../src/lib/decimal.js"
import { mapLimit } from "../../src/lib/concurrency.js"

describe("AppError", () => {
  it("carries code, status and optional Retry-After seconds", () => {
    const error = new AppError("UPSTREAM_RATE_LIMITED", "Try later", 503, 30)
    expect(error).toBeInstanceOf(Error)
    expect([error.code, error.statusCode, error.retryAfterSec]).toEqual(["UPSTREAM_RATE_LIMITED", 503, 30])
  })
})

describe("safeEqual", () => {
  it("compares strings of any length without throwing", () => {
    expect(safeEqual("secret", "secret")).toBe(true)
    expect(safeEqual("secret", "secreT")).toBe(false)
    expect(safeEqual("short", "a-much-longer-value")).toBe(false)
  })
})

describe("fixedClock", () => {
  it("returns copies of a settable, advanceable instant", () => {
    const clock = fixedClock(new Date("2026-11-20T15:00:00.000Z"))
    clock.advance(1_500)
    expect(clock.now().toISOString()).toBe("2026-11-20T15:00:01.500Z")
    clock.set(new Date("2026-01-01T00:00:00.000Z"))
    const a = clock.now()
    a.setUTCFullYear(1999)
    expect(clock.now().toISOString()).toBe("2026-01-01T00:00:00.000Z")
  })
})

describe("row helpers", () => {
  it("accept driver-specific shapes", () => {
    expect(asDate("2026-11-20T15:00:00.000Z").toISOString()).toBe("2026-11-20T15:00:00.000Z")
    expect(asDate(new Date(0)).getTime()).toBe(0)
    expect(asNumber("42")).toBe(42)
    expect(asNumber(42n)).toBe(42)
    expect(asNullableString(null)).toBeNull()
    expect(asNullableString(12.5)).toBe("12.5")
  })
})

describe("toDecimalString", () => {
  it("removes float artifacts and trailing zeros", () => {
    expect(toDecimalString(172.1)).toBe("172.1")
    expect(toDecimalString(0.1 + 0.2)).toBe("0.3")
    expect(toDecimalString(3_500_000_000_000)).toBe("3500000000000")
    expect(toDecimalString(0.0075)).toBe("0.0075")
  })
})

describe("mapLimit", () => {
  it("preserves order and never exceeds the concurrency limit", async () => {
    let active = 0
    let peak = 0
    const result = await mapLimit([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
      active += 1
      peak = Math.max(peak, active)
      await new Promise((resolve) => setTimeout(resolve, 5))
      active -= 1
      return n * 10
    })
    expect(result).toEqual([10, 20, 30, 40, 50, 60, 70])
    expect(peak).toBeLessThanOrEqual(3)
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/lib/lib.test.ts`
Expected: FAIL with `Failed to load url ../../src/lib/errors.js`.

- [x] **Step 3: Implement the helpers**

Create `server/src/lib/errors.ts`:
```ts
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
```

Create `server/src/lib/safeEqual.ts`:
```ts
import { createHash, timingSafeEqual } from "node:crypto"

/** Constant-time comparison; hashing first makes unequal lengths safe for timingSafeEqual. */
export function safeEqual(a: string, b: string): boolean {
  const left = createHash("sha256").update(a).digest()
  const right = createHash("sha256").update(b).digest()
  return timingSafeEqual(left, right)
}
```

Create `server/src/lib/clock.ts`:
```ts
export interface Clock {
  now(): Date
}

export const systemClock: Clock = { now: () => new Date() }

export interface FixedClock extends Clock {
  set(date: Date): void
  advance(ms: number): void
}

export function fixedClock(start: Date): FixedClock {
  let current = start.getTime()
  return {
    now: () => new Date(current),
    set: (date) => { current = date.getTime() },
    advance: (ms) => { current += ms },
  }
}
```

Create `server/src/lib/time.ts`:
```ts
/** Neon returns timestamptz as Date or string depending on driver path; PGlite returns Date. */
export function asDate(value: unknown): Date {
  if (value instanceof Date) return new Date(value.getTime())
  if (typeof value === "string" || typeof value === "number") return new Date(value)
  throw new TypeError(`Expected a timestamp, got ${typeof value}`)
}

export function asNullableDate(value: unknown): Date | null {
  return value === null || value === undefined ? null : asDate(value)
}

/** BIGINT/NUMERIC come back as string (Neon) or number/bigint (PGlite). */
export function asNumber(value: unknown): number {
  if (typeof value === "number") return value
  if (typeof value === "bigint") return Number(value)
  if (typeof value === "string") return Number(value)
  throw new TypeError(`Expected a number, got ${typeof value}`)
}

export function asNullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value)
}
```

Create `server/src/lib/decimal.ts`:
```ts
/** Wire prices are decimal strings (overview D20). Rounds to `scale` places and drops float noise. */
export function toDecimalString(value: number, scale = 6): string {
  if (!Number.isFinite(value)) throw new RangeError(`Not a finite number: ${value}`)
  return String(Number(value.toFixed(scale)))
}

export function nullableDecimal(value: number | null | undefined, scale = 6): string | null {
  return value === null || value === undefined || !Number.isFinite(value) ? null : toDecimalString(value, scale)
}
```

Create `server/src/lib/concurrency.ts`:
```ts
/** Runs `fn` over `items` with at most `limit` in flight; results keep input order. */
export async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length)
  let next = 0
  const worker = async () => {
    while (next < items.length) {
      const index = next
      next += 1
      results[index] = await fn(items[index] as T, index)
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
  return results
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/lib/lib.test.ts && npm run typecheck`
Expected: `6 passed`, and typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/lib server/test/lib
git commit -m "feat(server): add error, clock, timing-safe compare and row helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: `buildApp`, logger, container, error handling, `/health`

**Files:**
- Create: `server/src/lib/logger.ts`, `server/src/app.ts`, `server/src/container.ts`, `server/src/routes/health.ts`, `server/src/schemas/common.ts`
- Create: `server/test/support/app.ts`
- Test: `server/test/app.test.ts`

- [x] **Step 1: Add pino at the version Fastify already uses**

The app and every service share one pino logger, which is passed to Fastify as `loggerInstance`. Pin the same range Fastify depends on, so there's only one copy of pino and its types.

Run:
```bash
cd /Users/ckai/code/Wait/server
npm install "pino@$(node -p "JSON.parse(require('fs').readFileSync('node_modules/fastify/package.json','utf8')).dependencies.pino")"
npm ls pino
```
Expected: `package.json` now lists `pino` with the same range as Fastify (for example `^9.x`). `npm ls pino` shows a single deduped version.

- [x] **Step 2: Write the failing tests**

Create `server/test/support/app.ts`:
```ts
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
```

Create `server/test/app.test.ts`:
```ts
import { Type } from "@sinclair/typebox"
import { afterEach, describe, expect, it } from "vitest"
import { AppError } from "../src/lib/errors.js"
import { createLogger } from "../src/lib/logger.js"
import { buildTestApp } from "./support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

describe("buildApp", () => {
  it("serves /health with the container clock and security headers", async () => {
    app = (await buildTestApp()).app
    const response = await app.inject({ method: "GET", url: "/health" })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ status: "ok", timestamp: "2026-11-20T15:00:00.000Z" })
    expect(response.headers["x-content-type-options"]).toBe("nosniff")
  })

  it("returns the error envelope for unknown routes", async () => {
    app = (await buildTestApp()).app
    const response = await app.inject({ method: "GET", url: "/nope" })
    expect(response.statusCode).toBe(404)
    expect(response.json()).toEqual({ error: { code: "NOT_FOUND", message: "The requested resource was not found" } })
  })

  it("maps AppError to its status and sets Retry-After", async () => {
    app = (await buildTestApp()).app
    app.get("/boom", async () => {
      throw new AppError("UPSTREAM_RATE_LIMITED", "Slow down", 503, 30)
    })
    const response = await app.inject({ method: "GET", url: "/boom" })
    expect(response.statusCode).toBe(503)
    expect(response.headers["retry-after"]).toBe("30")
    expect(response.json()).toEqual({ error: { code: "UPSTREAM_RATE_LIMITED", message: "Slow down" } })
  })

  it("maps schema validation failures to VALIDATION_ERROR", async () => {
    app = (await buildTestApp()).app
    app.post("/echo", { schema: { body: Type.Object({ n: Type.Integer() }) } }, async (request) => request.body)
    const response = await app.inject({ method: "POST", url: "/echo", payload: { n: "not-a-number" } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
  })

  it("keeps a nullable body field null (no Ajv coercion)", async () => {
    app = (await buildTestApp()).app
    // Deliberately string-first: with Fastify's default coercion, Ajv would turn null into "" here.
    // Production schemas are null-first (overview §8.1); this test guards the ajv option itself.
    app.post("/nullable", {
      schema: { body: Type.Object({ cursor: Type.Union([Type.String(), Type.Null()]) }, { additionalProperties: false }) },
    }, async (request) => ({ isNull: request.body.cursor === null }))
    const response = await app.inject({ method: "POST", url: "/nullable", payload: { cursor: null } })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ isNull: true })
  })

  it("rejects unknown body fields instead of stripping them", async () => {
    app = (await buildTestApp()).app
    app.post("/strict", {
      schema: { body: Type.Object({ cursor: Type.Union([Type.Null(), Type.String()]) }, { additionalProperties: false }) },
    }, async () => ({ ok: true }))
    const response = await app.inject({ method: "POST", url: "/strict", payload: { cursor: null, surprise: 1 } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
  })

  it("hides unexpected error messages behind INTERNAL_ERROR", async () => {
    app = (await buildTestApp()).app
    app.get("/crash", async () => {
      throw new Error("database password is hunter2")
    })
    const response = await app.inject({ method: "GET", url: "/crash" })
    expect(response.statusCode).toBe(500)
    expect(response.json()).toEqual({ error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred" } })
  })

  it("redacts authorization headers and tokens in logs", async () => {
    const lines: string[] = []
    const logger = createLogger("info", { write: (line: string) => { lines.push(line) } })
    app = (await buildTestApp({ logger })).app
    app.get("/probe", async (request) => {
      request.log.info({ headers: { authorization: "Bearer secret-123" }, device: { token: "abc-token" } }, "probe")
      return { ok: true }
    })
    await app.inject({ method: "GET", url: "/probe" })
    const probe = lines.find((line) => line.includes('"msg":"probe"'))
    expect(probe).toContain("[redacted]")
    expect(probe).not.toContain("secret-123")
    expect(probe).not.toContain("abc-token")
  })
})
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/app.test.ts`
Expected: FAIL with `Failed to load url ../../src/app.js` (or `../src/lib/logger.js`).

- [x] **Step 4: Implement the logger, schemas, container, health route and app**

Create `server/src/lib/logger.ts`:
```ts
import type { FastifyBaseLogger } from "fastify"
import { pino, type DestinationStream } from "pino"
import type { LogLevel } from "../config.js"

/** Never log bearer tokens or device tokens (Resignal gap, overview §8.1). */
export const REDACT_PATHS = ["req.headers.authorization", "headers.authorization", "*.token", "*.deviceToken"]

/** The single pino logger behind Fastify (`loggerInstance`) and every service. */
export function createLogger(level: LogLevel, stream?: DestinationStream): FastifyBaseLogger {
  const options = { level, redact: { paths: REDACT_PATHS, censor: "[redacted]" } }
  return stream ? pino(options, stream) : pino(options)
}
```

Create `server/src/schemas/common.ts`:
```ts
import { Type, type Static } from "@sinclair/typebox"

export const ErrorResponseSchema = Type.Object({
  error: Type.Object({ code: Type.String(), message: Type.String() }),
})
export type ErrorResponse = Static<typeof ErrorResponseSchema>

/** US tickers like AAPL, BRK.B, BF-B (overview §8.4). */
export const SYMBOL_PATTERN = "^[A-Z]{1,5}([.-][A-Z]{1,2})?$"
export const SYMBOL_REGEX = new RegExp(SYMBOL_PATTERN)
export const SymbolSchema = Type.String({ pattern: SYMBOL_PATTERN })
```

Create `server/src/container.ts`:
```ts
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
```

Create `server/src/routes/health.ts`:
```ts
import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import { Type } from "@sinclair/typebox"
import type { RouteOptions } from "../container.js"

const HealthResponseSchema = Type.Object({ status: Type.Literal("ok"), timestamp: Type.String() })

const healthRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  app.get("/health", { schema: { response: { 200: HealthResponseSchema } } }, async () => ({
    status: "ok" as const,
    timestamp: container.clock.now().toISOString(),
  }))
}

export default healthRoutes
```

Create `server/src/app.ts`:
```ts
import Fastify, { type FastifyError } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { Config } from "./config.js"
import type { Container } from "./container.js"
import { AppError, sendAppError, sendError } from "./lib/errors.js"
import healthRoutes from "./routes/health.js"

export interface BuildAppOptions {
  config: Config
  container: Container
}

export async function buildApp({ config, container }: BuildAppOptions) {
  const app = Fastify({
    loggerInstance: container.logger,
    bodyLimit: 1024 * 1024,
    // Overview §8.1 "Request validation (Ajv)": Fastify's defaults coerce `null` to "" inside
    // nullable unions and silently strip unknown fields. Validate exactly what the client sent.
    ajv: { customOptions: { coerceTypes: false, removeAdditional: false } },
  }).withTypeProvider<TypeBoxTypeProvider>()

  app.addHook("onSend", async (_request, reply) => {
    reply.header("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
    reply.header("X-Content-Type-Options", "nosniff")
    reply.header("X-Frame-Options", "DENY")
    reply.header("Referrer-Policy", "no-referrer")
  })

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (error instanceof AppError) return sendAppError(reply, error)
    if (error.validation) return sendError(reply, 400, "VALIDATION_ERROR", error.message)
    if (typeof error.statusCode === "number" && error.statusCode >= 400 && error.statusCode < 500) {
      return sendError(reply, error.statusCode, "INVALID_INPUT", error.message)
    }
    request.log.error({ err: error }, "unhandled_error")
    return sendError(reply, 500, "INTERNAL_ERROR", "An unexpected error occurred")
  })

  app.setNotFoundHandler((_request, reply) => sendError(reply, 404, "NOT_FOUND", "The requested resource was not found"))

  await app.register(healthRoutes, { container })

  return app
}

export type App = Awaited<ReturnType<typeof buildApp>>
```
`config` isn't used until Task 8, which registers the JWT plugin with `config.jwtSecret`.

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/app.test.ts && npm run typecheck`
Expected: `8 passed`, and typecheck exits 0.
- If the nullable test or the strict test fails, the `ajv.customOptions` line is missing.
- If the redaction test fails, `loggerInstance` isn't wired to `container.logger`.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/package.json server/package-lock.json server/src/lib/logger.ts server/src/app.ts server/src/container.ts server/src/routes/health.ts server/src/schemas/common.ts server/test/support/app.ts server/test/app.test.ts
git commit -m "feat(server): add buildApp composition, shared redacting logger, error envelope and /health

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 2: Database access and entry points

### Task 4: `Sql` adapter, migration runner, migration 001

**Files:**
- Create: `server/src/db/sql.ts`, `server/src/db/migrations.ts`, `server/migrations/001_users_and_rate_limits.sql`
- Create: `server/test/support/pglite.ts`
- Test: `server/test/db/sql.test.ts`, `server/test/db/migrations.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/db/sql.test.ts`:
```ts
import { PGlite } from "@electric-sql/pglite"
import { afterEach, describe, expect, it } from "vitest"
import { pgliteSql, toParameterized } from "../../src/db/sql.js"

const tag = (strings: TemplateStringsArray, ...values: unknown[]) => toParameterized(strings, values)
let db: PGlite | undefined

afterEach(async () => {
  await db?.close()
  db = undefined
})

describe("toParameterized", () => {
  it("numbers interpolations as $1..$n", () => {
    expect(tag`SELECT ${1}::int + ${2}::int AS total WHERE ${"x"} = ${"x"}`).toEqual({
      text: "SELECT $1::int + $2::int AS total WHERE $3 = $4",
      values: [1, 2, "x", "x"],
    })
  })
})

describe("pgliteSql", () => {
  it("runs a parameterized tagged query against PGlite", async () => {
    db = new PGlite()
    const sql = pgliteSql(db)
    const rows = await sql`SELECT ${20}::int + ${22}::int AS total, ${JSON.stringify(["A", "B"])}::jsonb AS list`
    expect(rows).toEqual([{ total: 42, list: ["A", "B"] }])
  })
})
```

Create `server/test/db/migrations.test.ts`:
```ts
import { mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import { PGlite } from "@electric-sql/pglite"
import { afterEach, describe, expect, it } from "vitest"
import { applyMigrations, readMigrationFiles } from "../../src/db/migrations.js"
import { MIGRATIONS_DIR, pgliteExecutor } from "../support/pglite.js"

let db: PGlite | undefined

afterEach(async () => {
  await db?.close()
  db = undefined
})

describe("readMigrationFiles", () => {
  it("reads NNN_name.sql files in version order", async () => {
    const files = await readMigrationFiles(MIGRATIONS_DIR)
    expect(files[0]).toMatchObject({ version: 1, name: "users_and_rate_limits" })
    expect(files.map((f) => f.version)).toEqual([...files.map((f) => f.version)].sort((a, b) => a - b))
  })

  it("rejects badly named files", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "wait-migrations-"))
    await writeFile(path.join(dir, "1_bad.sql"), "SELECT 1;")
    await expect(readMigrationFiles(dir)).rejects.toThrow(/001_name\.sql/)
  })
})

describe("applyMigrations", () => {
  it("applies every file once and is a no-op on the second run", async () => {
    db = new PGlite()
    const files = await readMigrationFiles(MIGRATIONS_DIR)
    const first = await applyMigrations(pgliteExecutor(db), files)
    expect(first).toEqual({ applied: files.map((f) => f.version), skipped: [] })
    const tables = await db.query<{ users: string | null; buckets: string | null }>(
      "SELECT to_regclass('public.users')::text AS users, to_regclass('public.rate_buckets')::text AS buckets",
    )
    expect(tables.rows[0]).toEqual({ users: "users", buckets: "rate_buckets" })

    const second = await applyMigrations(pgliteExecutor(db), files)
    expect(second).toEqual({ applied: [], skipped: files.map((f) => f.version) })
  })

  it("rolls back a failing migration and does not record it", async () => {
    db = new PGlite()
    const broken = [{ version: 900, name: "broken", sql: "CREATE TABLE half_done (id INT); SELECT * FROM missing_table;" }]
    await expect(applyMigrations(pgliteExecutor(db), broken)).rejects.toThrow(/missing_table/)
    const leftovers = await db.query<{ t: string | null }>("SELECT to_regclass('public.half_done')::text AS t")
    expect(leftovers.rows[0]?.t).toBeNull()
    const recorded = await db.query("SELECT version FROM schema_migrations WHERE version = 900")
    expect(recorded.rows).toEqual([])
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/db`
Expected: FAIL with `Failed to load url ../../src/db/sql.js` and `../support/pglite.js`.

- [x] **Step 3: Implement the `Sql` adapter**

Create `server/src/db/sql.ts`:
```ts
import { neon } from "@neondatabase/serverless"

export type Row = Record<string, unknown>

/**
 * The only database surface repositories see. Rules (overview §8.1): plain value interpolation only,
 * no `sql.unsafe`, no composed fragments, every write a single statement. Pass JSON as
 * `${JSON.stringify(value)}::jsonb` so Neon HTTP and PGlite serialize identically.
 */
export type Sql = (strings: TemplateStringsArray, ...values: unknown[]) => Promise<Row[]>

export function neonSql(databaseUrl: string): Sql {
  const query = neon(databaseUrl)
  return async (strings, ...values) => (await query(strings, ...values)) as Row[]
}

export function toParameterized(strings: TemplateStringsArray, values: unknown[]): { text: string; values: unknown[] } {
  let text = strings[0] ?? ""
  for (let i = 1; i < strings.length; i += 1) {
    text += `$${i}${strings[i] ?? ""}`
  }
  return { text, values }
}

/** Structural type so `src/` never imports the PGlite dev dependency. */
export interface QueryableDb {
  query<T>(text: string, params?: unknown[]): Promise<{ rows: T[] }>
}

export function pgliteSql(db: QueryableDb): Sql {
  return async (strings, ...values) => {
    const { text, values: params } = toParameterized(strings, values)
    return (await db.query<Row>(text, params)).rows
  }
}
```

- [x] **Step 4: Implement the migration runner and migration 001**

Create `server/src/db/migrations.ts`:
```ts
import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import type { Row } from "./sql.js"

export interface MigrationExecutor {
  query(text: string, params?: unknown[]): Promise<Row[]>
  /** Multi-statement text, no parameters (simple query protocol). */
  exec(text: string): Promise<void>
  transaction<T>(fn: (tx: MigrationExecutor) => Promise<T>): Promise<T>
}

export interface MigrationFile {
  version: number
  name: string
  sql: string
}

const FILE_PATTERN = /^(\d{3})_([a-z0-9_]+)\.sql$/

export async function readMigrationFiles(dir: string): Promise<MigrationFile[]> {
  const entries = (await readdir(dir)).filter((entry) => entry.endsWith(".sql")).sort()
  const files: MigrationFile[] = []
  for (const entry of entries) {
    const match = FILE_PATTERN.exec(entry)
    if (!match) throw new Error(`Migration file name must look like 001_name.sql: ${entry}`)
    files.push({ version: Number(match[1]), name: match[2] ?? "", sql: await readFile(path.join(dir, entry), "utf8") })
  }
  const versions = files.map((file) => file.version)
  if (new Set(versions).size !== versions.length) throw new Error(`Duplicate migration version in ${dir}`)
  return files
}

export async function applyMigrations(
  executor: MigrationExecutor,
  files: MigrationFile[],
): Promise<{ applied: number[]; skipped: number[] }> {
  await executor.exec(
    "CREATE TABLE IF NOT EXISTS schema_migrations (version INT PRIMARY KEY, name TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())",
  )
  const done = new Set((await executor.query("SELECT version FROM schema_migrations")).map((row) => Number(row.version)))
  const applied: number[] = []
  const skipped: number[] = []
  for (const file of [...files].sort((a, b) => a.version - b.version)) {
    if (done.has(file.version)) {
      skipped.push(file.version)
      continue
    }
    await executor.transaction(async (tx) => {
      await tx.exec(file.sql)
      await tx.query("INSERT INTO schema_migrations (version, name) VALUES ($1, $2)", [file.version, file.name])
    })
    applied.push(file.version)
  }
  return { applied, skipped }
}

/** Adapts a Neon `Pool` client (pg-compatible) for `scripts/migrate.ts` and `npm run test:neon`. */
export interface PoolClientLike {
  query(text: string, params?: unknown[]): Promise<{ rows: Row[] }>
}

export function poolExecutor(client: PoolClientLike): MigrationExecutor {
  const executor: MigrationExecutor = {
    query: async (text, params) => (await client.query(text, params)).rows,
    exec: async (text) => {
      await client.query(text)
    },
    transaction: async (fn) => {
      await client.query("BEGIN")
      try {
        const result = await fn(executor)
        await client.query("COMMIT")
        return result
      } catch (error) {
        await client.query("ROLLBACK")
        throw error
      }
    },
  }
  return executor
}
```

Create `server/migrations/001_users_and_rate_limits.sql`:
```sql
-- 001: anonymous users and the Postgres token-bucket table (overview §8.3)
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  anonymous_id TEXT NOT NULL,
  watchlist_version BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_anonymous_id ON users(anonymous_id);

CREATE TABLE IF NOT EXISTS rate_buckets (
  key TEXT PRIMARY KEY,
  tokens DOUBLE PRECISION NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  blocked_until TIMESTAMPTZ
);
```

- [x] **Step 5: Implement the test database helper**

Create `server/test/support/pglite.ts`:
```ts
import path from "node:path"
import { PGlite } from "@electric-sql/pglite"
import { Pool } from "@neondatabase/serverless"
import { applyMigrations, poolExecutor, readMigrationFiles, type MigrationExecutor } from "../../src/db/migrations.js"
import { neonSql, pgliteSql, type Row, type Sql } from "../../src/db/sql.js"

export const MIGRATIONS_DIR = path.resolve(import.meta.dirname, "../../migrations")

/** Raw handle for assertions: the PGlite instance, or a Neon pool adapter under `npm run test:neon`. */
export interface TestDatabase {
  query<T = Row>(text: string, params?: unknown[]): Promise<{ rows: T[] }>
  exec(text: string): Promise<unknown>
  close(): Promise<void>
}

export interface TestDb {
  db: TestDatabase
  sql: Sql
  close(): Promise<void>
}

export function pgliteExecutor(db: PGlite): MigrationExecutor {
  return {
    query: async (text, params) => (await db.query<Row>(text, params ?? [])).rows,
    exec: async (text) => {
      await db.exec(text)
    },
    transaction: (fn) =>
      db.transaction((tx) =>
        fn({
          query: async (text, params) => (await tx.query<Row>(text, params ?? [])).rows,
          exec: async (text) => {
            await tx.exec(text)
          },
          transaction: () => Promise.reject(new Error("Nested transactions are not supported")),
        }),
      ),
  }
}

/**
 * Fresh, fully migrated database per call. Default: in-process PGlite (no credentials).
 * `npm run test:neon` sets TEST_DB=neon and runs the same suites against TEST_DATABASE_URL
 * (a disposable Neon branch), truncating every table first.
 */
export async function createTestDb(): Promise<TestDb> {
  const files = await readMigrationFiles(MIGRATIONS_DIR)
  if (process.env.TEST_DB === "neon") {
    const url = process.env.TEST_DATABASE_URL
    if (!url) throw new Error("TEST_DB=neon requires TEST_DATABASE_URL (a disposable Neon branch)")
    const pool = new Pool({ connectionString: url })
    const client = await pool.connect()
    try {
      await applyMigrations(poolExecutor({ query: (text, params) => client.query(text, params) }), files)
      const tables = await client.query(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'",
      )
      const names = tables.rows.map((row: { tablename: string }) => `"${row.tablename}"`)
      if (names.length > 0) await client.query(`TRUNCATE ${names.join(", ")} CASCADE`)
    } finally {
      client.release()
    }
    const db: TestDatabase = {
      query: async <T>(text: string, params?: unknown[]) => (await pool.query(text, params)) as unknown as { rows: T[] },
      exec: (text) => pool.query(text),
      close: () => pool.end(),
    }
    return { db, sql: neonSql(url), close: () => db.close() }
  }
  const db = new PGlite()
  await applyMigrations(pgliteExecutor(db), files)
  return { db, sql: pgliteSql(db), close: () => db.close() }
}
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run test/db && npm run typecheck`
Expected: `6 passed` (2 in `sql.test.ts`, 4 in `migrations.test.ts`). Typecheck exits 0.

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/db server/migrations/001_users_and_rate_limits.sql server/test/support/pglite.ts server/test/db
git commit -m "feat(server): add Sql adapter, working migration runner and migration 001

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Entry points, `vercel.json`, `.env.example`, migrate script

**Files:**
- Create: `server/src/server.ts`, `server/src/index.ts`, `server/scripts/migrate.ts`, `server/vercel.json`, `server/.env.example`
- Test: `server/test/server.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/server.test.ts`:
```ts
import { afterAll, describe, expect, it } from "vitest"

const env = {
  NODE_ENV: "test",
  LOG_LEVEL: "silent",
  DATABASE_URL: "postgres://test:test@localhost:5432/wait_test",
  JWT_SECRET: "test-secret-test-secret-test-secret-0001",
  FINNHUB_API_KEY: "finnhub-test-key",
  TIINGO_API_KEY: "tiingo-test-key",
  ALPACA_KEY_ID: "alpaca-test-id",
  ALPACA_SECRET_KEY: "alpaca-test-secret",
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
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/server.test.ts`
Expected: FAIL with `Failed to load url ../src/server.js`.

- [x] **Step 3: Implement the entry points and deploy files**

Create `server/src/server.ts`:
```ts
import type { IncomingMessage, ServerResponse } from "node:http"
import { buildApp } from "./app.js"
import { loadConfig } from "./config.js"
import { createContainer } from "./container.js"

// Fail fast at cold start: a missing env var crashes the function with the variable's name.
const config = loadConfig(process.env)
const app = await buildApp({ config, container: createContainer(config) })

export { app }

export default async (req: IncomingMessage, res: ServerResponse) => {
  await app.ready()
  app.server.emit("request", req, res)
}
```

Create `server/src/index.ts`:
```ts
import dotenv from "dotenv"

dotenv.config({ path: ".env.development.local" })
dotenv.config({ path: ".env.local", override: true })

const { app } = await import("./server.js")
const port = Number(process.env.PORT) || 3000

try {
  await app.listen({ port, host: "0.0.0.0" })
} catch (error) {
  app.log.error(error)
  process.exit(1)
}
```

Create `server/scripts/migrate.ts`:
```ts
import path from "node:path"
import dotenv from "dotenv"
import { Pool } from "@neondatabase/serverless"
import { applyMigrations, poolExecutor, readMigrationFiles } from "../src/db/migrations.js"

// A URL set in the shell (e.g. a disposable Neon branch) wins over the files loaded below.
const fromShell = process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL
dotenv.config({ path: ".env.development.local" })
dotenv.config({ path: ".env.local", override: true })

// Prefer the direct (unpooled) URL for DDL when the Vercel ↔ Neon integration provides it.
const url = fromShell ?? process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL
if (!url) {
  console.error("DATABASE_URL is not set. Run `vercel env pull .env.local --environment=production` inside server/ first.")
  process.exit(1)
}
console.log(`migrating ${new URL(url).host}${fromShell ? " (from the shell)" : ""}`)

const pool = new Pool({ connectionString: url })
const client = await pool.connect()
try {
  const files = await readMigrationFiles(path.resolve(import.meta.dirname, "../migrations"))
  const { applied, skipped } = await applyMigrations(poolExecutor({ query: (text, params) => client.query(text, params) }), files)
  console.log(`migrations applied: [${applied.join(", ")}] skipped: [${skipped.join(", ")}]`)
} finally {
  client.release()
  await pool.end()
}
```

Create `server/vercel.json`:
```json
{
  "builds": [{ "src": "src/server.ts", "use": "@vercel/node" }],
  "routes": [
    { "src": "/api/(.*)", "dest": "src/server.ts" },
    { "src": "/health", "dest": "src/server.ts" }
  ]
}
```

Create `server/.env.example`:
```dotenv
# Copy to .env.local for local dev (or run `vercel env pull .env.local`). Never commit real values.
NODE_ENV=development
LOG_LEVEL=info
DATABASE_URL=postgres://user:password@host/db?sslmode=require
# Direct (unpooled) URL from the Vercel ↔ Neon integration; `npm run migrate` prefers it for DDL.
DATABASE_URL_UNPOOLED=postgres://user:password@host/db?sslmode=require
JWT_SECRET=replace-with-at-least-32-random-characters
FINNHUB_API_KEY=
TIINGO_API_KEY=
ALPACA_KEY_ID=
ALPACA_SECRET_KEY=
# Plan 06 adds: MASSIVE_API_KEY, MASSIVE_BASE_URL, CRON_SECRET, APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC
```

- [x] **Step 4: Run the full suite and typecheck**

Run: `npm test && npm run typecheck`
Expected: all test files pass (`Test Files  6 passed`), and typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/server.ts server/src/index.ts server/scripts/migrate.ts server/vercel.json server/.env.example server/test/server.test.ts
git commit -m "feat(server): add Vercel and local entry points, migrate script, env example

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 3: Auth

### Task 6: `UserRepository` (interface, Neon, Mock)

**Files:**
- Create: `server/src/db/types.ts`, `server/src/db/UserRepository.ts`, `server/src/db/NeonUserRepository.ts`, `server/src/db/MockUserRepository.ts`
- Test: `server/test/db/UserRepository.test.ts`

- [x] **Step 1: Write the failing contract test, which runs against both implementations**

Create `server/test/db/UserRepository.test.ts`:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { NeonUserRepository } from "../../src/db/NeonUserRepository.js"
import type { UserRepository } from "../../src/db/UserRepository.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

const ANON = "6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f"
const T0 = new Date("2026-11-20T15:00:00.000Z")
const T1 = new Date("2026-11-20T16:00:00.000Z")

const implementations: Array<[string, () => Promise<{ repo: UserRepository; close: () => Promise<void> }>]> = [
  ["NeonUserRepository (PGlite)", async () => {
    const db: TestDb = await createTestDb()
    return { repo: new NeonUserRepository(db.sql), close: db.close }
  }],
  ["MockUserRepository", async () => ({ repo: new MockUserRepository(), close: async () => {} })],
]

describe.each(implementations)("%s", (_name, make) => {
  let repo: UserRepository
  let close: () => Promise<void>

  beforeEach(async () => {
    ;({ repo, close } = await make())
  })
  afterEach(async () => {
    await close()
  })

  it("creates a user on first sight of an anonymous id", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(user).toMatchObject({ anonymousId: ANON, createdAt: T0, updatedAt: T0 })
    expect(user.id).toMatch(/^[0-9a-f-]{36}$/)
  })

  it("returns the same user on later calls and bumps updatedAt", async () => {
    const first = await repo.findOrCreateByAnonymousId(ANON, T0)
    const second = await repo.findOrCreateByAnonymousId(ANON, T1)
    expect(second.id).toBe(first.id)
    expect(second.createdAt).toEqual(T0)
    expect(second.updatedAt).toEqual(T1)
  })

  it("gets by id and returns null for unknown ids", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(await repo.getById(user.id)).toEqual(user)
    expect(await repo.getById("00000000-0000-4000-8000-000000000000")).toBeNull()
  })

  it("deletes by id and reports whether a row existed", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(await repo.deleteById(user.id)).toBe(true)
    expect(await repo.getById(user.id)).toBeNull()
    expect(await repo.deleteById(user.id)).toBe(false)
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/db/UserRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/MockUserRepository.js`.

- [x] **Step 3: Implement the types, the interface and both repositories**

Create `server/src/db/types.ts`:
```ts
export interface User {
  id: string
  anonymousId: string
  createdAt: Date
  updatedAt: Date
}
```

Create `server/src/db/UserRepository.ts`:
```ts
import type { User } from "./types.js"

export interface UserRepository {
  /** Idempotent single-statement upsert keyed by the unique anonymous id. */
  findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User>
  getById(id: string): Promise<User | null>
  /** Cascades to every user-owned row (ON DELETE CASCADE). Returns false if no row existed. */
  deleteById(id: string): Promise<boolean>
}
```

Create `server/src/db/NeonUserRepository.ts`:
```ts
import { randomUUID } from "node:crypto"
import { asDate } from "../lib/time.js"
import type { Row, Sql } from "./sql.js"
import type { User } from "./types.js"
import type { UserRepository } from "./UserRepository.js"

function mapRowToUser(row: Row): User {
  return {
    id: String(row.id),
    anonymousId: String(row.anonymous_id),
    createdAt: asDate(row.created_at),
    updatedAt: asDate(row.updated_at),
  }
}

export class NeonUserRepository implements UserRepository {
  constructor(private readonly sql: Sql) {}

  async findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User> {
    const rows = await this.sql`
      INSERT INTO users (id, anonymous_id, created_at, updated_at)
      VALUES (${randomUUID()}, ${anonymousId}, ${now}, ${now})
      ON CONFLICT (anonymous_id) DO UPDATE SET updated_at = EXCLUDED.updated_at
      RETURNING id, anonymous_id, created_at, updated_at`
    const row = rows[0]
    if (!row) throw new Error("users upsert returned no row")
    return mapRowToUser(row)
  }

  async getById(id: string): Promise<User | null> {
    const rows = await this.sql`SELECT id, anonymous_id, created_at, updated_at FROM users WHERE id = ${id}`
    return rows[0] ? mapRowToUser(rows[0]) : null
  }

  async deleteById(id: string): Promise<boolean> {
    const rows = await this.sql`DELETE FROM users WHERE id = ${id} RETURNING id`
    return rows.length > 0
  }
}
```

Create `server/src/db/MockUserRepository.ts`:
```ts
import { randomUUID } from "node:crypto"
import type { User } from "./types.js"
import type { UserRepository } from "./UserRepository.js"

export class MockUserRepository implements UserRepository {
  private readonly users = new Map<string, User>()

  clear(): void {
    this.users.clear()
  }

  seed(users: User[]): void {
    for (const user of users) this.users.set(user.id, { ...user })
  }

  async findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User> {
    const existing = [...this.users.values()].find((user) => user.anonymousId === anonymousId)
    if (existing) {
      existing.updatedAt = new Date(now.getTime())
      return { ...existing }
    }
    const user: User = { id: randomUUID(), anonymousId, createdAt: new Date(now.getTime()), updatedAt: new Date(now.getTime()) }
    this.users.set(user.id, user)
    return { ...user }
  }

  async getById(id: string): Promise<User | null> {
    const user = this.users.get(id)
    return user ? { ...user } : null
  }

  async deleteById(id: string): Promise<boolean> {
    return this.users.delete(id)
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `npx vitest run test/db/UserRepository.test.ts && npm run typecheck`
Expected: `8 passed` (4 cases × 2 implementations). Typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/db/types.ts server/src/db/UserRepository.ts server/src/db/NeonUserRepository.ts server/src/db/MockUserRepository.ts server/test/db/UserRepository.test.ts
git commit -m "feat(server): add user repository with idempotent anonymous upsert

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Postgres token bucket `RateLimiter`

**Files:**
- Create: `server/src/services/RateLimiter.ts`
- Test: `server/test/services/RateLimiter.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/services/RateLimiter.test.ts`:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { fixedClock, type FixedClock } from "../../src/lib/clock.js"
import { MockRateLimiter, PostgresRateLimiter, type BucketPolicy } from "../../src/services/RateLimiter.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

const TWO_PER_SECOND: BucketPolicy = { capacity: 2, refillPerSec: 1 }

describe("PostgresRateLimiter", () => {
  let db: TestDb
  let clock: FixedClock
  let limiter: PostgresRateLimiter

  beforeEach(async () => {
    db = await createTestDb()
    clock = fixedClock(new Date("2026-11-20T15:00:00.000Z"))
    limiter = new PostgresRateLimiter(db.sql, clock)
  })
  afterEach(async () => {
    await db.close()
  })

  it("allows up to capacity, then refills at the configured rate", async () => {
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
  })

  it("never refills above capacity", async () => {
    await limiter.tryTake("k", TWO_PER_SECOND)
    clock.advance(3_600_000)
    const results = [
      await limiter.tryTake("k", TWO_PER_SECOND),
      await limiter.tryTake("k", TWO_PER_SECOND),
      await limiter.tryTake("k", TWO_PER_SECOND),
    ]
    expect(results).toEqual([true, true, false])
  })

  it("keeps keys independent and honours cost", async () => {
    expect(await limiter.tryTake("a", TWO_PER_SECOND, 2)).toBe(true)
    expect(await limiter.tryTake("a", TWO_PER_SECOND)).toBe(false)
    expect(await limiter.tryTake("b", TWO_PER_SECOND)).toBe(true)
  })

  it("denies everything while blocked and only refills after the block ends", async () => {
    await limiter.block("k", 30)
    clock.advance(29_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000) // block over, but no tokens accrued during it
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
  })

  it("reports the remaining block as Retry-After seconds", async () => {
    expect(await limiter.retryAfterSec("k")).toBeNull()
    await limiter.block("k", 30)
    clock.advance(10_500)
    expect(await limiter.retryAfterSec("k")).toBe(20)
    clock.advance(20_000)
    expect(await limiter.retryAfterSec("k")).toBeNull()
  })
})

describe("MockRateLimiter", () => {
  it("records takes and blocks and denies listed keys", async () => {
    const limiter = new MockRateLimiter()
    limiter.denied.add("no")
    expect(await limiter.tryTake("yes", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("no", TWO_PER_SECOND)).toBe(false)
    await limiter.block("yes", 10)
    expect(await limiter.tryTake("yes", TWO_PER_SECOND)).toBe(false)
    expect(await limiter.retryAfterSec("yes")).toBe(10)
    expect(await limiter.retryAfterSec("no")).toBeNull()
    expect(limiter.takes.map((t) => t.key)).toEqual(["yes", "no", "yes"])
    expect(limiter.blocks).toEqual([{ key: "yes", seconds: 10 }])
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/services/RateLimiter.test.ts`
Expected: FAIL with `Failed to load url ../../src/services/RateLimiter.js`.

- [x] **Step 3: Implement the rate limiter**

Create `server/src/services/RateLimiter.ts`:
```ts
import type { Sql } from "../db/sql.js"
import type { Clock } from "../lib/clock.js"

export interface BucketPolicy {
  capacity: number
  refillPerSec: number
}

/** Provider budgets (overview §6.3 item 4). Keys are stable: they are rows in rate_buckets. */
export const PROVIDER_BUCKETS = {
  finnhub: { key: "provider:finnhub", policy: { capacity: 30, refillPerSec: 1 } },
  tiingoHour: { key: "provider:tiingo:hour", policy: { capacity: 50, refillPerSec: 50 / 3600 } },
  tiingoDay: { key: "provider:tiingo:day", policy: { capacity: 1000, refillPerSec: 1000 / 86_400 } },
  alpaca: { key: "provider:alpaca", policy: { capacity: 100, refillPerSec: 200 / 60 } },
  massive: { key: "provider:massive", policy: { capacity: 5, refillPerSec: 5 / 60 } },
} as const satisfies Record<string, { key: string; policy: BucketPolicy }>

export const REGISTER_IP_POLICY: BucketPolicy = { capacity: 20, refillPerSec: 20 / 60 }
export const REGISTER_ANON_POLICY: BucketPolicy = { capacity: 5, refillPerSec: 5 / 60 }

export interface RateLimiter {
  /** Atomically refills and takes `cost` tokens. False when empty or blocked. */
  tryTake(key: string, policy: BucketPolicy, cost?: number): Promise<boolean>
  /** Empties the bucket and denies every take for `seconds` (used after a provider 429). */
  block(key: string, seconds: number): Promise<void>
  /** Seconds until a block on `key` ends, or null when it isn't blocked. Optional for simple fakes. */
  retryAfterSec?(key: string): Promise<number | null>
}

export class PostgresRateLimiter implements RateLimiter {
  constructor(
    private readonly sql: Sql,
    private readonly clock: Clock,
  ) {}

  async tryTake(key: string, policy: BucketPolicy, cost = 1): Promise<boolean> {
    const now = this.clock.now()
    const rows = await this.sql`
      INSERT INTO rate_buckets AS b (key, tokens, updated_at)
      VALUES (${key}, ${policy.capacity}::float8 - ${cost}::float8, ${now}::timestamptz)
      ON CONFLICT (key) DO UPDATE SET
        tokens = LEAST(${policy.capacity}::float8,
                       b.tokens + EXTRACT(EPOCH FROM (${now}::timestamptz - b.updated_at))::float8 * ${policy.refillPerSec}::float8)
                 - ${cost}::float8,
        updated_at = ${now}::timestamptz
      WHERE (b.blocked_until IS NULL OR b.blocked_until <= ${now}::timestamptz)
        AND LEAST(${policy.capacity}::float8,
                  b.tokens + EXTRACT(EPOCH FROM (${now}::timestamptz - b.updated_at))::float8 * ${policy.refillPerSec}::float8)
            >= ${cost}::float8
      RETURNING tokens`
    return rows.length > 0
  }

  async block(key: string, seconds: number): Promise<void> {
    const until = new Date(this.clock.now().getTime() + seconds * 1000)
    // updated_at = until: the refill clock starts when the block ends, so no tokens accrue during it.
    await this.sql`
      INSERT INTO rate_buckets (key, tokens, updated_at, blocked_until)
      VALUES (${key}, 0, ${until}::timestamptz, ${until}::timestamptz)
      ON CONFLICT (key) DO UPDATE SET tokens = 0, updated_at = EXCLUDED.updated_at, blocked_until = EXCLUDED.blocked_until`
  }

  async retryAfterSec(key: string): Promise<number | null> {
    const now = this.clock.now()
    const rows = await this.sql`
      SELECT CEIL(EXTRACT(EPOCH FROM (blocked_until - ${now}::timestamptz)))::int AS seconds
      FROM rate_buckets WHERE key = ${key} AND blocked_until > ${now}::timestamptz`
    return rows[0] ? Number(rows[0].seconds) : null
  }
}

export class MockRateLimiter implements RateLimiter {
  readonly denied = new Set<string>()
  readonly takes: Array<{ key: string; cost: number }> = []
  readonly blocks: Array<{ key: string; seconds: number }> = []
  /** Blocks never expire in the mock; tests assert on `blocks` and `retryAfterSec`. */
  private readonly blocked = new Map<string, number>()

  async tryTake(key: string, _policy: BucketPolicy, cost = 1): Promise<boolean> {
    this.takes.push({ key, cost })
    return !this.denied.has(key) && !this.blocked.has(key)
  }

  async block(key: string, seconds: number): Promise<void> {
    this.blocks.push({ key, seconds })
    this.blocked.set(key, seconds)
  }

  async retryAfterSec(key: string): Promise<number | null> {
    return this.blocked.get(key) ?? null
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `npx vitest run test/services/RateLimiter.test.ts && npm run typecheck`
Expected: `6 passed`, and typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/services/RateLimiter.ts server/test/services/RateLimiter.test.ts
git commit -m "feat(server): add single-statement Postgres token bucket rate limiter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: JWT plugin, auth middleware, `AuthService`, `POST /api/auth/register`

**Files:**
- Create: `server/src/plugins/jwt.ts`, `server/src/middleware/auth.ts`, `server/src/services/AuthService.ts`, `server/src/schemas/auth.ts`, `server/src/routes/api/auth.ts`
- Modify: `server/src/container.ts` (whole file below), `server/src/app.ts` (register the JWT plugin and auth routes), `server/test/support/app.ts` (whole file below)
- Test: `server/test/routes/auth.test.ts`

- [x] **Step 1: Write the failing route tests**

Create `server/test/routes/auth.test.ts`:
```ts
import { afterEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { MockRateLimiter } from "../../src/services/RateLimiter.js"
import { buildTestApp } from "../support/app.js"

const ANON = "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"
type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup() {
  const users = new MockUserRepository()
  const rateLimiter = new MockRateLimiter()
  const built = await buildTestApp({ users, rateLimiter })
  app = built.app
  return { app: built.app, users, rateLimiter }
}

describe("POST /api/auth/register", () => {
  it("creates a user and returns a token whose payload is { userId }", async () => {
    const { app, users } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON } })
    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(app.jwt.verify<{ userId: string }>(body.token).userId).toBe(body.user.id)
    expect((await users.getById(body.user.id))?.anonymousId).toBe(ANON.toLowerCase())
  })

  it("is idempotent per anonymous id regardless of case", async () => {
    const { app } = await setup()
    const first = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON } })
    const second = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON.toLowerCase() } })
    expect(second.json().user.id).toBe(first.json().user.id)
  })

  it("rejects ids that are not UUIDs", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: "not-a-uuid" } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("INVALID_INPUT")
  })

  it("rate-limits per client IP and per anonymous id", async () => {
    const { app, rateLimiter } = await setup()
    await app.inject({ method: "POST", url: "/api/auth/register", headers: { "x-real-ip": "1.2.3.4" }, payload: { anonymousId: ANON } })
    expect(rateLimiter.takes.map((t) => t.key)).toEqual(["register:ip:1.2.3.4", `register:anon:${ANON.toLowerCase()}`])

    rateLimiter.denied.add("register:ip:1.2.3.4")
    const limited = await app.inject({ method: "POST", url: "/api/auth/register", headers: { "x-real-ip": "1.2.3.4" }, payload: { anonymousId: ANON } })
    expect(limited.statusCode).toBe(429)
    expect(limited.headers["retry-after"]).toBe("60")
    expect(limited.json().error.code).toBe("RATE_LIMITED")
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/routes/auth.test.ts`
Expected: FAIL. `POST /api/auth/register` returns 404, so `app.jwt.verify` throws `TypeError: Cannot read properties of undefined` because the JWT plugin isn't registered yet.

- [x] **Step 3: Implement the JWT plugin and auth middleware**

Create `server/src/plugins/jwt.ts`:
```ts
import type { FastifyPluginAsync } from "fastify"
import fjwt from "@fastify/jwt"
import fp from "fastify-plugin"

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { userId: string }
    user: { userId: string }
  }
}

export interface JwtPluginOptions {
  secret: string
}

const jwtPlugin: FastifyPluginAsync<JwtPluginOptions> = async (server, { secret }) => {
  await server.register(fjwt, {
    secret,
    sign: { algorithm: "HS256", expiresIn: "7d" },
    verify: { algorithms: ["HS256"] },
  })
}

// fp: `request.jwtVerify` / `server.jwt` must be visible to every route plugin.
export default fp(jwtPlugin, { name: "wait-jwt" })
```

Create `server/src/middleware/auth.ts`:
```ts
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
    let userId: string
    try {
      userId = (await request.jwtVerify<{ userId: string }>()).userId
    } catch {
      return sendError(reply, 401, "UNAUTHORIZED", "Invalid or expired token")
    }
    // Database errors propagate to the global handler (500), unlike Resignal, which reported them as 401.
    const user = await users.getById(userId)
    if (!user) return sendError(reply, 401, "USER_NOT_FOUND", "User associated with token no longer exists")
    request.authenticatedUser = user
  }
  return { authenticate }
}
```

- [x] **Step 4: Implement `AuthService`, the schemas and the route**

Create `server/src/services/AuthService.ts`:
```ts
import type { User } from "../db/types.js"
import type { UserRepository } from "../db/UserRepository.js"
import type { Clock } from "../lib/clock.js"
import { AppError } from "../lib/errors.js"
import { REGISTER_ANON_POLICY, REGISTER_IP_POLICY, type RateLimiter } from "./RateLimiter.js"

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class AuthService {
  constructor(
    private readonly users: UserRepository,
    private readonly limiter: RateLimiter,
    private readonly clock: Clock,
  ) {}

  /** Find-or-create by anonymous id (stored lowercase; iOS sends uppercase uuidString). */
  async register(anonymousId: string, clientIp: string): Promise<User> {
    if (!UUID_REGEX.test(anonymousId)) throw new AppError("INVALID_INPUT", "anonymousId must be a valid UUID", 400)
    const normalized = anonymousId.toLowerCase()
    if (!(await this.limiter.tryTake(`register:ip:${clientIp}`, REGISTER_IP_POLICY))) {
      throw new AppError("RATE_LIMITED", "Too many registration attempts, try again later", 429, 60)
    }
    if (!(await this.limiter.tryTake(`register:anon:${normalized}`, REGISTER_ANON_POLICY))) {
      throw new AppError("RATE_LIMITED", "Too many registration attempts, try again later", 429, 60)
    }
    return this.users.findOrCreateByAnonymousId(normalized, this.clock.now())
  }

  async deleteAccount(userId: string): Promise<void> {
    const deleted = await this.users.deleteById(userId)
    if (!deleted) throw new AppError("USER_NOT_FOUND", "User associated with token no longer exists", 401)
  }
}
```

Create `server/src/schemas/auth.ts`:
```ts
import { Type, type Static } from "@sinclair/typebox"

export const RegisterBodySchema = Type.Object({ anonymousId: Type.String({ minLength: 1, maxLength: 64 }) }, { additionalProperties: false })
export type RegisterBody = Static<typeof RegisterBodySchema>

export const RegisterResponseSchema = Type.Object({
  token: Type.String(),
  user: Type.Object({ id: Type.String() }),
})
```

Create `server/src/routes/api/auth.ts`:
```ts
import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { RouteOptions } from "../../container.js"
import { RegisterBodySchema, RegisterResponseSchema } from "../../schemas/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"

const authRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()

  app.post("/register", {
    schema: {
      body: RegisterBodySchema,
      response: { 200: RegisterResponseSchema, 400: ErrorResponseSchema, 429: ErrorResponseSchema, 500: ErrorResponseSchema },
    },
  }, async (request) => {
    const clientIp = (request.headers["x-real-ip"] as string | undefined) ?? request.ip
    const user = await container.auth.register(request.body.anonymousId, clientIp)
    return { token: server.jwt.sign({ userId: user.id }), user: { id: user.id } }
  })
}

export default authRoutes
```

- [x] **Step 5: Wire the container and the app**

Replace `server/src/container.ts` with:
```ts
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
```

In `server/src/app.ts`, add these imports below the existing ones:
```ts
import jwtPlugin from "./plugins/jwt.js"
import authRoutes from "./routes/api/auth.js"
```
Then replace the line `await app.register(healthRoutes, { container })` with:
```ts
  await app.register(jwtPlugin, { secret: config.jwtSecret })
  await app.register(healthRoutes, { container })
  await app.register(authRoutes, { prefix: "/api/auth", container })
```

Replace `server/test/support/app.ts` with the final helper that every later route test uses (plans 05 and 06 included):
```ts
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
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run test/routes/auth.test.ts test/app.test.ts test/server.test.ts && npm run typecheck`
Expected: all pass (`4 passed` in auth.test.ts). Typecheck exits 0. `server.test.ts` still passes because `neonSql` makes no connection until the first query.

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/plugins server/src/middleware server/src/services/AuthService.ts server/src/schemas/auth.ts server/src/routes/api/auth.ts server/src/container.ts server/src/app.ts server/test/support/app.ts server/test/routes/auth.test.ts
git commit -m "feat(server): add anonymous register with JWT and rate limits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: `DELETE /api/auth/account`

**Files:**
- Modify: `server/src/routes/api/auth.ts`
- Test: `server/test/routes/account.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/routes/account.test.ts`:
```ts
import { afterEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { buildTestApp } from "../support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup() {
  const users = new MockUserRepository()
  const built = await buildTestApp({ users })
  app = built.app
  return { app: built.app, users, user: built.user, headers: built.authHeaders() }
}

describe("DELETE /api/auth/account", () => {
  it("requires a bearer token", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "DELETE", url: "/api/auth/account" })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("rejects a token signed with another secret", async () => {
    const { app } = await setup()
    const forged = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJ4In0.c2lnbmF0dXJl"
    const response = await app.inject({ method: "DELETE", url: "/api/auth/account", headers: { authorization: `Bearer ${forged}` } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("deletes the user, then the same token reports USER_NOT_FOUND", async () => {
    const { app, users, user, headers } = await setup()
    const deleted = await app.inject({ method: "DELETE", url: "/api/auth/account", headers })
    expect(deleted.statusCode).toBe(204)
    expect(deleted.body).toBe("")
    expect(await users.getById(user.id)).toBeNull()

    const again = await app.inject({ method: "DELETE", url: "/api/auth/account", headers })
    expect(again.statusCode).toBe(401)
    expect(again.json().error.code).toBe("USER_NOT_FOUND")
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/routes/account.test.ts`
Expected: FAIL. All 3 tests get `404` / `NOT_FOUND` where they expect `401` or `204`, because the route doesn't exist yet.

- [x] **Step 3: Add the route**

In `server/src/routes/api/auth.ts`:
1. Add these imports:
```ts
import { Type } from "@sinclair/typebox"
import { buildAuthMiddleware } from "../../middleware/auth.js"
```
2. Directly after `const app = server.withTypeProvider<TypeBoxTypeProvider>()`, add:
```ts
  const { authenticate } = buildAuthMiddleware(container.users)
```
3. After the `/register` route, add:
```ts
  app.delete("/account", {
    onRequest: [authenticate],
    schema: { response: { 204: Type.Null(), 401: ErrorResponseSchema, 500: ErrorResponseSchema } },
  }, async (request, reply) => {
    await container.auth.deleteAccount(request.authenticatedUser.id)
    return reply.status(204).send(null)
  })
```
Every 204 route in these plans uses `reply.status(204).send(null)`. Calling `send()` with no argument is a TS2554 error, and Fastify sends no body on a 204 anyway.

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/routes/account.test.ts`
Expected: `3 passed`.

- [x] **Step 5: Run the whole suite and typecheck**

Run: `npm test && npm run typecheck`
Expected: every test file passes, and typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/routes/api/auth.ts server/test/routes/account.test.ts
git commit -m "feat(server): add DELETE /api/auth/account behind onRequest auth

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 4: Market core (calendar, TTLs, provider HTTP, cache repository)

### Task 10: `marketCalendar` and `ttl`

**Files:**
- Create: `server/src/domain/marketCalendar.ts`, `server/src/domain/ttl.ts`
- Test: `server/test/domain/marketCalendar.test.ts`, `server/test/domain/ttl.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/domain/marketCalendar.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { etDateString, isMarketOpen, lastSessionOpen, nextClose, nextOpen } from "../../src/domain/marketCalendar.js"

const at = (iso: string) => new Date(iso)

describe("marketCalendar (America/New_York, Mon–Fri 09:30–16:00, no holiday table)", () => {
  it("formats the ET calendar date", () => {
    expect(etDateString(at("2026-11-21T03:00:00Z"))).toBe("2026-11-20") // Fri 22:00 EST
  })

  it("knows when the regular session is open", () => {
    expect(isMarketOpen(at("2026-11-20T15:00:00Z"))).toBe(true) // Fri 10:00 EST
    expect(isMarketOpen(at("2026-11-20T14:29:00Z"))).toBe(false) // 09:29
    expect(isMarketOpen(at("2026-11-20T21:00:00Z"))).toBe(false) // 16:00 is closed
    expect(isMarketOpen(at("2026-11-21T15:00:00Z"))).toBe(false) // Saturday
  })

  it("finds the next open across a weekend", () => {
    expect(nextOpen(at("2026-11-20T21:30:00Z")).toISOString()).toBe("2026-11-23T14:30:00.000Z")
  })

  it("handles the DST start (2026-03-08)", () => {
    expect(nextOpen(at("2026-03-06T22:00:00Z")).toISOString()).toBe("2026-03-09T13:30:00.000Z")
  })

  it("handles the DST end (2026-11-01)", () => {
    expect(nextClose(at("2026-10-30T12:00:00Z")).toISOString()).toBe("2026-10-30T20:00:00.000Z")
    expect(nextClose(at("2026-10-30T20:30:00Z")).toISOString()).toBe("2026-11-02T21:00:00.000Z")
  })

  it("finds the most recent session open at or before an instant", () => {
    expect(lastSessionOpen(at("2026-11-21T15:00:00Z")).toISOString()).toBe("2026-11-20T14:30:00.000Z") // Sat → Fri
    expect(lastSessionOpen(at("2026-11-20T14:00:00Z")).toISOString()).toBe("2026-11-19T14:30:00.000Z") // Fri 09:00 → Thu
    expect(lastSessionOpen(at("2026-11-20T14:30:00Z")).toISOString()).toBe("2026-11-20T14:30:00.000Z")
  })
})
```

Create `server/test/domain/ttl.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { expiresAt } from "../../src/domain/ttl.js"

const iso = (kind: Parameters<typeof expiresAt>[0], fetched: string) => expiresAt(kind, new Date(fetched)).toISOString()

describe("server cache TTLs (overview §6.3 item 3)", () => {
  it("quotes live 3 min while open, until the next open while closed", () => {
    expect(iso("quote", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:03:00.000Z")
    expect(iso("quote", "2026-11-20T22:00:00.000Z")).toBe("2026-11-23T14:30:00.000Z")
  })

  it("intraday history lives 5 min (1D) / 15 min (1W) while open", () => {
    expect(iso("history1D", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:05:00.000Z")
    expect(iso("history1W", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:15:00.000Z")
    expect(iso("history1W", "2026-11-21T15:00:00.000Z")).toBe("2026-11-23T14:30:00.000Z")
  })

  it("daily5y refreshes two hours after the session close it belongs to", () => {
    expect(iso("daily5y", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T23:00:00.000Z") // Fri 10:00 → Fri 18:00 EST
    expect(iso("daily5y", "2026-11-20T21:30:00.000Z")).toBe("2026-11-20T23:00:00.000Z") // Fri 16:30 → same
    expect(iso("daily5y", "2026-11-21T00:00:00.000Z")).toBe("2026-11-23T23:00:00.000Z") // Fri 19:00 → Mon 18:00
  })

  it("search and profile live 7 days, metrics 1 day", () => {
    expect(iso("search", "2026-11-20T15:00:00.000Z")).toBe("2026-11-27T15:00:00.000Z")
    expect(iso("profile", "2026-11-20T15:00:00.000Z")).toBe("2026-11-27T15:00:00.000Z")
    expect(iso("metrics", "2026-11-20T15:00:00.000Z")).toBe("2026-11-21T15:00:00.000Z")
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/domain`
Expected: FAIL with `Failed to load url ../../src/domain/marketCalendar.js`.

- [x] **Step 3: Implement the calendar**

Create `server/src/domain/marketCalendar.ts`:
```ts
const ET = "America/New_York"
const OPEN_MINUTES = 9 * 60 + 30
const CLOSE_MINUTES = 16 * 60
const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }

const formatter = new Intl.DateTimeFormat("en-US", {
  timeZone: ET,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
  weekday: "short",
})

export interface EtParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
  /** 0 = Sunday … 6 = Saturday */
  weekday: number
}

interface CalendarDay {
  year: number
  month: number
  day: number
  weekday: number
}

export function etParts(at: Date): EtParts {
  const parts = Object.fromEntries(formatter.formatToParts(at).map((part) => [part.type, part.value]))
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
    weekday: WEEKDAYS[parts.weekday ?? ""] ?? 0,
  }
}

const pad = (n: number) => String(n).padStart(2, "0")

/** ET calendar date as YYYY-MM-DD (the "trading date" of an instant). */
export function etDateString(at: Date): string {
  const p = etParts(at)
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`
}

function offsetMs(at: Date): number {
  const p = etParts(at)
  const wallAsUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second)
  return wallAsUtc - Math.floor(at.getTime() / 1000) * 1000
}

/** Converts an ET wall-clock time (outside the 02:00 DST gap) to a UTC instant. */
export function etWallTimeToUtc(year: number, month: number, day: number, hour: number, minute: number): Date {
  const guess = Date.UTC(year, month - 1, day, hour, minute)
  const first = guess - offsetMs(new Date(guess))
  return new Date(guess - offsetMs(new Date(first)))
}

function addDays(day: { year: number; month: number; day: number }, n: number): CalendarDay {
  const d = new Date(Date.UTC(day.year, day.month - 1, day.day + n))
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(), weekday: d.getUTCDay() }
}

const isWeekday = (weekday: number) => weekday >= 1 && weekday <= 5
const atMinutes = (d: CalendarDay, minutes: number) => etWallTimeToUtc(d.year, d.month, d.day, Math.floor(minutes / 60), minutes % 60)

export function isMarketOpen(at: Date): boolean {
  const p = etParts(at)
  if (!isWeekday(p.weekday)) return false
  const minutes = p.hour * 60 + p.minute
  return minutes >= OPEN_MINUTES && minutes < CLOSE_MINUTES
}

/** Bar start times inside the regular session (Alpaca returns extended hours too). */
export const isRegularSessionTime = isMarketOpen

function scan(from: Date, direction: 1 | -1, minutes: number, accept: (candidate: Date) => boolean): Date {
  const start = etParts(from)
  for (let k = 0; k <= 8; k += 1) {
    const day = addDays(start, direction * k)
    if (!isWeekday(day.weekday)) continue
    const candidate = atMinutes(day, minutes)
    if (accept(candidate)) return candidate
  }
  throw new Error(`No session boundary found near ${from.toISOString()}`)
}

export function nextOpen(after: Date): Date {
  return scan(after, 1, OPEN_MINUTES, (c) => c.getTime() > after.getTime())
}

export function nextClose(after: Date): Date {
  return scan(after, 1, CLOSE_MINUTES, (c) => c.getTime() > after.getTime())
}

export function lastSessionOpen(atOrBefore: Date): Date {
  return scan(atOrBefore, -1, OPEN_MINUTES, (c) => c.getTime() <= atOrBefore.getTime())
}
```

- [x] **Step 4: Implement the TTLs**

Create `server/src/domain/ttl.ts`:
```ts
import { isMarketOpen, nextClose, nextOpen } from "./marketCalendar.js"

export type CacheKind = "quote" | "history1D" | "history1W" | "daily5y" | "search" | "profile" | "metrics"

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const plus = (date: Date, ms: number) => new Date(date.getTime() + ms)

/** When a cached value fetched at `fetchedAt` stops being fresh (overview §6.3 item 3). */
export function expiresAt(kind: CacheKind, fetchedAt: Date): Date {
  const open = isMarketOpen(fetchedAt)
  switch (kind) {
    case "quote":
      return open ? plus(fetchedAt, 3 * MINUTE) : nextOpen(fetchedAt)
    case "history1D":
      return open ? plus(fetchedAt, 5 * MINUTE) : nextOpen(fetchedAt)
    case "history1W":
      return open ? plus(fetchedAt, 15 * MINUTE) : nextOpen(fetchedAt)
    case "daily5y":
      // "Next close + 2 h", measured so a fetch at 16:30 still refreshes at 18:00 the same day
      // (end-of-day bars publish shortly after the close).
      return plus(nextClose(plus(fetchedAt, -2 * HOUR)), 2 * HOUR)
    case "search":
    case "profile":
      return plus(fetchedAt, 7 * DAY)
    case "metrics":
      return plus(fetchedAt, DAY)
  }
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/domain && npm run typecheck`
Expected: `10 passed` (6 calendar, 4 ttl). Typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/domain server/test/domain
git commit -m "feat(server): add ET market calendar and cache TTL rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Provider types and `getJson`

**Files:**
- Create: `server/src/providers/types.ts`, `server/src/providers/http.ts`
- Create: `server/test/support/fakeFetch.ts`
- Test: `server/test/providers/http.test.ts`

- [x] **Step 1: Write the fake fetch helper**

Create `server/test/support/fakeFetch.ts`:
```ts
import { readFileSync } from "node:fs"
import path from "node:path"
import type { FetchLike } from "../../src/providers/http.js"

export interface FakeRoute {
  match: (url: URL) => boolean
  respond: (url: URL, init?: RequestInit) => Response | Promise<Response>
}

export interface FakeCall {
  url: URL
  init?: RequestInit
}

/** Records every call; unmatched URLs return HTTP 500 so tests fail loudly. */
export function fakeFetch(routes: FakeRoute[]): { fetch: FetchLike; calls: FakeCall[] } {
  const calls: FakeCall[] = []
  const impl: FetchLike = async (url, init) => {
    const parsed = new URL(url)
    calls.push({ url: parsed, init })
    const route = routes.find((r) => r.match(parsed))
    if (!route) return new Response(JSON.stringify({ error: `no fake route for ${parsed.pathname}` }), { status: 500 })
    return route.respond(parsed, init)
  }
  return { fetch: impl, calls }
}

export const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" }, ...init })

export function fixture(name: string): unknown {
  return JSON.parse(readFileSync(path.resolve(import.meta.dirname, "fixtures", name), "utf8"))
}

export function headerOf(init: RequestInit | undefined, name: string): string | null {
  return new Headers(init?.headers).get(name)
}
```

- [x] **Step 2: Write the failing tests**

Create `server/test/providers/http.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { getJson, parseRetryAfter } from "../../src/providers/http.js"
import { ProviderError } from "../../src/providers/types.js"
import { fakeFetch, headerOf, json } from "../support/fakeFetch.js"

const always = (response: () => Response) => fakeFetch([{ match: () => true, respond: response }])

async function errorOf(promise: Promise<unknown>): Promise<ProviderError> {
  try {
    await promise
  } catch (error) {
    if (error instanceof ProviderError) return error
    throw error
  }
  throw new Error("expected a ProviderError")
}

describe("getJson", () => {
  it("parses JSON and sends the provider headers", async () => {
    const { fetch, calls } = always(() => json({ ok: true }))
    expect(await getJson(fetch, "https://example.test/x", { provider: "finnhub", headers: { "X-Key": "k" } })).toEqual({ ok: true })
    expect(headerOf(calls[0]?.init, "x-key")).toBe("k")
    expect(headerOf(calls[0]?.init, "accept")).toBe("application/json")
  })

  it("maps 429 to rate_limited with Retry-After seconds", async () => {
    const { fetch } = always(() => new Response("{}", { status: 429, headers: { "retry-after": "12" } }))
    const error = await errorOf(getJson(fetch, "https://example.test/x", { provider: "tiingo" }))
    expect([error.provider, error.kind, error.retryAfterSec]).toEqual(["tiingo", "rate_limited", 12])
  })

  it("maps 404, 5xx, bad JSON and timeouts", async () => {
    expect((await errorOf(getJson(always(() => new Response("{}", { status: 404 })).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("not_found")
    expect((await errorOf(getJson(always(() => new Response("{}", { status: 503 })).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("upstream")
    expect((await errorOf(getJson(always(() => new Response("<html>")).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("bad_response")
    const timeout = async () => {
      throw Object.assign(new Error("The operation timed out"), { name: "TimeoutError" })
    }
    expect((await errorOf(getJson(timeout, "https://e.test", { provider: "alpaca" }))).kind).toBe("timeout")
  })
})

describe("parseRetryAfter", () => {
  it("accepts seconds and ignores garbage", () => {
    expect(parseRetryAfter("30")).toBe(30)
    expect(parseRetryAfter(null)).toBeUndefined()
    expect(parseRetryAfter("soon")).toBeUndefined()
  })
})
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/providers/http.test.ts`
Expected: FAIL with `Failed to load url ../../src/providers/http.js`.

- [x] **Step 4: Implement the provider types and HTTP helper**

Create `server/src/providers/types.ts`:
```ts
export type ProviderName = "finnhub" | "tiingo" | "alpaca" | "massive"

/** Prices are decimal strings (overview D20); times are ISO 8601 UTC. */
export interface ProviderQuote {
  symbol: string
  price: string
  previousClose: string | null
  open: string | null
  high: string | null
  low: string | null
  change: string | null
  changePercent: number | null
  asOf: string
}

export interface SymbolMatch {
  symbol: string
  name: string
  exchange: string | null
  type: string
}

export interface ProviderProfile {
  symbol: string
  name: string | null
  exchange: string | null
  industry: string | null
  logoUrl: string | null
  /** USD (Finnhub reports millions; adapters convert). */
  marketCap: string | null
}

export interface ProviderMetrics {
  peRatio: number | null
  pbRatio: number | null
  dividendYield: number | null
  roe: number | null
  roa: number | null
  profitMargin: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  beta: number | null
}

/** One close per bar: `t` ISO bar start, `c` decimal close. */
export interface Bar {
  t: string
  c: string
}

export interface QuoteProvider {
  getQuote(symbol: string): Promise<ProviderQuote | null>
}

export interface SymbolSearchProvider {
  search(query: string): Promise<SymbolMatch[]>
}

export interface ProfileProvider {
  getProfile(symbol: string): Promise<ProviderProfile | null>
  getMetrics(symbol: string): Promise<ProviderMetrics | null>
}

export interface DailyBarsProvider {
  /** Inclusive ET dates YYYY-MM-DD, oldest first. */
  getDailyBars(symbol: string, from: string, to: string): Promise<Bar[]>
}

export type IntradayTimeframe = "5Min" | "30Min"

export interface IntradayBarsProvider {
  getIntradayBars(symbol: string, timeframe: IntradayTimeframe, start: Date, end: Date): Promise<Bar[]>
}

export type ProviderErrorKind = "rate_limited" | "not_found" | "upstream" | "bad_response" | "timeout"

export class ProviderError extends Error {
  constructor(
    readonly provider: ProviderName,
    readonly kind: ProviderErrorKind,
    readonly retryAfterSec?: number,
    readonly status?: number,
  ) {
    super(`${provider}:${kind}${status ? `:${status}` : ""}`)
    this.name = "ProviderError"
  }
}
```

Create `server/src/providers/http.ts`:
```ts
import { ProviderError, type ProviderName } from "./types.js"

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>

export interface GetJsonOptions {
  provider: ProviderName
  headers?: Record<string, string>
  timeoutMs?: number
}

export function parseRetryAfter(value: string | null): number | undefined {
  if (!value) return undefined
  const seconds = Number(value)
  if (Number.isFinite(seconds) && seconds >= 0) return seconds
  const date = Date.parse(value)
  return Number.isNaN(date) ? undefined : Math.max(0, Math.ceil((date - Date.now()) / 1000))
}

/** GET + JSON with an 8 s timeout. Keys travel in headers only, never in the URL. */
export async function getJson<T>(fetchImpl: FetchLike, url: string, options: GetJsonOptions): Promise<T> {
  const { provider } = options
  let response: Response
  try {
    response = await fetchImpl(url, {
      method: "GET",
      headers: { accept: "application/json", ...options.headers },
      signal: AbortSignal.timeout(options.timeoutMs ?? 8_000),
    })
  } catch (error) {
    const name = (error as { name?: string }).name
    throw new ProviderError(provider, name === "TimeoutError" || name === "AbortError" ? "timeout" : "upstream")
  }
  if (response.status === 429) throw new ProviderError(provider, "rate_limited", parseRetryAfter(response.headers.get("retry-after")), 429)
  if (response.status === 404) throw new ProviderError(provider, "not_found", undefined, 404)
  if (!response.ok) throw new ProviderError(provider, "upstream", undefined, response.status)
  const text = await response.text()
  try {
    return JSON.parse(text) as T
  } catch {
    throw new ProviderError(provider, "bad_response", undefined, response.status)
  }
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/providers/http.test.ts && npm run typecheck`
Expected: `4 passed`, and typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/providers/types.ts server/src/providers/http.ts server/test/support/fakeFetch.ts server/test/providers/http.test.ts
git commit -m "feat(server): add provider types and getJson with error mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: `MarketCacheRepository` and migration 002

**Files:**
- Create: `server/migrations/002_market_cache.sql`
- Create: `server/src/db/MarketCacheRepository.ts`, `server/src/db/NeonMarketCacheRepository.ts`, `server/src/db/MockMarketCacheRepository.ts`
- Test: `server/test/db/MarketCacheRepository.test.ts`

- [x] **Step 1: Write the failing contract test**

Create `server/test/db/MarketCacheRepository.test.ts`:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { MarketCacheRepository } from "../../src/db/MarketCacheRepository.js"
import { MockMarketCacheRepository } from "../../src/db/MockMarketCacheRepository.js"
import { NeonMarketCacheRepository } from "../../src/db/NeonMarketCacheRepository.js"
import type { ProviderQuote } from "../../src/providers/types.js"
import { createTestDb } from "../support/pglite.js"

const fetchedAt = new Date("2026-11-20T15:00:00.000Z")
const expiresAt = new Date("2026-11-20T15:03:00.000Z")
const quote = (symbol: string, price: string): ProviderQuote => ({
  symbol, price, previousClose: "170", open: "171", high: "173", low: "170.5", change: "2.1", changePercent: 1.235, asOf: "2026-11-20T14:59:00.000Z",
})

const implementations: Array<[string, () => Promise<{ repo: MarketCacheRepository; close: () => Promise<void> }>]> = [
  ["NeonMarketCacheRepository (PGlite)", async () => {
    const db = await createTestDb()
    return { repo: new NeonMarketCacheRepository(db.sql), close: db.close }
  }],
  ["MockMarketCacheRepository", async () => ({ repo: new MockMarketCacheRepository(), close: async () => {} })],
]

describe.each(implementations)("%s", (_name, make) => {
  let repo: MarketCacheRepository
  let close: () => Promise<void>
  beforeEach(async () => {
    ;({ repo, close } = await make())
  })
  afterEach(async () => {
    await close()
  })

  it("round-trips quotes and returns only requested symbols", async () => {
    await repo.putQuotes([
      { symbol: "AAPL", payload: quote("AAPL", "172.1"), provider: "finnhub", fetchedAt, expiresAt },
      { symbol: "MSFT", payload: quote("MSFT", "410"), provider: "finnhub", fetchedAt, expiresAt },
    ])
    const found = await repo.getQuotes(["AAPL", "NVDA"])
    expect([...found.keys()]).toEqual(["AAPL"])
    expect(found.get("AAPL")).toEqual({ payload: quote("AAPL", "172.1"), provider: "finnhub", fetchedAt, expiresAt })
  })

  it("upserts quotes and ignores an empty batch", async () => {
    await repo.putQuotes([{ symbol: "AAPL", payload: quote("AAPL", "1"), provider: "finnhub", fetchedAt, expiresAt }])
    await repo.putQuotes([{ symbol: "AAPL", payload: quote("AAPL", "2"), provider: "finnhub", fetchedAt, expiresAt }])
    await repo.putQuotes([])
    expect((await repo.getQuotes(["AAPL"])).get("AAPL")?.payload.price).toBe("2")
  })

  it("round-trips history per (symbol, series)", async () => {
    const bars = [{ t: "2026-11-19T00:00:00.000Z", c: "171.2" }, { t: "2026-11-20T00:00:00.000Z", c: "172.1" }]
    await repo.putHistory("AAPL", "daily5y", { payload: bars, provider: "tiingo", fetchedAt, expiresAt })
    expect(await repo.getHistory("AAPL", "daily5y")).toEqual({ payload: bars, provider: "tiingo", fetchedAt, expiresAt })
    expect(await repo.getHistory("AAPL", "1D")).toBeNull()
  })

  it("round-trips profile and search payloads", async () => {
    const profile = { profile: null, metrics: null, profileFetchedAt: fetchedAt.toISOString() }
    await repo.putProfile("AAPL", { payload: profile, provider: "finnhub", fetchedAt, expiresAt })
    expect((await repo.getProfile("AAPL"))?.payload).toEqual(profile)
    const matches = [{ symbol: "AAPL", name: "Apple Inc", exchange: null, type: "Common Stock" }]
    await repo.putSearch("app", { payload: matches, provider: "finnhub", fetchedAt, expiresAt })
    expect((await repo.getSearch("app"))?.payload).toEqual(matches)
    expect(await repo.getSearch("zzz")).toBeNull()
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/db/MarketCacheRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/MockMarketCacheRepository.js`.

- [x] **Step 3: Add migration 002**

Create `server/migrations/002_market_cache.sql`:
```sql
-- 002: shared market-data caches, one row per symbol (overview §8.3)
CREATE TABLE IF NOT EXISTS quote_cache (
  symbol TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  provider TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS history_cache (
  symbol TEXT NOT NULL,
  series TEXT NOT NULL,          -- '1D' | '1W' | 'daily5y'
  payload JSONB NOT NULL,
  provider TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (symbol, series)
);

CREATE TABLE IF NOT EXISTS profile_cache (
  symbol TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS search_cache (
  query TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
```

- [x] **Step 4: Implement the interface and both repositories**

Create `server/src/db/MarketCacheRepository.ts`:
```ts
import type { Bar, ProviderMetrics, ProviderProfile, ProviderQuote, SymbolMatch } from "../providers/types.js"

export type HistorySeries = "1D" | "1W" | "daily5y"

export interface CacheEntry<T> {
  payload: T
  provider: string
  fetchedAt: Date
  expiresAt: Date
}

/** profile2 is refreshed every 7 days, metrics every day; both live in one row. */
export interface ProfilePayload {
  profile: ProviderProfile | null
  metrics: ProviderMetrics | null
  profileFetchedAt: string
}

export interface MarketCacheRepository {
  getQuotes(symbols: string[]): Promise<Map<string, CacheEntry<ProviderQuote>>>
  putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>): Promise<void>
  getHistory(symbol: string, series: HistorySeries): Promise<CacheEntry<Bar[]> | null>
  putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>): Promise<void>
  getProfile(symbol: string): Promise<CacheEntry<ProfilePayload> | null>
  putProfile(symbol: string, entry: CacheEntry<ProfilePayload>): Promise<void>
  getSearch(query: string): Promise<CacheEntry<SymbolMatch[]> | null>
  putSearch(query: string, entry: CacheEntry<SymbolMatch[]>): Promise<void>
}
```

Create `server/src/db/NeonMarketCacheRepository.ts`:
```ts
import type { Bar, ProviderQuote, SymbolMatch } from "../providers/types.js"
import { asDate } from "../lib/time.js"
import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "./MarketCacheRepository.js"
import type { Row, Sql } from "./sql.js"

function mapEntry<T>(row: Row, provider = String(row.provider ?? "finnhub")): CacheEntry<T> {
  return { payload: row.payload as T, provider, fetchedAt: asDate(row.fetched_at), expiresAt: asDate(row.expires_at) }
}

export class NeonMarketCacheRepository implements MarketCacheRepository {
  constructor(private readonly sql: Sql) {}

  async getQuotes(symbols: string[]): Promise<Map<string, CacheEntry<ProviderQuote>>> {
    const result = new Map<string, CacheEntry<ProviderQuote>>()
    if (symbols.length === 0) return result
    const rows = await this.sql`
      SELECT symbol, payload, provider, fetched_at, expires_at FROM quote_cache
      WHERE symbol IN (SELECT jsonb_array_elements_text(${JSON.stringify(symbols)}::jsonb))`
    for (const row of rows) result.set(String(row.symbol), mapEntry<ProviderQuote>(row))
    return result
  }

  async putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>): Promise<void> {
    if (entries.length === 0) return
    const records = entries.map((e) => ({
      symbol: e.symbol,
      payload: e.payload,
      provider: e.provider,
      fetched_at: e.fetchedAt.toISOString(),
      expires_at: e.expiresAt.toISOString(),
    }))
    await this.sql`
      INSERT INTO quote_cache (symbol, payload, provider, fetched_at, expires_at)
      SELECT x.symbol, x.payload, x.provider, x.fetched_at, x.expires_at
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb)
        AS x(symbol text, payload jsonb, provider text, fetched_at timestamptz, expires_at timestamptz)
      ON CONFLICT (symbol) DO UPDATE SET
        payload = EXCLUDED.payload, provider = EXCLUDED.provider,
        fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getHistory(symbol: string, series: HistorySeries): Promise<CacheEntry<Bar[]> | null> {
    const rows = await this.sql`
      SELECT payload, provider, fetched_at, expires_at FROM history_cache WHERE symbol = ${symbol} AND series = ${series}`
    return rows[0] ? mapEntry<Bar[]>(rows[0]) : null
  }

  async putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>): Promise<void> {
    await this.sql`
      INSERT INTO history_cache (symbol, series, payload, provider, fetched_at, expires_at)
      VALUES (${symbol}, ${series}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.provider}, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (symbol, series) DO UPDATE SET
        payload = EXCLUDED.payload, provider = EXCLUDED.provider,
        fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getProfile(symbol: string): Promise<CacheEntry<ProfilePayload> | null> {
    const rows = await this.sql`SELECT payload, fetched_at, expires_at FROM profile_cache WHERE symbol = ${symbol}`
    return rows[0] ? mapEntry<ProfilePayload>(rows[0], "finnhub") : null
  }

  async putProfile(symbol: string, entry: CacheEntry<ProfilePayload>): Promise<void> {
    await this.sql`
      INSERT INTO profile_cache (symbol, payload, fetched_at, expires_at)
      VALUES (${symbol}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (symbol) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }

  async getSearch(query: string): Promise<CacheEntry<SymbolMatch[]> | null> {
    const rows = await this.sql`SELECT payload, fetched_at, expires_at FROM search_cache WHERE query = ${query}`
    return rows[0] ? mapEntry<SymbolMatch[]>(rows[0], "finnhub") : null
  }

  async putSearch(query: string, entry: CacheEntry<SymbolMatch[]>): Promise<void> {
    await this.sql`
      INSERT INTO search_cache (query, payload, fetched_at, expires_at)
      VALUES (${query}, ${JSON.stringify(entry.payload)}::jsonb, ${entry.fetchedAt}::timestamptz, ${entry.expiresAt}::timestamptz)
      ON CONFLICT (query) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at, expires_at = EXCLUDED.expires_at`
  }
}
```

Create `server/src/db/MockMarketCacheRepository.ts`:
```ts
import type { Bar, ProviderQuote, SymbolMatch } from "../providers/types.js"
import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "./MarketCacheRepository.js"

const clone = <T>(entry: CacheEntry<T>): CacheEntry<T> => ({
  payload: structuredClone(entry.payload),
  provider: entry.provider,
  fetchedAt: new Date(entry.fetchedAt.getTime()),
  expiresAt: new Date(entry.expiresAt.getTime()),
})

export class MockMarketCacheRepository implements MarketCacheRepository {
  readonly quotes = new Map<string, CacheEntry<ProviderQuote>>()
  readonly history = new Map<string, CacheEntry<Bar[]>>()
  readonly profiles = new Map<string, CacheEntry<ProfilePayload>>()
  readonly searches = new Map<string, CacheEntry<SymbolMatch[]>>()

  clear(): void {
    this.quotes.clear()
    this.history.clear()
    this.profiles.clear()
    this.searches.clear()
  }

  /** Overview §8.1: every Mock* repository has clear() and seed(). */
  seed(data: {
    quotes?: Array<CacheEntry<ProviderQuote> & { symbol: string }>
    history?: Array<{ symbol: string; series: HistorySeries; entry: CacheEntry<Bar[]> }>
    profiles?: Array<{ symbol: string; entry: CacheEntry<ProfilePayload> }>
    searches?: Array<{ query: string; entry: CacheEntry<SymbolMatch[]> }>
  }): void {
    for (const { symbol, ...entry } of data.quotes ?? []) this.quotes.set(symbol, clone(entry))
    for (const { symbol, series, entry } of data.history ?? []) this.history.set(`${symbol}:${series}`, clone(entry))
    for (const { symbol, entry } of data.profiles ?? []) this.profiles.set(symbol, clone(entry))
    for (const { query, entry } of data.searches ?? []) this.searches.set(query, clone(entry))
  }

  async getQuotes(symbols: string[]) {
    const result = new Map<string, CacheEntry<ProviderQuote>>()
    for (const symbol of symbols) {
      const entry = this.quotes.get(symbol)
      if (entry) result.set(symbol, clone(entry))
    }
    return result
  }

  async putQuotes(entries: Array<CacheEntry<ProviderQuote> & { symbol: string }>) {
    for (const { symbol, ...entry } of entries) this.quotes.set(symbol, clone(entry))
  }

  async getHistory(symbol: string, series: HistorySeries) {
    const entry = this.history.get(`${symbol}:${series}`)
    return entry ? clone(entry) : null
  }

  async putHistory(symbol: string, series: HistorySeries, entry: CacheEntry<Bar[]>) {
    this.history.set(`${symbol}:${series}`, clone(entry))
  }

  async getProfile(symbol: string) {
    const entry = this.profiles.get(symbol)
    return entry ? clone(entry) : null
  }

  async putProfile(symbol: string, entry: CacheEntry<ProfilePayload>) {
    this.profiles.set(symbol, clone({ ...entry, provider: "finnhub" }))
  }

  async getSearch(query: string) {
    const entry = this.searches.get(query)
    return entry ? clone(entry) : null
  }

  async putSearch(query: string, entry: CacheEntry<SymbolMatch[]>) {
    this.searches.set(query, clone({ ...entry, provider: "finnhub" }))
  }
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/db && npm run typecheck`
Expected: every test in `test/db` passes. That includes the migrations test, which now applies `[1, 2]`. The new file reports `8 passed` (4 × 2). Typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/migrations/002_market_cache.sql server/src/db/MarketCacheRepository.ts server/src/db/NeonMarketCacheRepository.ts server/src/db/MockMarketCacheRepository.ts server/test/db/MarketCacheRepository.test.ts
git commit -m "feat(server): add market cache tables and repository

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 5: Provider adapters

Each adapter is tested against a committed fixture through `fakeFetch`. Every test asserts three things:
- the exact URL
- that the key travels **in a header, never in the URL**
- the mapping to the provider types

### Task 13: Finnhub adapter (quote, search, profile2, metric)

**Files:**
- Create: `server/src/providers/finnhub.ts`
- Create: `server/test/support/fixtures/finnhub-quote-aapl.json`, `finnhub-quote-unknown.json`, `finnhub-search-app.json`, `finnhub-profile2-aapl.json`, `finnhub-metric-aapl.json`
- Test: `server/test/providers/finnhub.test.ts`

- [x] **Step 1: Add the fixtures**

Create `server/test/support/fixtures/finnhub-quote-aapl.json`:
```json
{ "c": 172.1, "d": 2.1, "dp": 1.2353, "h": 173.0, "l": 170.5, "o": 171.0, "pc": 170.0, "t": 1795186800 }
```

Create `server/test/support/fixtures/finnhub-quote-unknown.json`:
```json
{ "c": 0, "d": null, "dp": null, "h": 0, "l": 0, "o": 0, "pc": 0, "t": 0 }
```

Create `server/test/support/fixtures/finnhub-search-app.json`:
```json
{
  "count": 5,
  "result": [
    { "description": "APPLE INC", "displaySymbol": "AAPL", "symbol": "AAPL", "type": "Common Stock" },
    { "description": "APPLE INC", "displaySymbol": "AAPL.MX", "symbol": "AAPL.MX", "type": "Common Stock" },
    { "description": "APPLIED MATERIALS INC", "displaySymbol": "AMAT", "symbol": "AMAT", "type": "Common Stock" },
    { "description": "APP WARRANT", "displaySymbol": "APPW", "symbol": "APPW", "type": "Warrant" },
    { "description": "SPDR S&P 500 ETF TRUST", "displaySymbol": "SPY", "symbol": "SPY", "type": "ETP" }
  ]
}
```

Create `server/test/support/fixtures/finnhub-profile2-aapl.json`:
```json
{
  "country": "US", "currency": "USD", "exchange": "NASDAQ NMS - GLOBAL MARKET", "finnhubIndustry": "Technology",
  "ipo": "1980-12-12", "logo": "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/AAPL.png",
  "marketCapitalization": 2650000.5, "name": "Apple Inc", "phone": "14089961010", "shareOutstanding": 15441.88,
  "ticker": "AAPL", "weburl": "https://www.apple.com/"
}
```

Create `server/test/support/fixtures/finnhub-metric-aapl.json`:
```json
{
  "metric": {
    "52WeekHigh": 199.62, "52WeekLow": 164.08, "beta": 1.29, "dividendYieldIndicatedAnnual": 0.55,
    "netProfitMarginTTM": 25.31, "pbAnnual": 45.2, "peBasicExclExtraTTM": 28.4, "roaTTM": 27.5, "roeTTM": 147.25
  },
  "metricType": "all",
  "symbol": "AAPL"
}
```

- [x] **Step 2: Write the failing test**

Create `server/test/providers/finnhub.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { FinnhubProvider } from "../../src/providers/finnhub.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const KEY = "finnhub-test-key"

function provider(routes: Record<string, unknown>) {
  const fake = fakeFetch(
    Object.entries(routes).map(([path, body]) => ({ match: (url: URL) => url.pathname === path, respond: () => json(body) })),
  )
  return { finnhub: new FinnhubProvider(KEY, fake.fetch), calls: fake.calls }
}

describe("FinnhubProvider", () => {
  it("maps /quote and sends the key as X-Finnhub-Token", async () => {
    const { finnhub, calls } = provider({ "/api/v1/quote": fixture("finnhub-quote-aapl.json") })
    expect(await finnhub.getQuote("AAPL")).toEqual({
      symbol: "AAPL", price: "172.1", previousClose: "170", open: "171", high: "173", low: "170.5",
      change: "2.1", changePercent: 1.2353, asOf: "2026-11-20T15:00:00.000Z",
    })
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/quote?symbol=AAPL")
    expect(headerOf(calls[0]?.init, "x-finnhub-token")).toBe(KEY)
    expect(calls[0]?.url.toString()).not.toContain(KEY)
  })

  it("returns null for an unknown symbol (all-zero quote)", async () => {
    const { finnhub } = provider({ "/api/v1/quote": fixture("finnhub-quote-unknown.json") })
    expect(await finnhub.getQuote("ZZZZ")).toBeNull()
  })

  it("searches US listings and keeps common stock, ETP and ADR with plain tickers", async () => {
    const { finnhub, calls } = provider({ "/api/v1/search": fixture("finnhub-search-app.json") })
    expect(await finnhub.search("app")).toEqual([
      { symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" },
      { symbol: "AMAT", name: "APPLIED MATERIALS INC", exchange: null, type: "Common Stock" },
      { symbol: "SPY", name: "SPDR S&P 500 ETF TRUST", exchange: null, type: "ETP" },
    ])
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/search?q=app&exchange=US")
  })

  it("maps profile2 (market cap from millions) and returns null for {}", async () => {
    const { finnhub } = provider({ "/api/v1/stock/profile2": fixture("finnhub-profile2-aapl.json") })
    expect(await finnhub.getProfile("AAPL")).toEqual({
      symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ NMS - GLOBAL MARKET", industry: "Technology",
      logoUrl: "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/AAPL.png", marketCap: "2650000500000",
    })
    const empty = provider({ "/api/v1/stock/profile2": {} })
    expect(await empty.finnhub.getProfile("ZZZZ")).toBeNull()
  })

  it("maps metric=all and returns null when every metric is missing", async () => {
    const { finnhub, calls } = provider({ "/api/v1/stock/metric": fixture("finnhub-metric-aapl.json") })
    expect(await finnhub.getMetrics("AAPL")).toEqual({
      peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
      fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29,
    })
    expect(calls[0]?.url.toString()).toBe("https://finnhub.io/api/v1/stock/metric?symbol=AAPL&metric=all")
    const empty = provider({ "/api/v1/stock/metric": { metric: {}, metricType: "all", symbol: "ZZZZ" } })
    expect(await empty.finnhub.getMetrics("ZZZZ")).toBeNull()
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/providers/finnhub.test.ts`
Expected: FAIL with `Failed to load url ../../src/providers/finnhub.js`.

- [x] **Step 4: Implement the adapter**

Create `server/src/providers/finnhub.ts`:
```ts
import { nullableDecimal, toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import type { ProfileProvider, ProviderMetrics, ProviderProfile, ProviderQuote, QuoteProvider, SymbolMatch, SymbolSearchProvider } from "./types.js"

interface FinnhubQuote { c: number; d: number | null; dp: number | null; h: number; l: number; o: number; pc: number; t: number }
interface FinnhubSearch { count: number; result: Array<{ description: string; displaySymbol: string; symbol: string; type: string }> }
interface FinnhubProfile { exchange?: string; finnhubIndustry?: string; logo?: string; marketCapitalization?: number; name?: string; ticker?: string }
interface FinnhubMetric { metric: Record<string, number | null | undefined> }

const SEARCH_TYPES = new Set(["Common Stock", "ETP", "ADR"])
const SEARCH_SYMBOL = /^[A-Z]{1,5}(\.[A-Z])?$/
const positive = (n: number | null | undefined) => (typeof n === "number" && n > 0 ? toDecimalString(n) : null)
const finite = (n: number | null | undefined) => (typeof n === "number" && Number.isFinite(n) ? n : null)

export class FinnhubProvider implements QuoteProvider, SymbolSearchProvider, ProfileProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://finnhub.io/api/v1",
  ) {}

  private get<T>(path: string, params: Record<string, string>): Promise<T> {
    const url = new URL(`${this.baseUrl}${path}`)
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value)
    return getJson<T>(this.fetchImpl, url.toString(), { provider: "finnhub", headers: { "X-Finnhub-Token": this.apiKey } })
  }

  async getQuote(symbol: string): Promise<ProviderQuote | null> {
    const q = await this.get<FinnhubQuote>("/quote", { symbol })
    if (!q.c || !q.t) return null // Finnhub answers unknown symbols with an all-zero quote
    return {
      symbol,
      price: toDecimalString(q.c),
      previousClose: positive(q.pc),
      open: positive(q.o),
      high: positive(q.h),
      low: positive(q.l),
      change: nullableDecimal(q.d),
      changePercent: finite(q.dp),
      asOf: new Date(q.t * 1000).toISOString(),
    }
  }

  async search(query: string): Promise<SymbolMatch[]> {
    const body = await this.get<FinnhubSearch>("/search", { q: query, exchange: "US" })
    return body.result
      .filter((r) => SEARCH_TYPES.has(r.type) && SEARCH_SYMBOL.test(r.symbol))
      .map((r) => ({ symbol: r.symbol, name: r.description, exchange: null, type: r.type }))
  }

  async getProfile(symbol: string): Promise<ProviderProfile | null> {
    const p = await this.get<FinnhubProfile>("/stock/profile2", { symbol })
    if (!p.ticker && !p.name) return null
    return {
      symbol,
      name: p.name ?? null,
      exchange: p.exchange ?? null,
      industry: p.finnhubIndustry ?? null,
      logoUrl: p.logo ? p.logo : null,
      marketCap: typeof p.marketCapitalization === "number" ? toDecimalString(p.marketCapitalization * 1_000_000, 0) : null,
    }
  }

  /** Ratios are as Finnhub reports them: yield, ROE, ROA and margin are percentages (0.55 = 0.55%). */
  async getMetrics(symbol: string): Promise<ProviderMetrics | null> {
    const m = (await this.get<FinnhubMetric>("/stock/metric", { symbol, metric: "all" })).metric ?? {}
    const metrics: ProviderMetrics = {
      peRatio: finite(m.peBasicExclExtraTTM),
      pbRatio: finite(m.pbAnnual),
      dividendYield: finite(m.dividendYieldIndicatedAnnual),
      roe: finite(m.roeTTM),
      roa: finite(m.roaTTM),
      profitMargin: finite(m.netProfitMarginTTM),
      fiftyTwoWeekHigh: positive(m["52WeekHigh"]),
      fiftyTwoWeekLow: positive(m["52WeekLow"]),
      beta: finite(m.beta),
    }
    return Object.values(metrics).every((value) => value === null) ? null : metrics
  }
}
```

- [x] **Step 5: Run the test to verify it passes**

Run: `npx vitest run test/providers/finnhub.test.ts && npm run typecheck`
Expected: `5 passed`, and typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/providers/finnhub.ts server/test/providers/finnhub.test.ts server/test/support/fixtures/finnhub-*.json
git commit -m "feat(server): add Finnhub quote, search, profile and metric adapter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: Tiingo daily adapter

**Files:**
- Create: `server/src/providers/tiingo.ts`, `server/test/support/fixtures/tiingo-daily-aapl.json`
- Test: `server/test/providers/tiingo.test.ts`

- [x] **Step 1: Add the fixture**

Create `server/test/support/fixtures/tiingo-daily-aapl.json`:
```json
[
  { "date": "2026-11-18T00:00:00.000Z", "close": 170.0, "high": 171.0, "low": 169.0, "open": 169.5, "volume": 50000000, "adjClose": 169.9, "adjHigh": 170.9, "adjLow": 168.9, "adjOpen": 169.4, "adjVolume": 50000000, "divCash": 0.0, "splitFactor": 1.0 },
  { "date": "2026-11-19T00:00:00.000Z", "close": 171.3, "high": 172.0, "low": 170.1, "open": 170.2, "volume": 48000000, "adjClose": 171.2, "adjHigh": 171.9, "adjLow": 170.0, "adjOpen": 170.1, "adjVolume": 48000000, "divCash": 0.0, "splitFactor": 1.0 },
  { "date": "2026-11-20T00:00:00.000Z", "close": 172.2, "high": 173.0, "low": 170.5, "open": 171.0, "volume": 52000000, "adjClose": 172.1, "adjHigh": 172.9, "adjLow": 170.4, "adjOpen": 170.9, "adjVolume": 52000000, "divCash": 0.0, "splitFactor": 1.0 }
]
```

- [x] **Step 2: Write the failing test**

Create `server/test/providers/tiingo.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { TiingoProvider } from "../../src/providers/tiingo.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const KEY = "tiingo-test-key"

describe("TiingoProvider", () => {
  it("maps daily bars to adjusted closes, oldest first", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json(fixture("tiingo-daily-aapl.json")) }])
    const bars = await new TiingoProvider(KEY, fake.fetch).getDailyBars("AAPL", "2021-11-13", "2026-11-20")
    expect(bars).toEqual([
      { t: "2026-11-18T00:00:00.000Z", c: "169.9" },
      { t: "2026-11-19T00:00:00.000Z", c: "171.2" },
      { t: "2026-11-20T00:00:00.000Z", c: "172.1" },
    ])
    expect(fake.calls[0]?.url.toString()).toBe(
      "https://api.tiingo.com/tiingo/daily/aapl/prices?startDate=2021-11-13&endDate=2026-11-20&resampleFreq=daily",
    )
    expect(headerOf(fake.calls[0]?.init, "authorization")).toBe(`Token ${KEY}`)
    expect(fake.calls[0]?.url.toString()).not.toContain(KEY)
  })

  it("uses Tiingo's dash form for class shares and returns [] for unknown tickers", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => new Response("{}", { status: 404 }) }])
    expect(await new TiingoProvider(KEY, fake.fetch).getDailyBars("BRK.B", "2026-01-01", "2026-11-20")).toEqual([])
    expect(fake.calls[0]?.url.pathname).toBe("/tiingo/daily/brk-b/prices")
  })

  it("treats a non-array body as bad_response", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json({ detail: "Error: Ticker 'ZZZZ' not found" }) }])
    await expect(new TiingoProvider(KEY, fake.fetch).getDailyBars("ZZZZ", "2026-01-01", "2026-11-20")).rejects.toMatchObject({
      provider: "tiingo",
      kind: "bad_response",
    })
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/providers/tiingo.test.ts`
Expected: FAIL with `Failed to load url ../../src/providers/tiingo.js`.

- [x] **Step 4: Implement the adapter**

Create `server/src/providers/tiingo.ts`:
```ts
import { toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import { ProviderError, type Bar, type DailyBarsProvider } from "./types.js"

interface TiingoDailyRow {
  date: string
  adjClose: number
}

export class TiingoProvider implements DailyBarsProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://api.tiingo.com",
  ) {}

  async getDailyBars(symbol: string, from: string, to: string): Promise<Bar[]> {
    const ticker = symbol.toLowerCase().replace(".", "-")
    const url = new URL(`${this.baseUrl}/tiingo/daily/${encodeURIComponent(ticker)}/prices`)
    url.searchParams.set("startDate", from)
    url.searchParams.set("endDate", to)
    url.searchParams.set("resampleFreq", "daily")
    let body: unknown
    try {
      body = await getJson<unknown>(this.fetchImpl, url.toString(), {
        provider: "tiingo",
        headers: { Authorization: `Token ${this.apiKey}` },
      })
    } catch (error) {
      if (error instanceof ProviderError && error.kind === "not_found") return []
      throw error
    }
    // Tiingo sometimes answers 200 with {"detail": "..."} instead of an array.
    if (!Array.isArray(body)) throw new ProviderError("tiingo", "bad_response")
    const rows = body as TiingoDailyRow[]
    return rows
      .filter((row) => typeof row.adjClose === "number" && Number.isFinite(row.adjClose))
      .map((row) => ({ t: new Date(row.date).toISOString(), c: toDecimalString(row.adjClose) }))
  }
}
```

- [x] **Step 5: Run the test to verify it passes**

Run: `npx vitest run test/providers/tiingo.test.ts && npm run typecheck`
Expected: `3 passed`, and typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/providers/tiingo.ts server/test/providers/tiingo.test.ts server/test/support/fixtures/tiingo-daily-aapl.json
git commit -m "feat(server): add Tiingo daily history adapter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: Alpaca intraday bars adapter

**Files:**
- Create: `server/src/providers/alpaca.ts`, `server/test/support/fixtures/alpaca-bars-aapl-5min.json`
- Test: `server/test/providers/alpaca.test.ts`

- [x] **Step 1: Add the fixture**

Create `server/test/support/fixtures/alpaca-bars-aapl-5min.json`:
```json
{
  "bars": [
    { "t": "2026-11-20T14:30:00Z", "o": 171.0, "h": 171.5, "l": 170.8, "c": 171.2, "v": 1200000, "n": 9000, "vw": 171.1 },
    { "t": "2026-11-20T14:35:00Z", "o": 171.2, "h": 171.8, "l": 171.1, "c": 171.6, "v": 900000, "n": 7000, "vw": 171.5 }
  ],
  "symbol": "AAPL",
  "next_page_token": null
}
```

- [x] **Step 2: Write the failing test**

Create `server/test/providers/alpaca.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { fixedClock } from "../../src/lib/clock.js"
import { AlpacaProvider } from "../../src/providers/alpaca.js"
import { fakeFetch, fixture, headerOf, json } from "../support/fakeFetch.js"

const clock = () => fixedClock(new Date("2026-11-20T15:00:00.000Z"))

describe("AlpacaProvider", () => {
  it("requests SIP split-adjusted bars ending at least 16 minutes ago", async () => {
    const fake = fakeFetch([{ match: () => true, respond: () => json(fixture("alpaca-bars-aapl-5min.json")) }])
    const alpaca = new AlpacaProvider("id-1", "secret-1", clock(), fake.fetch)
    const bars = await alpaca.getIntradayBars("AAPL", "5Min", new Date("2026-11-20T14:30:00.000Z"), new Date("2026-11-20T15:00:00.000Z"))
    expect(bars).toEqual([
      { t: "2026-11-20T14:30:00.000Z", c: "171.2" },
      { t: "2026-11-20T14:35:00.000Z", c: "171.6" },
    ])
    const url = fake.calls[0]?.url
    expect(url?.origin + (url?.pathname ?? "")).toBe("https://data.alpaca.markets/v2/stocks/AAPL/bars")
    expect(Object.fromEntries(url?.searchParams ?? [])).toEqual({
      timeframe: "5Min",
      start: "2026-11-20T14:30:00.000Z",
      end: "2026-11-20T14:44:00.000Z",
      feed: "sip",
      adjustment: "split",
      limit: "10000",
      sort: "asc",
    })
    expect(headerOf(fake.calls[0]?.init, "apca-api-key-id")).toBe("id-1")
    expect(headerOf(fake.calls[0]?.init, "apca-api-secret-key")).toBe("secret-1")
  })

  it("follows next_page_token and tolerates bars: null", async () => {
    const fake = fakeFetch([
      {
        match: (url) => !url.searchParams.has("page_token"),
        respond: () => json({ bars: [{ t: "2026-11-19T14:30:00Z", c: 170 }], symbol: "AAPL", next_page_token: "p2" }),
      },
      { match: (url) => url.searchParams.get("page_token") === "p2", respond: () => json({ bars: null, symbol: "AAPL", next_page_token: null }) },
    ])
    const alpaca = new AlpacaProvider("id-1", "secret-1", clock(), fake.fetch)
    const bars = await alpaca.getIntradayBars("AAPL", "30Min", new Date("2026-11-13T14:30:00.000Z"), new Date("2026-11-20T14:00:00.000Z"))
    expect(bars).toEqual([{ t: "2026-11-19T14:30:00.000Z", c: "170" }])
    expect(fake.calls).toHaveLength(2)
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/providers/alpaca.test.ts`
Expected: FAIL with `Failed to load url ../../src/providers/alpaca.js`.

- [x] **Step 4: Implement the adapter**

Create `server/src/providers/alpaca.ts`:
```ts
import type { Clock } from "../lib/clock.js"
import { toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import type { Bar, IntradayBarsProvider, IntradayTimeframe } from "./types.js"

interface AlpacaBarsResponse {
  bars: Array<{ t: string; c: number }> | null
  next_page_token: string | null
}

/** Basic (free) plan: full SIP tape, but nothing from the latest 15 minutes. */
const SIP_DELAY_MS = 16 * 60_000
const MAX_BARS = 20_000

export class AlpacaProvider implements IntradayBarsProvider {
  constructor(
    private readonly keyId: string,
    private readonly secretKey: string,
    private readonly clock: Clock,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://data.alpaca.markets",
  ) {}

  async getIntradayBars(symbol: string, timeframe: IntradayTimeframe, start: Date, end: Date): Promise<Bar[]> {
    const latestAllowed = this.clock.now().getTime() - SIP_DELAY_MS
    const clampedEnd = new Date(Math.min(end.getTime(), latestAllowed))
    const bars: Bar[] = []
    let pageToken: string | null = null
    do {
      const url = new URL(`${this.baseUrl}/v2/stocks/${encodeURIComponent(symbol)}/bars`)
      url.searchParams.set("timeframe", timeframe)
      url.searchParams.set("start", start.toISOString())
      url.searchParams.set("end", clampedEnd.toISOString())
      url.searchParams.set("feed", "sip")
      url.searchParams.set("adjustment", "split")
      url.searchParams.set("limit", "10000")
      url.searchParams.set("sort", "asc")
      if (pageToken) url.searchParams.set("page_token", pageToken)
      const body: AlpacaBarsResponse = await getJson<AlpacaBarsResponse>(this.fetchImpl, url.toString(), {
        provider: "alpaca",
        headers: { "APCA-API-KEY-ID": this.keyId, "APCA-API-SECRET-KEY": this.secretKey },
      })
      for (const bar of body.bars ?? []) bars.push({ t: new Date(bar.t).toISOString(), c: toDecimalString(bar.c) })
      pageToken = body.next_page_token
    } while (pageToken && bars.length < MAX_BARS)
    return bars
  }
}
```

- [x] **Step 5: Run the test to verify it passes**

Run: `npx vitest run test/providers && npm run typecheck`
Expected: every provider test passes (`14 passed` across http, finnhub, tiingo, alpaca). Typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/providers/alpaca.ts server/test/providers/alpaca.test.ts server/test/support/fixtures/alpaca-bars-aapl-5min.json
git commit -m "feat(server): add Alpaca 15-minute-delayed intraday bars adapter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 6: `MarketDataService`

`MarketDataService` is the only place that combines cache, buckets and providers. Every public method follows the same steps:
1. Read the cache. Fresh entries are returned immediately.
2. Coalesce identical in-flight work in process.
3. Take bucket tokens before calling a provider, and block the bucket when the provider answers 429.
4. Write the result to the cache.
5. On failure, fall back to stale cache (`stale: true`). With nothing cached, throw `UPSTREAM_RATE_LIMITED` (503 with `Retry-After`), `NOT_FOUND` (404) or `UPSTREAM_UNAVAILABLE` (502).

### Task 16: Service core and `getQuotes`

**Files:**
- Create: `server/src/services/MarketDataService.ts`
- Create: `server/test/support/market.ts`
- Test: `server/test/services/MarketDataService.quotes.test.ts`

- [x] **Step 1: Write the test helpers**

Create `server/test/support/market.ts`:
```ts
import { vi } from "vitest"
import { MockMarketCacheRepository } from "../../src/db/MockMarketCacheRepository.js"
import { fixedClock } from "../../src/lib/clock.js"
import type { Bar, ProviderMetrics, ProviderProfile, ProviderQuote, SymbolMatch } from "../../src/providers/types.js"
import { MarketDataService, type MarketLogger, type MarketProviders } from "../../src/services/MarketDataService.js"
import { MockRateLimiter } from "../../src/services/RateLimiter.js"

/** Friday 2026-11-20 10:00 EST: market open. */
export const NOW = new Date("2026-11-20T15:00:00.000Z")
export const DAY_MS = 86_400_000

export function providerQuote(symbol: string, price: string): ProviderQuote {
  return { symbol, price, previousClose: "100", open: "100", high: "101", low: "99", change: "1", changePercent: 1, asOf: "2026-11-20T14:59:00.000Z" }
}

export function makeProviders(overrides: Partial<MarketProviders> = {}): MarketProviders {
  return {
    quotes: { getQuote: vi.fn(async (symbol: string): Promise<ProviderQuote | null> => providerQuote(symbol, "100")) },
    search: { search: vi.fn(async (_query: string): Promise<SymbolMatch[]> => []) },
    profile: {
      getProfile: vi.fn(async (_symbol: string): Promise<ProviderProfile | null> => null),
      getMetrics: vi.fn(async (_symbol: string): Promise<ProviderMetrics | null> => null),
    },
    daily: { getDailyBars: vi.fn(async (_symbol: string, _from: string, _to: string): Promise<Bar[]> => []) },
    intraday: { getIntradayBars: vi.fn(async (): Promise<Bar[]> => []) },
    ...overrides,
  }
}

export function makeService(options: { providers?: Partial<MarketProviders>; now?: Date; logger?: MarketLogger } = {}) {
  const cache = new MockMarketCacheRepository()
  const limiter = new MockRateLimiter()
  const clock = fixedClock(options.now ?? NOW)
  const providers = makeProviders(options.providers)
  const service = new MarketDataService({ cache, limiter, providers, clock, logger: options.logger })
  return { service, cache, limiter, clock, providers }
}
```

- [x] **Step 2: Write the failing tests**

Create `server/test/services/MarketDataService.quotes.test.ts`:
```ts
import { describe, expect, it, vi } from "vitest"
import { ProviderError } from "../../src/providers/types.js"
import { makeService, NOW, providerQuote } from "../support/market.js"

describe("MarketDataService.getQuotes", () => {
  it("serves fresh cache without calling the provider", async () => {
    const { service, cache, providers } = makeService()
    await cache.putQuotes([{ symbol: "AAPL", payload: providerQuote("AAPL", "172.1"), provider: "finnhub", fetchedAt: NOW, expiresAt: new Date(NOW.getTime() + 60_000) }])
    const result = await service.getQuotes(["AAPL"])
    expect(result.quotes[0]).toMatchObject({ symbol: "AAPL", price: "172.1", stale: false, source: "finnhub", volume: null })
    expect(providers.quotes.getQuote).not.toHaveBeenCalled()
  })

  it("fetches misses, caches them for 3 minutes and keeps request order", async () => {
    const { service, cache } = makeService()
    const result = await service.getQuotes(["MSFT", "AAPL"])
    expect(result.quotes.map((q) => q.symbol)).toEqual(["MSFT", "AAPL"])
    expect(result.missing).toEqual([])
    expect(cache.quotes.get("AAPL")?.expiresAt.toISOString()).toBe("2026-11-20T15:03:00.000Z")
  })

  it("reports unknown symbols in missing", async () => {
    const { service } = makeService({ providers: { quotes: { getQuote: vi.fn(async () => null) } } })
    expect(await service.getQuotes(["ZZZZ"])).toEqual({ quotes: [], missing: ["ZZZZ"] })
  })

  it("falls back to stale cache when the provider fails", async () => {
    const { service, cache } = makeService({
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "upstream", undefined, 502) }) } },
    })
    await cache.putQuotes([{ symbol: "AAPL", payload: providerQuote("AAPL", "150"), provider: "finnhub", fetchedAt: new Date(0), expiresAt: new Date(1) }])
    const result = await service.getQuotes(["AAPL"])
    expect(result.quotes[0]).toMatchObject({ symbol: "AAPL", price: "150", stale: true })
  })

  it("fetches at most 25 symbols per request", async () => {
    const { service, providers } = makeService()
    const symbols = Array.from({ length: 30 }, (_, i) => `SYM${i}`)
    const result = await service.getQuotes(symbols)
    expect(providers.quotes.getQuote).toHaveBeenCalledTimes(25)
    expect(result.missing).toEqual(symbols.slice(25))
  })

  it("blocks the bucket on a provider 429 and throws 503 when nothing is cached", async () => {
    const { service, limiter } = makeService({
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "rate_limited", 30, 429) }) } },
    })
    await expect(service.getQuotes(["AAPL"])).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", statusCode: 503, retryAfterSec: 30 })
    expect(limiter.blocks).toEqual([{ key: "provider:finnhub", seconds: 30 }])
    // While blocked, Retry-After comes from the block itself, not the refill rate.
    await expect(service.getQuotes(["MSFT"])).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", retryAfterSec: 30 })
  })

  it("throws UPSTREAM_UNAVAILABLE (502) when every symbol failed and nothing is cached", async () => {
    const warn = vi.fn()
    const { service } = makeService({
      logger: { warn },
      providers: { quotes: { getQuote: vi.fn(async () => { throw new ProviderError("finnhub", "upstream", undefined, 502) }) } },
    })
    await expect(service.getQuotes(["AAPL"])).rejects.toMatchObject({ code: "UPSTREAM_UNAVAILABLE", statusCode: 502 })
    expect(warn).toHaveBeenCalledWith({ provider: "finnhub", kind: "upstream", status: 502 }, "market.provider_error")
  })

  it("dedupes requested symbols before fetching and caching", async () => {
    const { service, providers } = makeService()
    const result = await service.getQuotes(["AAPL", "AAPL", "MSFT"])
    expect(result.quotes.map((q) => q.symbol)).toEqual(["AAPL", "MSFT"])
    expect(providers.quotes.getQuote).toHaveBeenCalledTimes(2)
  })

  it("coalesces concurrent identical fetches", async () => {
    const getQuote = vi.fn(async (symbol: string) => {
      await new Promise((resolve) => setTimeout(resolve, 10))
      return providerQuote(symbol, "100")
    })
    const { service } = makeService({ providers: { quotes: { getQuote } } })
    await Promise.all([service.getQuotes(["AAPL"]), service.getQuotes(["AAPL"])])
    expect(getQuote).toHaveBeenCalledTimes(1)
  })
})
```

- [x] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/services/MarketDataService.quotes.test.ts`
Expected: FAIL with `Failed to load url ../../src/services/MarketDataService.js`.

- [x] **Step 4: Implement the service core and `getQuotes`**

Create `server/src/services/MarketDataService.ts`:
```ts
import type { CacheEntry, MarketCacheRepository } from "../db/MarketCacheRepository.js"
import { expiresAt } from "../domain/ttl.js"
import type { Clock } from "../lib/clock.js"
import { mapLimit } from "../lib/concurrency.js"
import { AppError } from "../lib/errors.js"
import {
  ProviderError,
  type DailyBarsProvider,
  type IntradayBarsProvider,
  type ProfileProvider,
  type ProviderQuote,
  type QuoteProvider,
  type SymbolSearchProvider,
} from "../providers/types.js"
import { PROVIDER_BUCKETS, type BucketPolicy, type RateLimiter } from "./RateLimiter.js"

export interface MarketProviders {
  quotes: QuoteProvider
  search: SymbolSearchProvider
  profile: ProfileProvider
  daily: DailyBarsProvider
  intraday: IntradayBarsProvider
}

export interface MarketLogger {
  warn(details: object, message: string): void
}

export interface MarketDataServiceDeps {
  cache: MarketCacheRepository
  limiter: RateLimiter
  providers: MarketProviders
  clock: Clock
  logger?: MarketLogger
}

/** Wire shape of GET /api/market/quotes items (overview §8.4). */
export interface QuoteDTO {
  symbol: string
  price: string
  previousClose: string | null
  open: string | null
  high: string | null
  low: string | null
  change: string | null
  changePercent: number | null
  volume: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  asOf: string
  source: string
  stale: boolean
}

export interface QuotesResult {
  quotes: QuoteDTO[]
  missing: string[]
}

type Bucket = { key: string; policy: BucketPolicy }
type ProviderOutcome<T> =
  | { ok: true; value: T }
  | { ok: false; reason: "rate_limited" | "not_found" | "unavailable"; retryAfterSec?: number }

const MAX_FETCH_PER_REQUEST = 25
const FETCH_CONCURRENCY = 5

export const rateLimitedError = (retryAfterSec = 60) =>
  new AppError("UPSTREAM_RATE_LIMITED", "Market data is temporarily rate limited, try again shortly", 503, retryAfterSec)
export const unavailableError = () => new AppError("UPSTREAM_UNAVAILABLE", "The market data provider is unavailable", 502)

function toQuoteDTO(entry: CacheEntry<ProviderQuote>, stale: boolean): QuoteDTO {
  const q = entry.payload
  return {
    symbol: q.symbol,
    price: q.price,
    previousClose: q.previousClose,
    open: q.open,
    high: q.high,
    low: q.low,
    change: q.change,
    changePercent: q.changePercent,
    volume: null,
    fiftyTwoWeekHigh: null,
    fiftyTwoWeekLow: null,
    asOf: q.asOf,
    source: entry.provider,
    stale,
  }
}

export class MarketDataService {
  private readonly inflight = new Map<string, Promise<unknown>>()

  constructor(private readonly deps: MarketDataServiceDeps) {}

  /** Shares one in-flight promise per key within this instance (Vercel reuses warm instances). */
  private coalesce<T>(key: string, work: () => Promise<T>): Promise<T> {
    const existing = this.inflight.get(key) as Promise<T> | undefined
    if (existing) return existing
    const promise = work().finally(() => this.inflight.delete(key))
    this.inflight.set(key, promise)
    return promise
  }

  /** Takes a token from every bucket, calls the provider, and blocks the buckets on a provider 429. */
  private async callProvider<T>(buckets: Bucket[], call: () => Promise<T>): Promise<ProviderOutcome<T>> {
    for (const bucket of buckets) {
      if (!(await this.deps.limiter.tryTake(bucket.key, bucket.policy))) {
        const blockedFor = (await this.deps.limiter.retryAfterSec?.(bucket.key)) ?? null
        return { ok: false, reason: "rate_limited", retryAfterSec: blockedFor ?? Math.ceil(1 / bucket.policy.refillPerSec) }
      }
    }
    try {
      return { ok: true, value: await call() }
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error
      if (error.kind === "rate_limited") {
        const seconds = error.retryAfterSec ?? 60
        for (const bucket of buckets) await this.deps.limiter.block(bucket.key, seconds)
        return { ok: false, reason: "rate_limited", retryAfterSec: seconds }
      }
      if (error.kind === "not_found") return { ok: false, reason: "not_found" }
      this.deps.logger?.warn({ provider: error.provider, kind: error.kind, status: error.status }, "market.provider_error")
      return { ok: false, reason: "unavailable" }
    }
  }

  async getQuotes(requested: string[]): Promise<QuotesResult> {
    // Dedupe first: one INSERT … ON CONFLICT can't touch the same row twice.
    const symbols = [...new Set(requested)]
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getQuotes(symbols)
    const fresh = new Map<string, QuoteDTO>()
    const stale = new Map<string, CacheEntry<ProviderQuote>>()
    for (const symbol of symbols) {
      const entry = cached.get(symbol)
      if (entry && entry.expiresAt.getTime() > now.getTime()) fresh.set(symbol, toQuoteDTO(entry, false))
      else if (entry) stale.set(symbol, entry)
    }

    const toFetch = symbols.filter((symbol) => !fresh.has(symbol)).slice(0, MAX_FETCH_PER_REQUEST)
    const fetched: Array<CacheEntry<ProviderQuote> & { symbol: string }> = []
    let rateLimitedFor: number | undefined
    let providerUnavailable = false
    await mapLimit(toFetch, FETCH_CONCURRENCY, async (symbol) => {
      if (rateLimitedFor !== undefined) return
      const outcome = await this.coalesce(`quote:${symbol}`, () =>
        this.callProvider([PROVIDER_BUCKETS.finnhub], () => this.deps.providers.quotes.getQuote(symbol)),
      )
      if (outcome.ok && outcome.value) {
        fetched.push({ symbol, payload: outcome.value, provider: "finnhub", fetchedAt: now, expiresAt: expiresAt("quote", now) })
      } else if (!outcome.ok && outcome.reason === "rate_limited") {
        rateLimitedFor = outcome.retryAfterSec
      } else if (!outcome.ok && outcome.reason === "unavailable") {
        providerUnavailable = true
      }
    })
    await this.deps.cache.putQuotes(fetched)
    for (const entry of fetched) fresh.set(entry.symbol, toQuoteDTO(entry, false))

    const quotes: QuoteDTO[] = []
    const missing: string[] = []
    for (const symbol of symbols) {
      const quote = fresh.get(symbol)
      const staleEntry = stale.get(symbol)
      if (quote) quotes.push(quote)
      else if (staleEntry) quotes.push(toQuoteDTO(staleEntry, true))
      else missing.push(symbol)
    }
    if (quotes.length === 0 && rateLimitedFor !== undefined) throw rateLimitedError(rateLimitedFor)
    if (quotes.length === 0 && providerUnavailable) throw unavailableError()
    return { quotes, missing }
  }
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/services/MarketDataService.quotes.test.ts && npm run typecheck`
Expected: `9 passed`, and typecheck exits 0.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/services/MarketDataService.ts server/test/support/market.ts server/test/services/MarketDataService.quotes.test.ts
git commit -m "feat(server): add cached, coalesced, rate-limited quote service

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 17: `getHistory` (1D/1W from Alpaca, 1M/1Y/5Y derived from one `daily5y` Tiingo series)

**Files:**
- Modify: `server/src/services/MarketDataService.ts`
- Test: `server/test/services/MarketDataService.history.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/services/MarketDataService.history.test.ts`:
```ts
import { describe, expect, it, vi } from "vitest"
import type { Bar } from "../../src/providers/types.js"
import { ProviderError } from "../../src/providers/types.js"
import { deriveDailyRange, isoWeekKey } from "../../src/services/MarketDataService.js"
import { makeService, NOW } from "../support/market.js"

const day = (isoDate: string, c: string): Bar => ({ t: `${isoDate}T00:00:00.000Z`, c })
const consecutiveDays = (count: number): Bar[] =>
  Array.from({ length: count }, (_, i) => ({ t: new Date(Date.UTC(2025, 0, 1 + i)).toISOString(), c: String(100 + i) }))

describe("getHistory 1D / 1W (Alpaca, 15 min delayed)", () => {
  it("1D asks for the current session, drops extended hours and caches for 5 minutes", async () => {
    const getIntradayBars = vi.fn(async (): Promise<Bar[]> => [
      { t: "2026-11-20T13:00:00.000Z", c: "170" }, // 08:00 EST pre-market
      { t: "2026-11-20T14:30:00.000Z", c: "171.2" },
      { t: "2026-11-20T14:35:00.000Z", c: "171.6" },
    ])
    const { service, cache } = makeService({ providers: { intraday: { getIntradayBars } } })
    const result = await service.getHistory("AAPL", "1D")
    expect(result).toEqual({
      symbol: "AAPL", range: "1D", source: "alpaca", stale: false, delayedMinutes: 15, asOf: NOW.toISOString(),
      points: [{ t: "2026-11-20T14:30:00.000Z", c: "171.2" }, { t: "2026-11-20T14:35:00.000Z", c: "171.6" }],
    })
    expect(getIntradayBars).toHaveBeenCalledWith("AAPL", "5Min", new Date("2026-11-20T14:30:00.000Z"), NOW)
    expect(cache.history.get("AAPL:1D")?.expiresAt.toISOString()).toBe("2026-11-20T15:05:00.000Z")
    await service.getHistory("AAPL", "1D")
    expect(getIntradayBars).toHaveBeenCalledTimes(1)
  })

  it("1W spans the last five sessions with 30-minute bars", async () => {
    const getIntradayBars = vi.fn(async (): Promise<Bar[]> => [{ t: "2026-11-16T14:30:00.000Z", c: "168" }])
    const { service } = makeService({ providers: { intraday: { getIntradayBars } } })
    await service.getHistory("AAPL", "1W")
    expect(getIntradayBars).toHaveBeenCalledWith("AAPL", "30Min", new Date("2026-11-16T14:30:00.000Z"), NOW)
  })

  it("steps back past a market holiday (Thanksgiving 2026-11-26) instead of returning 404", async () => {
    const thanksgiving = new Date("2026-11-26T15:00:00.000Z") // Thu 10:00 EST; the calendar has no holiday table
    const wednesdayBar: Bar = { t: "2026-11-25T14:30:00.000Z", c: "170.9" }
    const getIntradayBars = vi.fn(async (_symbol: string, _timeframe: string, start: Date): Promise<Bar[]> =>
      start.toISOString() === "2026-11-25T14:30:00.000Z" ? [wednesdayBar] : [],
    )
    const { service } = makeService({ now: thanksgiving, providers: { intraday: { getIntradayBars } } })
    const result = await service.getHistory("AAPL", "1D")
    expect(result.points).toEqual([wednesdayBar])
    expect(getIntradayBars).toHaveBeenNthCalledWith(1, "AAPL", "5Min", new Date("2026-11-26T14:30:00.000Z"), thanksgiving)
    expect(getIntradayBars).toHaveBeenNthCalledWith(2, "AAPL", "5Min", new Date("2026-11-25T14:30:00.000Z"), new Date("2026-11-26T14:30:00.000Z"))
  })
})

describe("getHistory 1M / 1Y / 5Y (Tiingo daily5y)", () => {
  it("derives every daily range from one cached five-year pull", async () => {
    const getDailyBars = vi.fn(async (): Promise<Bar[]> => consecutiveDays(300))
    const { service, limiter } = makeService({ providers: { daily: { getDailyBars } } })
    const oneMonth = await service.getHistory("AAPL", "1M")
    const oneYear = await service.getHistory("AAPL", "1Y")
    await service.getHistory("AAPL", "5Y")
    expect(getDailyBars).toHaveBeenCalledTimes(1)
    expect(getDailyBars).toHaveBeenCalledWith("AAPL", "2021-11-14", "2026-11-20")
    expect(limiter.takes.map((t) => t.key)).toEqual(["provider:tiingo:hour", "provider:tiingo:day"])
    expect(oneMonth.points).toHaveLength(22)
    expect(oneMonth.points[21]?.c).toBe("399")
    expect(oneYear.points).toHaveLength(252)
    expect(oneYear).toMatchObject({ source: "tiingo", delayedMinutes: null, stale: false })
  })

  it("5Y keeps the last close of each ISO week", () => {
    const bars = ["09", "10", "11", "12", "13", "16", "17", "18", "19", "20"].map((d, i) => day(`2026-11-${d}`, String(i + 1)))
    expect(deriveDailyRange(bars, "5Y")).toEqual([day("2026-11-13", "5"), day("2026-11-20", "10")])
    expect(isoWeekKey("2026-11-16T00:00:00.000Z")).toBe("2026-W47")
    expect(isoWeekKey("2026-11-20T00:00:00.000Z")).toBe("2026-W47")
  })

  it("serves stale cache when Tiingo fails", async () => {
    const { service, cache } = makeService({
      providers: { daily: { getDailyBars: vi.fn(async () => { throw new ProviderError("tiingo", "upstream", undefined, 500) }) } },
    })
    await cache.putHistory("AAPL", "daily5y", { payload: [day("2026-11-19", "171.2")], provider: "tiingo", fetchedAt: new Date(0), expiresAt: new Date(1) })
    expect(await service.getHistory("AAPL", "1M")).toMatchObject({ stale: true, points: [day("2026-11-19", "171.2")] })
  })

  it("throws NOT_FOUND for an unknown symbol and 503 when the bucket is empty", async () => {
    const empty = makeService()
    await expect(empty.service.getHistory("ZZZZ", "1Y")).rejects.toMatchObject({ code: "NOT_FOUND", statusCode: 404 })
    const limited = makeService()
    limited.limiter.denied.add("provider:tiingo:hour")
    await expect(limited.service.getHistory("AAPL", "1Y")).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", retryAfterSec: 72 })
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/services/MarketDataService.history.test.ts`
Expected: FAIL. `deriveDailyRange`/`isoWeekKey` aren't exported, and `service.getHistory is not a function`.

- [x] **Step 3: Implement `getHistory`**

In `server/src/services/MarketDataService.ts`, add these imports below the existing ones:
```ts
import type { HistorySeries } from "../db/MarketCacheRepository.js"
import { etDateString, isRegularSessionTime, lastSessionOpen } from "../domain/marketCalendar.js"
import type { CacheKind } from "../domain/ttl.js"
import type { Bar } from "../providers/types.js"
```

Then add these exports directly above `export class MarketDataService`:
```ts
export const CHART_RANGES = ["1D", "1W", "1M", "1Y", "5Y"] as const
export type ChartRange = (typeof CHART_RANGES)[number]

/** Wire shape of GET /api/market/history (overview §8.4). */
export interface HistoryResult {
  symbol: string
  range: ChartRange
  points: Bar[]
  source: string
  asOf: string
  stale: boolean
  delayedMinutes: number | null
}

const SIP_DELAY_MS = 16 * 60_000
const FIVE_YEARS_MS = (5 * 365 + 7) * 86_400_000

export function isoWeekKey(iso: string): string {
  const source = new Date(iso)
  const d = new Date(Date.UTC(source.getUTCFullYear(), source.getUTCMonth(), source.getUTCDate()))
  const weekday = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - weekday)
  const yearStart = Date.UTC(d.getUTCFullYear(), 0, 1)
  const week = Math.ceil(((d.getTime() - yearStart) / 86_400_000 + 1) / 7)
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`
}

/** 1M = last 22 closes, 1Y = last 252, 5Y = last close of each ISO week. Input oldest first. */
export function deriveDailyRange(bars: Bar[], range: "1M" | "1Y" | "5Y"): Bar[] {
  if (range === "1M") return bars.slice(-22)
  if (range === "1Y") return bars.slice(-252)
  const byWeek = new Map<string, Bar>()
  for (const bar of bars) byWeek.set(isoWeekKey(bar.t), bar)
  return [...byWeek.values()]
}
```

Then add these methods inside `MarketDataService`, after `getQuotes`:
```ts
  async getHistory(symbol: string, range: ChartRange): Promise<HistoryResult> {
    if (range === "1D" || range === "1W") {
      const { entry, stale } = await this.cachedSeries(symbol, range, range === "1D" ? "history1D" : "history1W", "alpaca", [PROVIDER_BUCKETS.alpaca], () =>
        this.loadIntraday(symbol, range),
      )
      return { symbol, range, points: entry.payload, source: entry.provider, asOf: entry.fetchedAt.toISOString(), stale, delayedMinutes: 15 }
    }
    const { entry, stale } = await this.cachedSeries(symbol, "daily5y", "daily5y", "tiingo", [PROVIDER_BUCKETS.tiingoHour, PROVIDER_BUCKETS.tiingoDay], () => {
      const now = this.deps.clock.now()
      return this.deps.providers.daily.getDailyBars(symbol, etDateString(new Date(now.getTime() - FIVE_YEARS_MS)), etDateString(now))
    })
    return {
      symbol,
      range,
      points: deriveDailyRange(entry.payload, range),
      source: entry.provider,
      asOf: entry.fetchedAt.toISOString(),
      stale,
      delayedMinutes: null,
    }
  }

  /**
   * 1D = the latest session with delayed data; 1W = the last five sessions. The calendar has no holiday
   * table, so an empty window (Thanksgiving, an early close) steps back one session at a time, up to
   * 5 weekdays, before giving up. A valid symbol never gets 404 on a holiday.
   */
  private async loadIntraday(symbol: string, range: "1D" | "1W"): Promise<Bar[]> {
    const now = this.deps.clock.now()
    const timeframe = range === "1D" ? "5Min" : "30Min"
    let open = lastSessionOpen(new Date(now.getTime() - SIP_DELAY_MS))
    let end = now
    for (let attempt = 0; attempt < 5; attempt += 1) {
      let start = open
      if (range === "1W") {
        for (let i = 1; i < 5; i += 1) start = lastSessionOpen(new Date(start.getTime() - 1))
      }
      const bars = await this.deps.providers.intraday.getIntradayBars(symbol, timeframe, start, end)
      const regular = bars.filter((bar) => isRegularSessionTime(new Date(bar.t)))
      if (regular.length > 0) return regular
      end = open
      open = lastSessionOpen(new Date(open.getTime() - 1))
    }
    return []
  }

  private async cachedSeries(
    symbol: string,
    series: HistorySeries,
    kind: CacheKind,
    provider: string,
    buckets: Bucket[],
    load: () => Promise<Bar[]>,
  ): Promise<{ entry: CacheEntry<Bar[]>; stale: boolean }> {
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getHistory(symbol, series)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return { entry: cached, stale: false }
    const outcome = await this.coalesce(`history:${symbol}:${series}`, () => this.callProvider(buckets, load))
    if (outcome.ok && outcome.value.length > 0) {
      const entry: CacheEntry<Bar[]> = { payload: outcome.value, provider, fetchedAt: now, expiresAt: expiresAt(kind, now) }
      await this.deps.cache.putHistory(symbol, series, entry)
      return { entry, stale: false }
    }
    if (cached) return { entry: cached, stale: true }
    if (outcome.ok || outcome.reason === "not_found") throw new AppError("NOT_FOUND", `No price history for ${symbol}`, 404)
    if (outcome.reason === "rate_limited") throw rateLimitedError(outcome.retryAfterSec)
    throw unavailableError()
  }
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/services && npm run typecheck`
Expected: every service test passes, including `7 passed` in the history file. Typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/services/MarketDataService.ts server/test/services/MarketDataService.history.test.ts
git commit -m "feat(server): add chart history from Alpaca intraday and Tiingo daily5y

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 18: `search` and `getProfile`

**Files:**
- Modify: `server/src/services/MarketDataService.ts`
- Test: `server/test/services/MarketDataService.searchProfile.test.ts`

- [x] **Step 1: Write the failing tests**

Create `server/test/services/MarketDataService.searchProfile.test.ts`:
```ts
import { describe, expect, it, vi } from "vitest"
import type { ProviderMetrics, ProviderProfile } from "../../src/providers/types.js"
import { ProviderError } from "../../src/providers/types.js"
import { DAY_MS, makeService, NOW } from "../support/market.js"

const APPLE = [{ symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" }]
const PROFILE: ProviderProfile = { symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", industry: "Technology", logoUrl: null, marketCap: "2650000500000" }
const METRICS: ProviderMetrics = {
  peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
  fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29,
}

describe("MarketDataService.search", () => {
  it("normalizes the query and caches results for 7 days", async () => {
    const search = vi.fn(async () => APPLE)
    const { service, cache } = makeService({ providers: { search: { search } } })
    expect(await service.search("  App ")).toEqual(APPLE)
    expect(search).toHaveBeenCalledWith("app")
    expect(cache.searches.get("app")?.expiresAt.toISOString()).toBe("2026-11-27T15:00:00.000Z")
    await service.search("APP")
    expect(search).toHaveBeenCalledTimes(1)
  })

  it("uses an expired cache entry when the provider fails, else throws 503 when limited", async () => {
    const failing = makeService({ providers: { search: { search: vi.fn(async () => { throw new ProviderError("finnhub", "timeout") }) } } })
    await failing.cache.putSearch("app", { payload: APPLE, provider: "finnhub", fetchedAt: new Date(0), expiresAt: new Date(1) })
    expect(await failing.service.search("app")).toEqual(APPLE)

    const limited = makeService()
    limited.limiter.denied.add("provider:finnhub")
    await expect(limited.service.search("app")).rejects.toMatchObject({ code: "UPSTREAM_RATE_LIMITED", statusCode: 503 })
  })
})

describe("MarketDataService.getProfile", () => {
  it("merges profile2 and metrics into the wire DTO", async () => {
    const { service } = makeService({
      providers: { profile: { getProfile: vi.fn(async () => PROFILE), getMetrics: vi.fn(async () => METRICS) } },
    })
    expect(await service.getProfile("AAPL")).toEqual({
      symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", industry: "Technology", logoUrl: null, marketCap: "2650000500000",
      peRatio: 28.4, pbRatio: 45.2, dividendYield: 0.55, roe: 147.25, roa: 27.5, profitMargin: 25.31,
      fiftyTwoWeekHigh: "199.62", fiftyTwoWeekLow: "164.08", beta: 1.29, asOf: NOW.toISOString(),
    })
  })

  it("refreshes metrics daily but profile2 only weekly", async () => {
    const getProfile = vi.fn(async () => PROFILE)
    const getMetrics = vi.fn(async () => METRICS)
    const { service, clock } = makeService({ providers: { profile: { getProfile, getMetrics } } })
    await service.getProfile("AAPL")
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([1, 1])
    clock.advance(DAY_MS + 60_000)
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([1, 2])
    clock.advance(7 * DAY_MS)
    await service.getProfile("AAPL")
    expect([getProfile.mock.calls.length, getMetrics.mock.calls.length]).toEqual([2, 3])
  })

  it("throws NOT_FOUND when Finnhub knows nothing about the symbol", async () => {
    const { service } = makeService()
    await expect(service.getProfile("ZZZZ")).rejects.toMatchObject({ code: "NOT_FOUND", statusCode: 404 })
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/services/MarketDataService.searchProfile.test.ts`
Expected: FAIL with `service.search is not a function`.

- [x] **Step 3: Implement `search` and `getProfile`**

In `server/src/services/MarketDataService.ts`, extend the `../db/MarketCacheRepository.js` type import to `import type { CacheEntry, HistorySeries, MarketCacheRepository, ProfilePayload } from "../db/MarketCacheRepository.js"`. Remove the separate `HistorySeries` import line added in Task 17. Then add `type SymbolMatch` to the `../providers/types.js` import list.

Add this export above `export class MarketDataService`:
```ts
/** Wire shape of GET /api/market/profile (overview §8.4). Ratios are Finnhub's percentages. */
export interface ProfileDTO {
  symbol: string
  name: string | null
  exchange: string | null
  industry: string | null
  logoUrl: string | null
  marketCap: string | null
  peRatio: number | null
  pbRatio: number | null
  dividendYield: number | null
  roe: number | null
  roa: number | null
  profitMargin: number | null
  fiftyTwoWeekHigh: string | null
  fiftyTwoWeekLow: string | null
  beta: number | null
  asOf: string
}

const PROFILE_REFRESH_MS = 7 * 86_400_000

function toProfileDTO(symbol: string, entry: CacheEntry<ProfilePayload>): ProfileDTO {
  const p = entry.payload.profile
  const m = entry.payload.metrics
  return {
    symbol,
    name: p?.name ?? null,
    exchange: p?.exchange ?? null,
    industry: p?.industry ?? null,
    logoUrl: p?.logoUrl ?? null,
    marketCap: p?.marketCap ?? null,
    peRatio: m?.peRatio ?? null,
    pbRatio: m?.pbRatio ?? null,
    dividendYield: m?.dividendYield ?? null,
    roe: m?.roe ?? null,
    roa: m?.roa ?? null,
    profitMargin: m?.profitMargin ?? null,
    fiftyTwoWeekHigh: m?.fiftyTwoWeekHigh ?? null,
    fiftyTwoWeekLow: m?.fiftyTwoWeekLow ?? null,
    beta: m?.beta ?? null,
    asOf: entry.fetchedAt.toISOString(),
  }
}
```

Add these methods inside `MarketDataService`, after `getHistory`:
```ts
  async search(query: string): Promise<SymbolMatch[]> {
    const key = query.trim().toLowerCase()
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getSearch(key)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return cached.payload
    const outcome = await this.coalesce(`search:${key}`, () =>
      this.callProvider([PROVIDER_BUCKETS.finnhub], () => this.deps.providers.search.search(key)),
    )
    if (outcome.ok) {
      await this.deps.cache.putSearch(key, { payload: outcome.value, provider: "finnhub", fetchedAt: now, expiresAt: expiresAt("search", now) })
      return outcome.value
    }
    if (cached) return cached.payload
    if (outcome.reason === "not_found") return []
    if (outcome.reason === "rate_limited") throw rateLimitedError(outcome.retryAfterSec)
    throw unavailableError()
  }

  getProfile(symbol: string): Promise<ProfileDTO> {
    return this.coalesce(`profile:${symbol}`, () => this.loadProfile(symbol))
  }

  private async loadProfile(symbol: string): Promise<ProfileDTO> {
    const now = this.deps.clock.now()
    const cached = await this.deps.cache.getProfile(symbol)
    if (cached && cached.expiresAt.getTime() > now.getTime()) return toProfileDTO(symbol, cached)

    const cachedProfile = cached?.payload.profile ?? null
    const profileIsFresh = cachedProfile !== null && now.getTime() - Date.parse(cached?.payload.profileFetchedAt ?? "") < PROFILE_REFRESH_MS
    const finnhub = [PROVIDER_BUCKETS.finnhub]
    const metrics = await this.callProvider(finnhub, () => this.deps.providers.profile.getMetrics(symbol))
    const profile = profileIsFresh ? null : await this.callProvider(finnhub, () => this.deps.providers.profile.getProfile(symbol))

    const profileFailed = profile !== null && !profile.ok
    if (!metrics.ok && (profileIsFresh || profileFailed)) {
      if (cached) return toProfileDTO(symbol, cached)
      const reasons = [metrics, profile].flatMap((o) => (o && !o.ok ? [o] : []))
      const limited = reasons.find((o) => o.reason === "rate_limited")
      if (limited) throw rateLimitedError(limited.retryAfterSec)
      if (reasons.every((o) => o.reason === "not_found")) throw new AppError("NOT_FOUND", `No profile for ${symbol}`, 404)
      throw unavailableError()
    }

    const payload: ProfilePayload = {
      profile: profile?.ok ? profile.value : cachedProfile,
      metrics: metrics.ok ? metrics.value : (cached?.payload.metrics ?? null),
      profileFetchedAt: profile?.ok ? now.toISOString() : (cached?.payload.profileFetchedAt ?? now.toISOString()),
    }
    if (payload.profile === null && payload.metrics === null) throw new AppError("NOT_FOUND", `No profile for ${symbol}`, 404)
    const entry: CacheEntry<ProfilePayload> = { payload, provider: "finnhub", fetchedAt: now, expiresAt: expiresAt("metrics", now) }
    await this.deps.cache.putProfile(symbol, entry)
    return toProfileDTO(symbol, entry)
  }
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/services && npm run typecheck`
Expected: every service test passes, including `5 passed` in the search/profile file. Typecheck exits 0.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/services/MarketDataService.ts server/test/services/MarketDataService.searchProfile.test.ts
git commit -m "feat(server): add cached symbol search and merged company profile

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 7: Market routes and composition

### Task 19: `/api/market/*` routes and the container wiring

**Files:**
- Create: `server/src/schemas/market.ts`, `server/src/routes/api/market.ts`
- Modify: `server/src/container.ts` (whole file below), `server/src/app.ts` (register the market routes)
- Test: `server/test/routes/market.test.ts`

- [x] **Step 1: Write the failing route tests**

Create `server/test/routes/market.test.ts`:
```ts
import { afterEach, describe, expect, it, vi } from "vitest"
import type { Bar } from "../../src/providers/types.js"
import { buildTestApp } from "../support/app.js"
import { makeService } from "../support/market.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup(market = makeService()) {
  const built = await buildTestApp({ rateLimiter: market.limiter, marketData: market.service })
  app = built.app
  const headers = built.authHeaders()
  const get = (url: string) => built.app.inject({ method: "GET", url, headers })
  return { get, market }
}

describe("GET /api/market/quotes", () => {
  it("requires auth", async () => {
    await setup()
    const response = await app!.inject({ method: "GET", url: "/api/market/quotes?symbols=AAPL" })
    expect(response.statusCode).toBe(401)
  })

  it("authenticates before validating, so a bad query without a token is 401, not 400", async () => {
    await setup()
    const response = await app!.inject({ method: "GET", url: "/api/market/history?symbol=lower&range=2Y" })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("uppercases, trims and dedupes symbols and returns the wire shape", async () => {
    const { get } = await setup()
    const response = await get("/api/market/quotes?symbols=aapl,%20MSFT,AAPL")
    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(body.quotes.map((q: { symbol: string }) => q.symbol)).toEqual(["AAPL", "MSFT"])
    expect(Object.keys(body.quotes[0]).sort()).toEqual(
      ["asOf", "change", "changePercent", "fiftyTwoWeekHigh", "fiftyTwoWeekLow", "high", "low", "open", "previousClose", "price", "source", "stale", "symbol", "volume"],
    )
    expect(body.missing).toEqual([])
  })

  it("rejects invalid tickers and more than 50 symbols", async () => {
    const { get } = await setup()
    expect((await get("/api/market/quotes?symbols=AAPL,%24%24%24")).json().error.code).toBe("INVALID_INPUT")
    const tooMany = Array.from({ length: 51 }, (_, i) => `A${String.fromCharCode(65 + (i % 26))}${String.fromCharCode(65 + Math.floor(i / 26))}`).join(",")
    const response = await get(`/api/market/quotes?symbols=${tooMany}`)
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("INVALID_INPUT")
  })

  it("returns 503 with Retry-After when rate limited and nothing is cached", async () => {
    const market = makeService()
    market.limiter.denied.add("provider:finnhub")
    const { get } = await setup(market)
    const response = await get("/api/market/quotes?symbols=AAPL")
    expect(response.statusCode).toBe(503)
    expect(response.headers["retry-after"]).toBe("1")
    expect(response.json().error.code).toBe("UPSTREAM_RATE_LIMITED")
  })
})

describe("GET /api/market/history, /search, /profile", () => {
  it("serves history and validates the range", async () => {
    const bars: Bar[] = [{ t: "2026-11-19T00:00:00.000Z", c: "171.2" }, { t: "2026-11-20T00:00:00.000Z", c: "172.1" }]
    const { get } = await setup(makeService({ providers: { daily: { getDailyBars: vi.fn(async () => bars) } } }))
    const response = await get("/api/market/history?symbol=AAPL&range=1Y")
    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({ symbol: "AAPL", range: "1Y", points: bars, source: "tiingo", stale: false, delayedMinutes: null })
    expect((await get("/api/market/history?symbol=AAPL&range=2Y")).json().error.code).toBe("VALIDATION_ERROR")
  })

  it("serves search results and bounds the query length", async () => {
    const results = [{ symbol: "AAPL", name: "APPLE INC", exchange: null, type: "Common Stock" }]
    const { get } = await setup(makeService({ providers: { search: { search: vi.fn(async () => results) } } }))
    expect((await get("/api/market/search?q=app")).json()).toEqual({ results })
    expect((await get(`/api/market/search?q=${"a".repeat(31)}`)).statusCode).toBe(400)
    expect((await get("/api/market/search?q=%20%20")).statusCode).toBe(400)
  })

  it("returns 404 NOT_FOUND for an unknown profile", async () => {
    const { get } = await setup()
    const response = await get("/api/market/profile?symbol=ZZZZ")
    expect(response.statusCode).toBe(404)
    expect(response.json().error.code).toBe("NOT_FOUND")
  })
})
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/routes/market.test.ts`
Expected: FAIL. `Container` has no `marketData` yet (typecheck error), and the market routes return 404.

- [x] **Step 3: Implement the schemas**

Create `server/src/schemas/market.ts`:
```ts
import { Type, type TSchema } from "@sinclair/typebox"
import { SymbolSchema } from "./common.js"

/** Null-first unions (overview §8.1): with coercion off, Ajv tries `null` before the value type. */
const Nullable = <T extends TSchema>(schema: T) => Type.Union([Type.Null(), schema])

// Every querystring field is a string schema, so nothing depends on Ajv coercion.
export const QuotesQuerySchema = Type.Object({ symbols: Type.String({ minLength: 1, maxLength: 600 }) })

export const QuoteSchema = Type.Object({
  symbol: Type.String(),
  price: Type.String(),
  previousClose: Nullable(Type.String()),
  open: Nullable(Type.String()),
  high: Nullable(Type.String()),
  low: Nullable(Type.String()),
  change: Nullable(Type.String()),
  changePercent: Nullable(Type.Number()),
  volume: Nullable(Type.Integer()),
  fiftyTwoWeekHigh: Nullable(Type.String()),
  fiftyTwoWeekLow: Nullable(Type.String()),
  asOf: Type.String(),
  source: Type.String(),
  stale: Type.Boolean(),
})

export const QuotesResponseSchema = Type.Object({ quotes: Type.Array(QuoteSchema), missing: Type.Array(Type.String()) })

export const ChartRangeSchema = Type.Union([Type.Literal("1D"), Type.Literal("1W"), Type.Literal("1M"), Type.Literal("1Y"), Type.Literal("5Y")])

export const HistoryQuerySchema = Type.Object({ symbol: SymbolSchema, range: ChartRangeSchema })

export const HistoryResponseSchema = Type.Object({
  symbol: Type.String(),
  range: ChartRangeSchema,
  points: Type.Array(Type.Object({ t: Type.String(), c: Type.String() })),
  source: Type.String(),
  asOf: Type.String(),
  stale: Type.Boolean(),
  delayedMinutes: Nullable(Type.Integer()),
})

/** The pattern means "contains a non-space character", so whitespace-only queries get 400. */
export const SearchQuerySchema = Type.Object({ q: Type.String({ minLength: 1, maxLength: 30, pattern: "\\S" }) })

export const SearchResponseSchema = Type.Object({
  results: Type.Array(Type.Object({ symbol: Type.String(), name: Type.String(), exchange: Nullable(Type.String()), type: Type.String() })),
})

export const ProfileQuerySchema = Type.Object({ symbol: SymbolSchema })

export const ProfileResponseSchema = Type.Object({
  symbol: Type.String(),
  name: Nullable(Type.String()),
  exchange: Nullable(Type.String()),
  industry: Nullable(Type.String()),
  logoUrl: Nullable(Type.String()),
  marketCap: Nullable(Type.String()),
  peRatio: Nullable(Type.Number()),
  pbRatio: Nullable(Type.Number()),
  dividendYield: Nullable(Type.Number()),
  roe: Nullable(Type.Number()),
  roa: Nullable(Type.Number()),
  profitMargin: Nullable(Type.Number()),
  fiftyTwoWeekHigh: Nullable(Type.String()),
  fiftyTwoWeekLow: Nullable(Type.String()),
  beta: Nullable(Type.Number()),
  asOf: Type.String(),
})
```

- [x] **Step 4: Implement the route plugin**

Create `server/src/routes/api/market.ts`:
```ts
import type { FastifyPluginAsync } from "fastify"
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { RouteOptions } from "../../container.js"
import { AppError } from "../../lib/errors.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema, SYMBOL_REGEX } from "../../schemas/common.js"
import {
  HistoryQuerySchema,
  HistoryResponseSchema,
  ProfileQuerySchema,
  ProfileResponseSchema,
  QuotesQuerySchema,
  QuotesResponseSchema,
  SearchQuerySchema,
  SearchResponseSchema,
} from "../../schemas/market.js"

const MAX_SYMBOLS = 50

export function parseSymbols(raw: string): string[] {
  const symbols = [...new Set(raw.split(",").map((s) => s.trim().toUpperCase()).filter((s) => s.length > 0))]
  if (symbols.length === 0 || symbols.length > MAX_SYMBOLS) {
    throw new AppError("INVALID_INPUT", `symbols must list 1 to ${MAX_SYMBOLS} tickers`, 400)
  }
  const invalid = symbols.find((symbol) => !SYMBOL_REGEX.test(symbol))
  if (invalid) throw new AppError("INVALID_INPUT", `Invalid symbol: ${invalid}`, 400)
  return symbols
}

const errors = { 400: ErrorResponseSchema, 401: ErrorResponseSchema, 404: ErrorResponseSchema, 502: ErrorResponseSchema, 503: ErrorResponseSchema }

const marketRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)
  // onRequest, not preHandler: 401 comes before querystring validation.
  app.addHook("onRequest", authenticate)

  app.get("/quotes", { schema: { querystring: QuotesQuerySchema, response: { 200: QuotesResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getQuotes(parseSymbols(request.query.symbols)),
  )

  app.get("/history", { schema: { querystring: HistoryQuerySchema, response: { 200: HistoryResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getHistory(request.query.symbol, request.query.range),
  )

  app.get("/search", { schema: { querystring: SearchQuerySchema, response: { 200: SearchResponseSchema, ...errors } } }, async (request) => ({
    results: await container.marketData.search(request.query.q),
  }))

  app.get("/profile", { schema: { querystring: ProfileQuerySchema, response: { 200: ProfileResponseSchema, ...errors } } }, async (request) =>
    container.marketData.getProfile(request.query.symbol),
  )
}

export default marketRoutes
```

- [x] **Step 5: Wire the container and the app**

Replace `server/src/container.ts` with:
```ts
import type { Config } from "./config.js"
import type { MarketCacheRepository } from "./db/MarketCacheRepository.js"
import { MockMarketCacheRepository } from "./db/MockMarketCacheRepository.js"
import { MockUserRepository } from "./db/MockUserRepository.js"
import { NeonMarketCacheRepository } from "./db/NeonMarketCacheRepository.js"
import { NeonUserRepository } from "./db/NeonUserRepository.js"
import { neonSql, type Sql } from "./db/sql.js"
import type { UserRepository } from "./db/UserRepository.js"
import type { FastifyBaseLogger } from "fastify"
import { fixedClock, systemClock, type Clock } from "./lib/clock.js"
import { createLogger } from "./lib/logger.js"
import { AlpacaProvider } from "./providers/alpaca.js"
import { FinnhubProvider } from "./providers/finnhub.js"
import { TiingoProvider } from "./providers/tiingo.js"
import { ProviderError, type ProviderName } from "./providers/types.js"
import { AuthService } from "./services/AuthService.js"
import { MarketDataService, type MarketProviders } from "./services/MarketDataService.js"
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
  marketCache: MarketCacheRepository
  marketData: MarketDataService
}

/** Options every route plugin receives. */
export interface RouteOptions {
  container: Container
}

/** Composition root: build every repository/service exactly once per cold start. No I/O happens here. */
export function createContainer(config: Config): Container {
  const sql = neonSql(config.databaseUrl)
  const clock = systemClock
  const logger = createLogger(config.logLevel)
  const users = new NeonUserRepository(sql)
  const rateLimiter = new PostgresRateLimiter(sql, clock)
  const marketCache = new NeonMarketCacheRepository(sql)
  const finnhub = new FinnhubProvider(config.finnhubApiKey)
  const providers: MarketProviders = {
    quotes: finnhub,
    search: finnhub,
    profile: finnhub,
    daily: new TiingoProvider(config.tiingoApiKey),
    intraday: new AlpacaProvider(config.alpacaKeyId, config.alpacaSecretKey, clock),
  }
  return {
    clock,
    logger,
    sql,
    users,
    rateLimiter,
    auth: new AuthService(users, rateLimiter, clock),
    marketCache,
    // The same logger Fastify uses, so `market.provider_error` warnings reach the Vercel runtime logs.
    marketData: new MarketDataService({ cache: marketCache, limiter: rateLimiter, providers, clock, logger: logger.child({ component: "market" }) }),
  }
}

/** The mock container has no database unless a test passes `{ sql }` from `createTestDb()`. */
const noDatabase: Sql = async () => {
  throw new Error("createMockContainer has no database; pass { sql } from createTestDb()")
}

const unavailable = (provider: ProviderName) => async (): Promise<never> => {
  throw new ProviderError(provider, "upstream")
}

/** Providers that always fail; route tests that need data inject their own MarketDataService. */
export function unavailableProviders(): MarketProviders {
  return {
    quotes: { getQuote: unavailable("finnhub") },
    search: { search: unavailable("finnhub") },
    profile: { getProfile: unavailable("finnhub"), getMetrics: unavailable("finnhub") },
    daily: { getDailyBars: unavailable("tiingo") },
    intraday: { getIntradayBars: unavailable("alpaca") },
  }
}

/** In-memory container for `app.inject` tests. Defaults to Friday 2026-11-20 10:00 ET (market open). */
export function createMockContainer(overrides: Partial<Container> = {}): Container {
  const clock = overrides.clock ?? fixedClock(new Date("2026-11-20T15:00:00.000Z"))
  const users = overrides.users ?? new MockUserRepository()
  const rateLimiter = overrides.rateLimiter ?? new MockRateLimiter()
  const marketCache = overrides.marketCache ?? new MockMarketCacheRepository()
  const logger = overrides.logger ?? createLogger("silent")
  return {
    clock,
    logger,
    sql: overrides.sql ?? noDatabase,
    users,
    rateLimiter,
    auth: overrides.auth ?? new AuthService(users, rateLimiter, clock),
    marketCache,
    marketData: overrides.marketData ?? new MarketDataService({ cache: marketCache, limiter: rateLimiter, providers: unavailableProviders(), clock, logger }),
  }
}
```

In `server/src/app.ts`, add `import marketRoutes from "./routes/api/market.js"` below the other route imports. Add this line after the auth route registration:
```ts
  await app.register(marketRoutes, { prefix: "/api/market", container })
```

- [x] **Step 6: Run the tests and typecheck**

Run: `npm test && npm run typecheck`
Expected: every test file passes, including `8 passed` in `test/routes/market.test.ts`. Typecheck exits 0.

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/src/schemas/market.ts server/src/routes/api/market.ts server/src/container.ts server/src/app.ts server/test/routes/market.test.ts
git commit -m "feat(server): expose authenticated /api/market quotes, history, search, profile

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 8: Docs and deploy

### Task 20: `server/README.md`

**Files:**
- Create: `server/README.md`

- [x] **Step 1: Write the README**

Create `server/README.md`:
````markdown
# wait-server

Backend for the Wait iOS app: anonymous auth and a cached, rate-limited market-data proxy (plan 04). Watchlist sync (plan 05) and daily ladder alerts (plan 06) build on it. Shared contracts are in `../docs/superpowers/plans/2026-11-22-wait-00-overview.md`.

## Stack
Fastify 5 + TypeBox · TypeScript ESM (NodeNext, `.js` import suffixes) · Neon Postgres via raw SQL (`src/db/sql.ts`) · vitest + PGlite · Vercel (one function built from `src/server.ts`).

## Layout
- `src/app.ts`: `buildApp({ config, container })` sets up plugins, the error envelope and the routes.
- `src/container.ts`: the composition root. `createContainer(config)` builds the Neon repositories, live providers and services. `createMockContainer()` builds in-memory versions for tests.
- `src/routes/**`: thin route plugins with TypeBox schemas on every route.
- `src/services/**`: business logic: `AuthService`, `MarketDataService`, and `RateLimiter` (a token bucket in Postgres).
- `src/db/**`: one interface per repository, each with `Neon*` (SQL) and `Mock*` (in-memory) implementations.
- `src/providers/**`: adapters for Finnhub (quotes, search, profile), Tiingo (daily history) and Alpaca (intraday bars, 15 min delayed).
- `src/domain/**`: the ET market calendar and the cache TTL rules.
- `migrations/NNN_name.sql`: re-runnable SQL migrations, applied by `npm run migrate`.

## Commands
```sh
npm ci
npm run typecheck   # src + test + scripts
npm test            # vitest; repository SQL runs against in-process PGlite
npm run dev         # http://localhost:3000 (reads .env.development.local then .env.local)
npm run migrate     # applies pending migrations to $DATABASE_URL (prefers DATABASE_URL_UNPOOLED)
TEST_DATABASE_URL=postgres://… npm run test:neon   # same repository suites against a disposable Neon branch
```

## Environment
See `.env.example` and overview §8.2. The app fails at cold start, naming any missing variable.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Neon pooled URL (Vercel ↔ Neon integration) |
| `DATABASE_URL_UNPOOLED` | for `npm run migrate` | Direct URL from the same integration; migrations fall back to `DATABASE_URL` |
| `JWT_SECRET` | yes | 32+ characters |
| `FINNHUB_API_KEY` | yes | sent as the `X-Finnhub-Token` header |
| `TIINGO_API_KEY` | yes | sent as `Authorization: Token …` |
| `ALPACA_KEY_ID`, `ALPACA_SECRET_KEY` | yes | Alpaca paper account (Basic data) |
| `LOG_LEVEL` | no | default `info` |
| `NODE_ENV` | no | `production` on Vercel |

## API (plan 04)
All `/api/market/*` routes need `Authorization: Bearer <token>`. Every error is returned as `{ "error": { "code", "message" } }`.

| Route | Notes |
|---|---|
| `GET /health` | `{ status, timestamp }` |
| `POST /api/auth/register` `{ anonymousId }` | Returns `{ token, user: { id } }`. Idempotent. Rate-limited per IP (20/min) and per id (5/min). |
| `DELETE /api/auth/account` | 204. Deletes everything that belongs to the user. |
| `GET /api/market/quotes?symbols=AAPL,MSFT` | 1–50 symbols, `{ quotes, missing }`. Quotes stay fresh for 3 min while the market is open. |
| `GET /api/market/history?symbol=AAPL&range=1D\|1W\|1M\|1Y\|5Y` | 1D and 1W come from Alpaca, 15 min delayed. 1M, 1Y and 5Y come from one cached Tiingo `daily5y` series. |
| `GET /api/market/search?q=app` | US common stock, ETP and ADR only. Cached 7 days. |
| `GET /api/market/profile?symbol=AAPL` | Finnhub profile2 (refreshed every 7 days) plus metrics (refreshed daily). |

When a provider is rate-limited, the API serves the cached value with `stale: true`. If nothing is cached, it returns `503 UPSTREAM_RATE_LIMITED` with `Retry-After`.

## Data licensing
Finnhub, Tiingo and Alpaca free tiers are **personal use only**. This server is for the owner and a few friends. Before any public release, move to a plan that allows external display. Only the adapters in `src/providers/` would change.
````

- [x] **Step 2: Commit**

```bash
cd /Users/ckai/code/Wait
git add server/README.md
git commit -m "docs(server): add README for wait-server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 21: Deploy to Vercel and smoke test `(manual: user)`

The executor stops at each `(manual: user)` step, prints the instructions and waits for the user to confirm.

**Files:** none (dashboard and CLI only)

- [ ] **Step 1: Create the provider keys `(manual: user)`** — SKIPPED (manual)

Create the Finnhub key, the Tiingo token, and the Alpaca **paper** Key ID and Secret (Prerequisites §3). Keep them in a password manager. Never paste them into the repo.

- [ ] **Step 2: Create the Vercel project `(manual: user)`** — SKIPPED (manual)

In the Vercel dashboard:
1. **Add New → Project →** import the `Wait` GitHub repo.
2. Set **Root Directory** to `server`.
3. Set **Framework Preset** to Other.
4. After creation, open **Settings → General → Node.js Version** and choose **22.x**.

The legacy `builds` key in `vercel.json` makes Vercel ignore the dashboard build settings. The warning it shows about this is expected.

- [ ] **Step 3: Attach Neon `(manual: user)`** — SKIPPED (manual)

In the project, go to **Storage → Connect Database → Neon**. Create the database and connect it to all environments. This adds `DATABASE_URL`, `DATABASE_URL_UNPOOLED` and the `PG*` variables.

- [ ] **Step 4: Add the env vars `(manual: user)`** — SKIPPED (manual)

```bash
cd /Users/ckai/code/Wait/server
npx vercel@latest link                    # choose the project from Step 2
# Production and Preview both get every secret, so preview deploys don't fail fast in loadConfig.
JWT=$(openssl rand -base64 48 | tr -d '\n')
for env in production preview; do printf '%s' "$JWT" | npx vercel@latest env add JWT_SECRET "$env"; done
unset JWT
for name in FINNHUB_API_KEY TIINGO_API_KEY ALPACA_KEY_ID ALPACA_SECRET_KEY; do
  for env in production preview; do npx vercel@latest env add "$name" "$env"; done   # paste the value at each prompt
done
npx vercel@latest env pull .env.local --environment=production   # gitignored
```
Expected: each `env add` prints `Added Environment Variable … to Project`. For `preview`, answer the git-branch prompt with an empty value, meaning all preview branches. `.env.local` now contains the names above; never print its values.

- [ ] **Step 5: Run the migrations against Neon** — SKIPPED (manual)

Run: `cd /Users/ckai/code/Wait/server && npm run migrate`
Expected: `migrating <your-neon-host>`, then `migrations applied: [1, 2] skipped: []`. Run it again and expect `migrations applied: [] skipped: [1, 2]`.

- [ ] **Step 6: Deploy** — SKIPPED (manual)

Run: `npx vercel@latest --prod`
Expected: the output ends with `Production: https://<project>.vercel.app`. Write the URL down; Task 26 Step 7 (Chunk 11) turns it into `WAIT_API_BASE_URL`.

- [ ] **Step 7: Smoke test with curl** — SKIPPED (manual)

```bash
export WAIT_API_BASE_URL=https://<project>.vercel.app
curl -s "$WAIT_API_BASE_URL/health"
TOKEN=$(curl -s -X POST "$WAIT_API_BASE_URL/api/auth/register" -H 'content-type: application/json' \
  -d "{\"anonymousId\":\"$(uuidgen)\"}" | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8")).token')
curl -s "$WAIT_API_BASE_URL/api/market/quotes?symbols=AAPL,MSFT" -H "authorization: Bearer $TOKEN"
curl -s "$WAIT_API_BASE_URL/api/market/history?symbol=AAPL&range=1Y" -H "authorization: Bearer $TOKEN" | node -pe 'const b=JSON.parse(require("fs").readFileSync(0,"utf8")); [b.range, b.points.length, b.source, b.stale].join(" ")'
curl -s "$WAIT_API_BASE_URL/api/market/history?symbol=AAPL&range=1D" -H "authorization: Bearer $TOKEN" | node -pe 'const b=JSON.parse(require("fs").readFileSync(0,"utf8")); [b.range, b.points.length, b.source, b.delayedMinutes].join(" ")'
curl -s "$WAIT_API_BASE_URL/api/market/search?q=apple" -H "authorization: Bearer $TOKEN"
curl -s "$WAIT_API_BASE_URL/api/market/profile?symbol=AAPL" -H "authorization: Bearer $TOKEN"
curl -s -o /dev/null -w "%{http_code}\n" "$WAIT_API_BASE_URL/api/market/quotes?symbols=AAPL"
```
Expected, in order:
1. `{"status":"ok","timestamp":"…"}`.
2. `{"quotes":[{"symbol":"AAPL","price":"…","source":"finnhub","stale":false,…},{"symbol":"MSFT",…}],"missing":[]}`.
3. `1Y 252 tiingo false` (or slightly fewer than 252 points for a recent IPO).
4. `1D <n> alpaca 15`. `n` is between 1 and 78, depending on the time of day.
5. `{"results":[{"symbol":"AAPL","name":"APPLE INC",…}…]}`.
6. A profile with `"name":"Apple Inc"` and a numeric `peRatio`.
7. `401`, because there is no token.

If a market call returns 502 `UPSTREAM_UNAVAILABLE`:
1. Open the Vercel runtime logs and find the `market.provider_error` warning. It names the provider, the error kind and the HTTP status.
2. Recheck the matching key with `npx vercel env ls`.

- [ ] **Step 8: Record the deploy** — SKIPPED (manual)

There is nothing to commit. Note the production URL in the PR description for this plan.

## Chunk 9: iOS `APIClient` target

From here on, Swift paths are relative to `/Users/ckai/code/Wait/Wait`, and every new Swift file starts with the repo header (overview §5.1). Run commands from the repo root `/Users/ckai/code/Wait`, using the scripts plan 02 created:
- `scripts/test-waitkit.sh <TestTarget>[/<Suite>]` runs package tests. It prints only errors, failing tests and the summary.
- `scripts/build-app.sh [WaitWatch]` builds the app (default) or the watch app.

### Task 22: `APIClient` target, `WireDates`, `APIError`

**Files:**
- Modify: `Packages/WaitKit/Package.swift`
- Create: `Packages/WaitKit/Sources/APIClient/WireDates.swift`, `Packages/WaitKit/Sources/APIClient/APIError.swift`
- Test: `Packages/WaitKit/Tests/APIClientTests/WireDatesTests.swift`, `Packages/WaitKit/Tests/APIClientTests/APIErrorTests.swift`

- [x] **Step 1: Declare the targets**

In `Packages/WaitKit/Package.swift`, add this target to `targets:` right after the `MarketDataClient` target. It uses plan 02's `Target.Dependency` shorthands.
```swift
    .target(name: "APIClient", dependencies: ["Domain", .dependencies, .dependenciesMacros]),
```
Add this alongside the other test targets. Every module the tests import is declared explicitly:
```swift
    .testTarget(name: "APIClientTests", dependencies: ["APIClient", "Domain", .dependencies, .dependenciesTestSupport]),
```

- [x] **Step 2: Write the failing tests**

Create `Packages/WaitKit/Tests/APIClientTests/WireDatesTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Foundation
import Testing

// MARK: - WireDatesTests

@Suite
struct WireDatesTests {
  private let fridayClose = Date(timeIntervalSince1970: 1_795_208_400) // 2026-11-20T21:00:00Z

  @Test
  func formatsUTCWithMilliseconds() {
    #expect(WireDates.string(from: fridayClose) == "2026-11-20T21:00:00.000Z")
  }

  @Test
  func parsesWithAndWithoutFractionalSeconds() {
    #expect(WireDates.date(from: "2026-11-20T21:00:00.000Z") == fridayClose)
    #expect(WireDates.date(from: "2026-11-20T21:00:00Z") == fridayClose)
    #expect(WireDates.date(from: "yesterday") == nil)
  }

  @Test
  func roundTripsThroughTheCoders() throws {
    struct Box: Codable, Equatable { let at: Date }
    let data = try WireDates.makeEncoder().encode(Box(at: fridayClose))
    #expect(String(decoding: data, as: UTF8.self) == #"{"at":"2026-11-20T21:00:00.000Z"}"#)
    #expect(try WireDates.makeDecoder().decode(Box.self, from: data) == Box(at: fridayClose))
  }
}
```

Create `Packages/WaitKit/Tests/APIClientTests/APIErrorTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Foundation
import Testing

// MARK: - APIErrorTests

@Suite
struct APIErrorTests {
  @Test
  func decodesTheServerErrorEnvelopeAndRetryAfter() {
    let body = Data(#"{"error":{"code":"UPSTREAM_RATE_LIMITED","message":"Slow down"}}"#.utf8)
    let error = APIError(status: 503, body: body, retryAfterHeader: "30")
    #expect(error == APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "Slow down", retryAfter: .seconds(30)))
    #expect(error.localizedDescription == "Slow down")
  }

  @Test
  func fallsBackToTheHTTPStatusWhenTheBodyIsNotAnEnvelope() {
    let error = APIError(status: 502, body: Data("<html>".utf8), retryAfterHeader: nil)
    #expect(error.code == "HTTP_502")
    #expect(error.retryAfter == nil)
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail** — NOT RUN (code-only; red confirmed in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: the build fails with `cannot find 'WireDates' in scope` and `cannot find 'APIError' in scope`.

- [x] **Step 4: Implement `WireDates` and `APIError`**

Create `Packages/WaitKit/Sources/APIClient/WireDates.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WireDates

/// ISO 8601 UTC with milliseconds, which is what the server emits via `toISOString()` (overview §9).
/// Decoding also accepts whole seconds.
public enum WireDates {
  // MARK: Public

  public static func string(from date: Date) -> String {
    fractional.format(date)
  }

  public static func date(from string: String) -> Date? {
    (try? fractional.parse(string)) ?? (try? whole.parse(string))
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      guard let parsed = WireDates.date(from: raw) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(raw)")
      }
      return parsed
    }
    return decoder
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(WireDates.string(from: date))
    }
    return encoder
  }

  // MARK: Private

  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let whole = Date.ISO8601FormatStyle()
}
```

Create `Packages/WaitKit/Sources/APIClient/APIError.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - APIError

/// Every failure from the Wait backend. `status == 0` means the request never got an HTTP response.
public struct APIError: Error, Equatable, Sendable {
  // MARK: Lifecycle

  public init(status: Int, code: String, message: String, retryAfter: Duration? = nil) {
    self.status = status
    self.code = code
    self.message = message
    self.retryAfter = retryAfter
  }

  /// Builds an error from a non-2xx body shaped `{ "error": { "code", "message" } }`.
  public init(status: Int, body: Data, retryAfterHeader: String?) {
    let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
    self.init(
      status: status,
      code: envelope?.error.code ?? "HTTP_\(status)",
      message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
      retryAfter: retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { .seconds($0) }
    )
  }

  // MARK: Public

  public static let misconfigured = APIError(status: 0, code: "MISCONFIGURED", message: "WaitAPIBaseURL is missing from Info.plist")

  public let status: Int
  public let code: String
  public let message: String
  public let retryAfter: Duration?

  public static func transport(_ message: String) -> APIError {
    APIError(status: 0, code: "NETWORK", message: message)
  }

  public static func decoding(status: Int, _ message: String) -> APIError {
    APIError(status: status, code: "DECODING", message: message)
  }

  // MARK: Private

  private struct Envelope: Decodable {
    struct Body: Decodable {
      let code: String
      let message: String
    }

    let error: Body
  }
}

// MARK: LocalizedError

extension APIError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass** — NOT RUN (code-only; 5/5 pass in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: `** TEST SUCCEEDED **`, with 5 tests passing.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/APIClient Wait/Packages/WaitKit/Tests/APIClientTests
git commit -m "feat(apiclient): add APIClient target with wire dates and error envelope

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 23: `KeychainClient` and `IdentityClient`

**Files:**
- Create: `Packages/WaitKit/Sources/APIClient/KeychainClient.swift`, `Packages/WaitKit/Sources/APIClient/IdentityClient.swift`
- Test: `Packages/WaitKit/Tests/APIClientTests/IdentityClientTests.swift`

- [x] **Step 1: Write the failing tests**

The live Keychain can't run in a hostless package test bundle (it fails with `-34018`, risk 9). Tests therefore use `KeychainClient.inMemory()`, and the live code is verified on a device in Task 30.

Create `Packages/WaitKit/Tests/APIClientTests/IdentityClientTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Foundation
import Testing

// MARK: - IdentityClientTests

@Suite
struct IdentityClientTests {
  @Test
  func createsTheIDOnceAndStoresItSynchronizable() throws {
    let keychain = KeychainClient.inMemory()
    let identity = IdentityClient.live(keychain: keychain)
    let first = try identity.anonymousID()
    let second = try identity.anonymousID()
    #expect(first == second)
    #expect(try keychain.read(IdentityClient.account, true) == Data(first.uuidString.utf8))
    #expect(try keychain.read(IdentityClient.account, false) == nil)
  }

  @Test
  func resetMakesTheNextCallCreateANewID() throws {
    let identity = IdentityClient.live(keychain: .inMemory())
    let before = try identity.anonymousID()
    try identity.reset()
    #expect(try identity.anonymousID() != before)
  }

  @Test
  func replacesACorruptStoredValue() throws {
    let keychain = KeychainClient.inMemory()
    try keychain.write(Data("not-a-uuid".utf8), IdentityClient.account, true)
    let id = try IdentityClient.live(keychain: keychain).anonymousID()
    #expect(try keychain.read(IdentityClient.account, true) == Data(id.uuidString.utf8))
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail** — NOT RUN (code-only; red confirmed in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests/IdentityClientTests`
Expected: the build fails with `cannot find 'KeychainClient' in scope`.

- [x] **Step 3: Implement both clients**

Create `Packages/WaitKit/Sources/APIClient/KeychainClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation
import Security

// MARK: - KeychainClient

/// Generic-password items under service `com.chenkai.wait`. Every query sets `kSecAttrSynchronizable`
/// explicitly (risk 9), so synchronizable and device-only items never shadow each other.
@DependencyClient
public struct KeychainClient: Sendable {
  public var read: @Sendable (_ account: String, _ synchronizable: Bool) throws -> Data?
  public var write: @Sendable (_ data: Data, _ account: String, _ synchronizable: Bool) throws -> Void
  public var delete: @Sendable (_ account: String, _ synchronizable: Bool) throws -> Void
}

// MARK: - KeychainError

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

// MARK: - KeychainClient + DependencyKey

extension KeychainClient: DependencyKey {
  // MARK: Public

  public static let service = "com.chenkai.wait"

  public static let liveValue = KeychainClient(
    read: { account, synchronizable in
      var query = baseQuery(account: account, synchronizable: synchronizable)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
      }
    },
    write: { data, account, synchronizable in
      let query = baseQuery(account: account, synchronizable: synchronizable)
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]
      var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
      }
      guard status == errSecSuccess else { throw KeychainError(status: status) }
    },
    delete: { account, synchronizable in
      let status = SecItemDelete(baseQuery(account: account, synchronizable: synchronizable) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
  )

  public static let testValue = KeychainClient()

  /// For tests and previews.
  public static func inMemory() -> KeychainClient {
    let store = LockIsolated<[String: Data]>([:])
    return KeychainClient(
      read: { account, synchronizable in store.value["\(synchronizable):\(account)"] },
      write: { data, account, synchronizable in store.withValue { $0["\(synchronizable):\(account)"] = data } },
      delete: { account, synchronizable in store.withValue { $0["\(synchronizable):\(account)"] = nil } }
    )
  }

  // MARK: Private

  private static func baseQuery(account: String, synchronizable: Bool) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
    ]
  }
}

extension DependencyValues {
  public var keychain: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}
```
If Swift 6 reports `reference to var 'kSecClass…' is not concurrency-safe`, copy the constants into `private nonisolated(unsafe) static let` properties of the extension. Do not change their values.

Create `Packages/WaitKit/Sources/APIClient/IdentityClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation

// MARK: - IdentityClient

/// The anonymous identity (overview D14). It lives in iCloud Keychain (synchronizable,
/// AfterFirstUnlock), so the user's devices share one server account and it survives reinstalls.
@DependencyClient
public struct IdentityClient: Sendable {
  /// Get-or-create. Never returns two different IDs for concurrent first calls on one device.
  public var anonymousID: @Sendable () throws -> UUID
  /// Deletes the ID on every device that shares iCloud Keychain. The next `anonymousID()` mints a new one.
  public var reset: @Sendable () throws -> Void
}

extension IdentityClient {
  public static let account = "anonymous-id"

  public static func live(keychain: KeychainClient) -> IdentityClient {
    let lock = LockIsolated(())
    return IdentityClient(
      anonymousID: {
        try lock.withValue { _ in
          if
            let data = try keychain.read(account, true),
            let raw = String(data: data, encoding: .utf8),
            let id = UUID(uuidString: raw)
          {
            return id
          }
          let id = UUID()
          try keychain.write(Data(id.uuidString.utf8), account, true)
          return id
        }
      },
      reset: { try keychain.delete(account, true) }
    )
  }
}

// MARK: - IdentityClient + DependencyKey

extension IdentityClient: DependencyKey {
  public static let liveValue = IdentityClient.live(keychain: .liveValue)
  public static let testValue = IdentityClient()
}

extension DependencyValues {
  public var identity: IdentityClient {
    get { self[IdentityClient.self] }
    set { self[IdentityClient.self] = newValue }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass** — NOT RUN (code-only; 8/8 pass in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: `** TEST SUCCEEDED **`, with 8 tests passing.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/APIClient/KeychainClient.swift Wait/Packages/WaitKit/Sources/APIClient/IdentityClient.swift Wait/Packages/WaitKit/Tests/APIClientTests/IdentityClientTests.swift
git commit -m "feat(apiclient): add synchronizable keychain identity

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 10: iOS `HTTPSession` and endpoints

### Task 24: `HTTPSession` (register on first use, re-register once on 401)

**Files:**
- Create: `Packages/WaitKit/Sources/APIClient/DTOs/AuthDTOs.swift`, `Packages/WaitKit/Sources/APIClient/HTTPSession.swift`
- Create: `Packages/WaitKit/Tests/APIClientTests/Support/StubURLProtocol.swift`
- Test: `Packages/WaitKit/Tests/APIClientTests/HTTPSessionTests.swift`

- [x] **Step 1: Write the URL stub**

The stub routes each request by its unique host, so suites can run in parallel. Create `Packages/WaitKit/Tests/APIClientTests/Support/StubURLProtocol.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Foundation

// MARK: - StubURLProtocol

final class StubURLProtocol: URLProtocol {
  // MARK: Internal

  struct Reply: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]
  }

  typealias Handler = @Sendable (URLRequest) -> Reply

  /// Registers a handler under a fresh host and returns its base URL.
  static func stub(_ handler: @escaping Handler) -> URL {
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    handlers.withValue { $0[host] = handler }
    return URL(string: "https://\(host)")!
  }

  static func requests(for baseURL: URL) -> [URLRequest] {
    captured.value[baseURL.host() ?? ""] ?? []
  }

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var request = request
    if request.httpBody == nil, let stream = request.httpBodyStream {
      request.httpBody = Data(reading: stream)
    }
    let host = request.url?.host() ?? ""
    let recorded = request
    Self.captured.withValue { $0[host, default: []].append(recorded) }
    guard let url = request.url, let handler = Self.handlers.value[host] else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    let reply = handler(request)
    let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  // MARK: Private

  private static let handlers = LockIsolated<[String: Handler]>([:])
  private static let captured = LockIsolated<[String: [URLRequest]]>([:])
}

func jsonReply(_ status: Int = 200, _ json: String, headers: [String: String] = [:]) -> StubURLProtocol.Reply {
  StubURLProtocol.Reply(status: status, body: Data(json.utf8), headers: ["Content-Type": "application/json"].merging(headers) { $1 })
}

extension Data {
  init(reading stream: InputStream) {
    self.init()
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      append(buffer, count: read)
    }
  }
}
```

- [x] **Step 2: Write the failing tests**

Create `Packages/WaitKit/Tests/APIClientTests/HTTPSessionTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Dependencies
import Foundation
import Testing

// MARK: - HTTPSessionTests

@Suite
struct HTTPSessionTests {
  private struct OK: Decodable, Equatable, Sendable { let ok: Bool }
  private struct Echo: Codable, Equatable, Sendable { let value: String }

  private let anonymousID = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!

  /// Serves tokens in `tokens` order on register; `accept` decides which bearer tokens /api/x accepts.
  private func makeSession(tokens: [String], accept: @escaping @Sendable (String?) -> Bool) -> (HTTPSession, URL, LockIsolated<Int>) {
    let registers = LockIsolated(0)
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register":
          let index = registers.withValue { count -> Int in
            count += 1
            return count - 1
          }
          return jsonReply(200, #"{"token":"\#(tokens[min(index, tokens.count - 1)])","user":{"id":"u1"}}"#)
        case "/api/x":
          let header = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
          return accept(header)
            ? jsonReply(200, #"{"ok":true}"#)
            : jsonReply(401, #"{"error":{"code":"UNAUTHORIZED","message":"Invalid or expired token"}}"#)
        case "/api/echo":
          return StubURLProtocol.Reply(status: 200, body: request.httpBody ?? Data())
        default:
          return jsonReply(404, #"{"error":{"code":"NOT_FOUND","message":"nope"}}"#)
      }
    }
    let id = anonymousID
    return (HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id }), base, registers)
  }

  @Test
  func registersOnFirstUseThenReusesTheToken() async throws {
    let (session, base, registers) = makeSession(tokens: ["t1"]) { $0 == "t1" }
    let first: OK = try await session.get("/api/x", query: [URLQueryItem(name: "symbols", value: "AAPL,MSFT")])
    let second: OK = try await session.get("/api/x")
    #expect(first == OK(ok: true) && second == OK(ok: true))
    #expect(registers.value == 1)
    let requests = StubURLProtocol.requests(for: base)
    let register = try #require(requests.first { $0.url?.path() == "/api/auth/register" })
    #expect(register.httpMethod == "POST")
    #expect(register.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"anonymousId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"}"#)
    #expect(requests.contains { $0.url?.query() == "symbols=AAPL,MSFT" })
  }

  @Test
  func reRegistersOnceOn401AndRetries() async throws {
    let (session, _, registers) = makeSession(tokens: ["stale", "fresh"]) { $0 == "fresh" }
    let result: OK = try await session.get("/api/x")
    #expect(result == OK(ok: true))
    #expect(registers.value == 2)
  }

  @Test
  func surfacesASecond401() async {
    let (session, _, registers) = makeSession(tokens: ["a", "b"]) { _ in false }
    await #expect(throws: APIError(status: 401, code: "UNAUTHORIZED", message: "Invalid or expired token")) {
      let _: OK = try await session.get("/api/x")
    }
    #expect(registers.value == 2)
  }

  @Test
  func postsEncodableBodiesAndDecodesResponses() async throws {
    let (session, _, _) = makeSession(tokens: ["t1"]) { _ in true }
    let echoed: Echo = try await session.post("/api/echo", body: Echo(value: "hello"))
    #expect(echoed == Echo(value: "hello"))
  }

  @Test
  func mapsErrorEnvelopesWithRetryAfter() async {
    let base = StubURLProtocol.stub { request in
      request.url?.path() == "/api/auth/register"
        ? jsonReply(200, #"{"token":"t","user":{"id":"u"}}"#)
        : jsonReply(503, #"{"error":{"code":"UPSTREAM_RATE_LIMITED","message":"Slow down"}}"#, headers: ["Retry-After": "30"])
    }
    let id = anonymousID
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })
    await #expect(throws: APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "Slow down", retryAfter: .seconds(30))) {
      let _: OK = try await session.get("/api/market/quotes")
    }
  }

  @Test
  func concurrentFirstCallsRegisterOnce() async throws {
    let (session, _, registers) = makeSession(tokens: ["t1"]) { $0 == "t1" }
    async let a: OK = session.get("/api/x")
    async let b: OK = session.get("/api/x")
    _ = try await (a, b)
    #expect(registers.value == 1)
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail** — NOT RUN (code-only; red confirmed in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests/HTTPSessionTests`
Expected: the build fails with `cannot find 'HTTPSession' in scope`.

- [x] **Step 4: Implement the auth DTOs and `HTTPSession`**

Create `Packages/WaitKit/Sources/APIClient/DTOs/AuthDTOs.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - RegisterRequestDTO

struct RegisterRequestDTO: Encodable, Sendable {
  let anonymousId: String
}

// MARK: - RegisterResponseDTO

struct RegisterResponseDTO: Decodable, Sendable {
  struct User: Decodable, Sendable {
    let id: String
  }

  let token: String
  let user: User
}
```

Create `Packages/WaitKit/Sources/APIClient/HTTPSession.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - APIRequest

public struct APIRequest: Sendable {
  // MARK: Lifecycle

  public init(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil, requiresAuth: Bool = true) {
    self.method = method
    self.path = path
    self.query = query
    self.body = body
    self.requiresAuth = requiresAuth
  }

  // MARK: Public

  public var method: String
  public var path: String
  public var query: [URLQueryItem]
  public var body: Data?
  public var requiresAuth: Bool
}

// MARK: - HTTPSession

/// The one connection to the Wait backend (overview §9). The JWT lives in memory only.
/// The first authenticated call registers with the anonymous ID. A 401 re-registers once and retries once.
/// Concurrent callers share a single in-flight registration.
public actor HTTPSession {
  // MARK: Lifecycle

  public init(baseURL: URL, session: URLSession = .shared, anonymousID: @escaping @Sendable () throws -> UUID) {
    self.baseURL = baseURL
    self.session = session
    self.anonymousID = anonymousID
  }

  // MARK: Public

  public func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
    try decode(try await send(APIRequest(method: "GET", path: path, query: query)))
  }

  public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response {
    try decode(try await send(APIRequest(method: "POST", path: path, body: try encode(body))))
  }

  /// For endpoints that answer 204.
  public func post<Body: Encodable & Sendable>(_ path: String, body: Body) async throws {
    _ = try await send(APIRequest(method: "POST", path: path, body: try encode(body)))
  }

  public func delete(_ path: String) async throws {
    _ = try await send(APIRequest(method: "DELETE", path: path))
  }

  /// Raw call with auth and the single 401 retry. Throws `APIError` for every non-2xx.
  public func send(_ request: APIRequest) async throws -> Data {
    var token = request.requiresAuth ? try await validToken() : nil
    var (data, response) = try await perform(request, token: token)
    if response.statusCode == 401, request.requiresAuth {
      token = try await validToken(replacing: token)
      (data, response) = try await perform(request, token: token)
    }
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    return data
  }

  // MARK: Private

  private let baseURL: URL
  private let session: URLSession
  private let anonymousID: @Sendable () throws -> UUID
  private var token: String?
  private var registration: Task<String, any Error>?

  /// Returns the cached token unless it is `stale` (the one that just got a 401). Concurrent 401s for the
  /// same stale token share one registration; a caller holding an older token gets the newer one directly.
  private func validToken(replacing stale: String? = nil) async throws -> String {
    if let token, token != stale {
      return token
    }
    if let registration {
      return try await registration.value
    }
    let task = Task { try await self.register() }
    registration = task
    defer { registration = nil }
    let fresh = try await task.value
    token = fresh
    return fresh
  }

  private func register() async throws -> String {
    let id: UUID
    do {
      id = try anonymousID()
    } catch {
      throw APIError(status: 0, code: "IDENTITY", message: "Could not read the anonymous ID: \(error)")
    }
    let body = try encode(RegisterRequestDTO(anonymousId: id.uuidString))
    let (data, response) = try await perform(APIRequest(method: "POST", path: "/api/auth/register", body: body, requiresAuth: false), token: nil)
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    let decoded: RegisterResponseDTO = try decode(data)
    return decoded.token
  }

  private func perform(_ request: APIRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
    guard var components = URLComponents(url: baseURL.appending(path: request.path), resolvingAgainstBaseURL: false) else {
      throw APIError.misconfigured
    }
    if !request.query.isEmpty { components.queryItems = request.query }
    guard let url = components.url else { throw APIError.misconfigured }
    var urlRequest = URLRequest(url: url, timeoutInterval: 15)
    urlRequest.httpMethod = request.method
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body = request.body {
      urlRequest.httpBody = body
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw APIError.transport(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else { throw APIError.transport("Not an HTTP response") }
    return (data, http)
  }

  private func encode(_ value: some Encodable) throws -> Data {
    do {
      return try WireDates.makeEncoder().encode(value)
    } catch {
      throw APIError(status: 0, code: "ENCODING", message: String(describing: error))
    }
  }

  private func decode<Response: Decodable>(_ data: Data) throws -> Response {
    do {
      return try WireDates.makeDecoder().decode(Response.self, from: data)
    } catch {
      throw APIError.decoding(status: 200, String(describing: error))
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass** — NOT RUN (code-only; 14/14 pass in a /tmp harness)

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: `** TEST SUCCEEDED **`, with 14 tests passing.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/APIClient/DTOs/AuthDTOs.swift Wait/Packages/WaitKit/Sources/APIClient/HTTPSession.swift Wait/Packages/WaitKit/Tests/APIClientTests/Support Wait/Packages/WaitKit/Tests/APIClientTests/HTTPSessionTests.swift
git commit -m "feat(apiclient): add HTTPSession with lazy register and single 401 retry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 25: Market DTOs and the `APIClient` dependency

**Files:**
- Modify: `Packages/WaitKit/Package.swift` (add `resources` to `APIClientTests`)
- Create: `Packages/WaitKit/Sources/APIClient/DTOs/MarketDTOs.swift`, `Packages/WaitKit/Sources/APIClient/APIClient.swift`
- Create: `Packages/WaitKit/Tests/APIClientTests/Fixtures/quotes.json`, `history-1d.json`, `search.json`, `profile.json`
- Test: `Packages/WaitKit/Tests/APIClientTests/APIClientTests.swift`

- [ ] **Step 1: Add the fixtures (the exact server wire shapes from Chunk 7)**

In `Package.swift`, change the `APIClientTests` target to:
```swift
    .testTarget(name: "APIClientTests", dependencies: ["APIClient", "Domain", .dependencies, .dependenciesTestSupport], resources: [.copy("Fixtures")]),
```

Create `Packages/WaitKit/Tests/APIClientTests/Fixtures/quotes.json`:
```json
{"quotes":[{"symbol":"AAPL","price":"172.1","previousClose":"170","open":"171","high":"173","low":"170.5","change":"2.1","changePercent":1.2353,"volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":false}],"missing":["ZZZZ"]}
```

Create `Packages/WaitKit/Tests/APIClientTests/Fixtures/history-1d.json`:
```json
{"symbol":"AAPL","range":"1D","points":[{"t":"2026-11-20T14:30:00.000Z","c":"171.2"},{"t":"2026-11-20T14:35:00.000Z","c":"171.6"}],"source":"alpaca","asOf":"2026-11-20T15:00:00.000Z","stale":false,"delayedMinutes":15}
```

Create `Packages/WaitKit/Tests/APIClientTests/Fixtures/search.json`:
```json
{"results":[{"symbol":"AAPL","name":"APPLE INC","exchange":null,"type":"Common Stock"}]}
```

Create `Packages/WaitKit/Tests/APIClientTests/Fixtures/profile.json`:
```json
{"symbol":"AAPL","name":"Apple Inc","exchange":"NASDAQ NMS - GLOBAL MARKET","industry":"Technology","logoUrl":"https://example.com/aapl.png","marketCap":"2650000500000","peRatio":28.4,"pbRatio":45.2,"dividendYield":0.55,"roe":147.25,"roa":27.5,"profitMargin":25.31,"fiftyTwoWeekHigh":"199.62","fiftyTwoWeekLow":"164.08","beta":1.29,"asOf":"2026-11-20T15:00:00.000Z"}
```

- [ ] **Step 2: Write the failing tests**

Create `Packages/WaitKit/Tests/APIClientTests/APIClientTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Domain
import Foundation
import Testing

// MARK: - APIClientTests

@Suite
struct APIClientTests {
  private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// A live APIClient over a stub server that answers register plus one `path` with `json`.
  private func client(path: String, status: Int = 200, json: String) -> (APIClient, URL) {
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register": return jsonReply(200, #"{"token":"t1","user":{"id":"u1"}}"#)
        case path: return jsonReply(status, json)
        default: return jsonReply(404, #"{"error":{"code":"NOT_FOUND","message":"unexpected \#(request.url?.path() ?? "")"}}"#)
      }
    }
    let id = UUID()
    return (.live(session: HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })), base)
  }

  private func lastRequest(_ base: URL) -> URLRequest? {
    StubURLProtocol.requests(for: base).last
  }

  @Test
  func quotesJoinsSymbolsAndDecodesTheWireShape() async throws {
    let (api, base) = client(path: "/api/market/quotes", json: try fixture("quotes"))
    let response = try await api.quotes(["AAPL", "ZZZZ"])
    #expect(lastRequest(base)?.url?.query() == "symbols=AAPL,ZZZZ")
    #expect(response.missing == ["ZZZZ"])
    let quote = try #require(response.quotes.first)
    #expect(quote.price == "172.1" && quote.changePercent == 1.2353 && quote.volume == nil && quote.stale == false)
    #expect(quote.asOf == WireDates.date(from: "2026-11-20T15:00:00.000Z"))
  }

  @Test
  func historySendsTheRangeRawValue() async throws {
    let (api, base) = client(path: "/api/market/history", json: try fixture("history-1d"))
    let response = try await api.history("AAPL", .oneDay)
    #expect(lastRequest(base)?.url?.query() == "symbol=AAPL&range=1D")
    #expect(response.points.map(\.c) == ["171.2", "171.6"])
    #expect(response.delayedMinutes == 15)
  }

  @Test
  func searchAndProfileDecode() async throws {
    let (searchAPI, _) = client(path: "/api/market/search", json: try fixture("search"))
    #expect(try await searchAPI.search("app").results.map(\.symbol) == ["AAPL"])
    let (profileAPI, _) = client(path: "/api/market/profile", json: try fixture("profile"))
    let profile = try await profileAPI.profile("AAPL")
    #expect(profile.marketCap == "2650000500000" && profile.peRatio == 28.4 && profile.fiftyTwoWeekLow == "164.08")
  }

  @Test
  func deleteAccountSendsDELETEAndAccepts204() async throws {
    let (api, base) = client(path: "/api/auth/account", status: 204, json: "")
    try await api.deleteAccount()
    #expect(lastRequest(base)?.httpMethod == "DELETE")
  }

  @Test
  func baseURLComesFromInfoPlistAndRejectsEmptyValues() {
    #expect(APIClient.baseURL(infoValue: "https://wait-api.vercel.app") == URL(string: "https://wait-api.vercel.app"))
    #expect(APIClient.baseURL(infoValue: "") == nil)
    #expect(APIClient.baseURL(infoValue: nil) == nil)
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `scripts/test-waitkit.sh APIClientTests/APIClientTests`
Expected: the build fails with `cannot find 'APIClient' in scope` (as a type) and `cannot find type 'QuotesResponseDTO'`.

- [ ] **Step 4: Implement the DTOs and the client**

Create `Packages/WaitKit/Sources/APIClient/DTOs/MarketDTOs.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// Wire DTOs for /api/market/* (overview §8.4). Prices stay decimal strings here.
// `MarketDataClient.backend` converts them to Domain types.

// MARK: - QuoteDTO

public struct QuoteDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let price: String
  public let previousClose: String?
  public let open: String?
  public let high: String?
  public let low: String?
  public let change: String?
  public let changePercent: Double?
  public let volume: Int?
  public let fiftyTwoWeekHigh: String?
  public let fiftyTwoWeekLow: String?
  public let asOf: Date
  public let source: String
  public let stale: Bool
}

// MARK: - QuotesResponseDTO

public struct QuotesResponseDTO: Decodable, Equatable, Sendable {
  public let quotes: [QuoteDTO]
  public let missing: [String]
}

// MARK: - HistoryPointDTO

public struct HistoryPointDTO: Decodable, Equatable, Sendable {
  public let t: Date
  public let c: String
}

// MARK: - HistoryResponseDTO

public struct HistoryResponseDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let range: String
  public let points: [HistoryPointDTO]
  public let source: String
  public let asOf: Date
  public let stale: Bool
  public let delayedMinutes: Int?
}

// MARK: - SearchResultDTO

public struct SearchResultDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let name: String
  public let exchange: String?
  public let type: String
}

// MARK: - SearchResponseDTO

public struct SearchResponseDTO: Decodable, Equatable, Sendable {
  public let results: [SearchResultDTO]
}

// MARK: - ProfileDTO

/// Ratios follow Finnhub: dividend yield, ROE, ROA and margin are percentages (0.55 means 0.55%).
public struct ProfileDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let name: String?
  public let exchange: String?
  public let industry: String?
  public let logoUrl: String?
  public let marketCap: String?
  public let peRatio: Double?
  public let pbRatio: Double?
  public let dividendYield: Double?
  public let roe: Double?
  public let roa: Double?
  public let profitMargin: Double?
  public let fiftyTwoWeekHigh: String?
  public let fiftyTwoWeekLow: String?
  public let beta: Double?
  public let asOf: Date
}
```

Create `Packages/WaitKit/Sources/APIClient/APIClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation

// MARK: - APIClient

/// Typed endpoints of the Wait backend. Plans 05 and 06 add sync and device endpoints here.
@DependencyClient
public struct APIClient: Sendable {
  public var quotes: @Sendable (_ symbols: [String]) async throws -> QuotesResponseDTO
  public var history: @Sendable (_ symbol: String, _ range: ChartRange) async throws -> HistoryResponseDTO
  public var search: @Sendable (_ query: String) async throws -> SearchResponseDTO
  public var profile: @Sendable (_ symbol: String) async throws -> ProfileDTO
  public var deleteAccount: @Sendable () async throws -> Void
}

extension APIClient {
  public static func live(session: HTTPSession) -> APIClient {
    APIClient(
      quotes: { symbols in
        try await session.get("/api/market/quotes", query: [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))])
      },
      history: { symbol, range in
        try await session.get("/api/market/history", query: [URLQueryItem(name: "symbol", value: symbol), URLQueryItem(name: "range", value: range.rawValue)])
      },
      search: { query in
        try await session.get("/api/market/search", query: [URLQueryItem(name: "q", value: query)])
      },
      profile: { symbol in
        try await session.get("/api/market/profile", query: [URLQueryItem(name: "symbol", value: symbol)])
      },
      deleteAccount: {
        try await session.delete("/api/auth/account")
      }
    )
  }

  /// `WaitAPIBaseURL` comes from `WAIT_API_BASE_URL` in `Config/*.xcconfig` (overview §8.2).
  public static func baseURL(infoValue: String?) -> URL? {
    guard let infoValue, !infoValue.isEmpty else { return nil }
    return URL(string: infoValue)
  }

  static let misconfigured = APIClient(
    quotes: { _ in throw APIError.misconfigured },
    history: { _, _ in throw APIError.misconfigured },
    search: { _ in throw APIError.misconfigured },
    profile: { _ in throw APIError.misconfigured },
    deleteAccount: { throw APIError.misconfigured }
  )
}

// MARK: - APIClient + DependencyKey

extension APIClient: DependencyKey {
  /// One shared session per process, so the in-memory JWT is reused by every caller.
  public static let liveValue: APIClient = {
    let info = Bundle.main.object(forInfoDictionaryKey: "WaitAPIBaseURL") as? String
    guard let baseURL = baseURL(infoValue: info) else { return .misconfigured }
    let identity = IdentityClient.liveValue
    return .live(session: HTTPSession(baseURL: baseURL, anonymousID: { try identity.anonymousID() }))
  }()

  public static let testValue = APIClient()
}

extension DependencyValues {
  public var apiClient: APIClient {
    get { self[APIClient.self] }
    set { self[APIClient.self] = newValue }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: `** TEST SUCCEEDED **`, with 19 tests passing.

- [ ] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/APIClient Wait/Packages/WaitKit/Tests/APIClientTests
git commit -m "feat(apiclient): add market DTOs and APIClient dependency

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 11: iOS backend market data and fundamentals

### Task 26: `MarketDataClient.backend` and the live-value swap

**Files:**
- Modify: `Packages/WaitKit/Package.swift` (add `"APIClient"` to the `MarketDataClient` target and to `MarketDataClientTests`)
- Create: `Packages/WaitKit/Sources/MarketDataClient/Backend/BackendMarketData.swift`
- Modify: `Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift` (`liveValue`)
- Modify: `Config/Base.xcconfig`, `Config/Secrets.example.xcconfig`, `Wait/Info.plist`, `project.yml` (a Debug-only ATS build phase) and the regenerated `Wait.xcodeproj`
- Test: `Packages/WaitKit/Tests/MarketDataClientTests/BackendMarketDataTests.swift`

- [ ] **Step 1: Add the dependency**

In `Package.swift`, add `"APIClient"` to the `dependencies` of the `MarketDataClient` target and of the `MarketDataClientTests` test target. The test target then reads `["MarketDataClient", "Domain", "APIClient", .dependencies, .dependenciesTestSupport]`, plus plan 02's `resources:`.

- [ ] **Step 2: Write the failing tests**

Create `Packages/WaitKit/Tests/MarketDataClientTests/BackendMarketDataTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import Domain
import Foundation
@testable import MarketDataClient
import Testing

// MARK: - BackendMarketDataTests

@Suite
struct BackendMarketDataTests {
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try WireDates.makeDecoder().decode(T.self, from: Data(json.utf8))
  }

  @Test
  func mapsQuotesAndDropsUnparseablePrices() async throws {
    let response: QuotesResponseDTO = try decode(#"""
    {"quotes":[
      {"symbol":"AAPL","price":"172.1","previousClose":"170","open":"171","high":"173","low":"170.5","change":"2.1","changePercent":1.2353,
       "volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":true},
      {"symbol":"BAD","price":"n/a","previousClose":null,"open":null,"high":null,"low":null,"change":null,"changePercent":null,
       "volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":false}
    ],"missing":["ZZZZ"]}
    """#)
    var api = APIClient()
    api.quotes = { _ in response }
    let quotes = try await MarketDataClient.backend(api).quotes(["AAPL", "BAD", "ZZZZ"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL"])
    let quote = try #require(quotes.first)
    #expect(quote.price == DecimalCoding.parse("172.1"))
    #expect(quote.previousClose == 170)
    #expect(quote.changePercent == 1.2353)
    #expect(quote.isStale)
    #expect(quote.asOf == WireDates.date(from: "2026-11-20T15:00:00.000Z"))
  }

  @Test
  func mapsSeriesSearchAndProfile() async throws {
    let history: HistoryResponseDTO = try decode(#"{"symbol":"AAPL","range":"1D","points":[{"t":"2026-11-20T14:30:00.000Z","c":"171.2"}],"source":"alpaca","asOf":"2026-11-20T15:00:00.000Z","stale":false,"delayedMinutes":15}"#)
    let search: SearchResponseDTO = try decode(#"{"results":[{"symbol":"AAPL","name":"APPLE INC","exchange":null,"type":"Common Stock"}]}"#)
    let profile: ProfileDTO = try decode(#"{"symbol":"AAPL","name":"Apple Inc","exchange":"NASDAQ","industry":"Technology","logoUrl":"https://example.com/aapl.png","marketCap":"2650000500000","peRatio":28.4,"pbRatio":45.2,"dividendYield":0.55,"roe":147.25,"roa":27.5,"profitMargin":25.31,"fiftyTwoWeekHigh":"199.62","fiftyTwoWeekLow":"164.08","beta":1.29,"asOf":"2026-11-20T15:00:00.000Z"}"#)
    var api = APIClient()
    api.history = { _, _ in history }
    api.search = { _ in search }
    api.profile = { _ in profile }
    let client = MarketDataClient.backend(api)

    let series = try await client.series("AAPL", .oneDay, .useCache)
    #expect(series.range == .oneDay && series.delayedMinutes == 15 && series.points.map(\.close) == [DecimalCoding.parse("171.2")!])

    #expect(try await client.search("app") == [SymbolSearchResult(symbol: "AAPL", name: "APPLE INC", exchange: nil, type: "Common Stock")])

    let company = try await client.profile("AAPL")
    #expect(company.marketCap == DecimalCoding.parse("2650000500000"))
    #expect(company.logoURL == URL(string: "https://example.com/aapl.png"))
    #expect(company.fiftyTwoWeekLow == DecimalCoding.parse("164.08") && company.peRatio == 28.4)
  }

  private static func quotesJSON(_ symbols: [String]) -> String {
    let items = symbols.map {
      #"{"symbol":"\#($0)","price":"1","previousClose":null,"open":null,"high":null,"low":null,"change":null,"changePercent":null,"volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":false}"#
    }
    return #"{"quotes":[\#(items.joined(separator: ","))],"missing":[]}"#
  }

  private static func recordingQuotesAPI(_ calls: LockIsolated<[[String]]>) -> APIClient {
    var api = APIClient()
    api.quotes = { symbols in
      calls.withValue { $0.append(symbols) }
      return try WireDates.makeDecoder().decode(QuotesResponseDTO.self, from: Data(quotesJSON(symbols).utf8))
    }
    return api
  }

  @Test
  func quotesNormalizesAndNeverSendsSymbolsTheServerWouldReject() async throws {
    let calls = LockIsolated<[[String]]>([])
    let quotes = try await MarketDataClient.backend(Self.recordingQuotesAPI(calls)).quotes(["aapl", "0700.HK", "AAPL"], .useCache)
    #expect(calls.value == [["AAPL"]])
    #expect(quotes.map(\.symbol) == ["AAPL"])
  }

  @Test
  func quotesChunksBy50AndMergesTheResults() async throws {
    let calls = LockIsolated<[[String]]>([])
    let symbols = (0 ..< 51).map { "S" + String(UnicodeScalar(UInt8(65 + $0 / 26))) + String(UnicodeScalar(UInt8(65 + $0 % 26))) }
    let quotes = try await MarketDataClient.backend(Self.recordingQuotesAPI(calls)).quotes(symbols, .useCache)
    #expect(calls.value.map(\.count) == [50, 1])
    #expect(quotes.map(\.symbol) == symbols)
  }

  @Test
  func aRateLimitedLaterChunkReturnsTheEarlierQuotesAsPartial() async throws {
    let symbols = (0 ..< 51).map { "S" + String(UnicodeScalar(UInt8(65 + $0 / 26))) + String(UnicodeScalar(UInt8(65 + $0 % 26))) }
    var api = APIClient()
    api.quotes = { chunk in
      if chunk.count == 1 { throw APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "", retryAfter: .seconds(30)) }
      return try WireDates.makeDecoder().decode(QuotesResponseDTO.self, from: Data(Self.quotesJSON(chunk).utf8))
    }
    let client = MarketDataClient.backend(api)
    let error = await #expect(throws: PartialQuotesError.self) { try await client.quotes(symbols, .useCache) }
    #expect(error?.quotes.count == 50)
    #expect(error?.retryAfter == .seconds(30))
  }

  @Test
  func emptyOrInvalidInputMakesNoRequest() async throws {
    let client = MarketDataClient.backend(APIClient()) // every endpoint unimplemented: any call fails the test
    #expect(try await client.quotes([], .useCache).isEmpty)
    #expect(try await client.quotes(["0700.HK"], .useCache).isEmpty)
    #expect(try await client.search("   ").isEmpty)
  }

  @Test
  func searchTrimsAndTruncatesTo30Characters() async throws {
    let sent = LockIsolated<String?>(nil)
    var api = APIClient()
    api.search = { query in
      sent.setValue(query)
      return try WireDates.makeDecoder().decode(SearchResponseDTO.self, from: Data(#"{"results":[]}"#.utf8))
    }
    _ = try await MarketDataClient.backend(api).search("  " + String(repeating: "a", count: 40) + " ")
    #expect(sent.value == String(repeating: "a", count: 30))
  }

  @Test
  func mapsAPIErrorsToMarketDataErrors() async {
    var api = APIClient()
    api.quotes = { _ in throw APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "", retryAfter: .seconds(30)) }
    api.profile = { _ in throw APIError(status: 404, code: "NOT_FOUND", message: "") }
    api.search = { _ in throw APIError.transport("offline") }
    api.history = { _, _ in throw APIError(status: 502, code: "UPSTREAM_UNAVAILABLE", message: "") }
    let client = MarketDataClient.backend(api)
    await #expect(throws: MarketDataError.rateLimited(retryAfter: .seconds(30))) { try await client.quotes(["AAPL"], .useCache) }
    await #expect(throws: MarketDataError.notFound) { try await client.profile("ZZZZ") }
    await #expect(throws: MarketDataError.network("offline")) { try await client.search("app") }
    await #expect(throws: MarketDataError.unavailable) { try await client.series("AAPL", .oneYear, .useCache) }
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests/BackendMarketDataTests`
Expected: the build fails with `type 'MarketDataClient' has no member 'backend'`.

- [ ] **Step 4: Implement the adapter**

Create `Packages/WaitKit/Sources/MarketDataClient/Backend/BackendMarketData.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation

// MARK: - MarketDataClient + Backend

extension MarketDataClient {
  /// The server accepts at most 50 symbols per `/api/market/quotes` call (overview §8.4).
  static let maxSymbolsPerRequest = 50

  /// Uppercased, deduped, and only tickers the server's symbol rule accepts. Others (e.g. `0700.HK`)
  /// are never sent; callers see them as missing rather than failing the whole batch with a 400.
  static func requestableSymbols(_ symbols: [String]) -> [String] {
    var seen = Set<String>()
    return symbols
      .map { $0.uppercased() }
      .filter { $0.range(of: #"^[A-Z]{1,5}([.-][A-Z]{1,2})?$"#, options: .regularExpression) != nil && seen.insert($0).inserted }
  }

  /// Every call goes to the Wait backend, which owns provider keys, shared caches and rate limits.
  /// Wrap it with `.cached(_:disk:ttl:now:)` for on-device TTLs, coalescing and the 429 cooldown.
  public static func backend(_ api: APIClient) -> MarketDataClient {
    MarketDataClient(
      quotes: { symbols, _ in
        let requestable = requestableSymbols(symbols)
        guard !requestable.isEmpty else { return [] }
        return try await mapAPIErrors {
          var quotes: [Quote] = []
          for start in stride(from: 0, to: requestable.count, by: maxSymbolsPerRequest) {
            let chunk = Array(requestable[start ..< min(start + maxSymbolsPerRequest, requestable.count)])
            do {
              quotes += try await api.quotes(chunk).quotes.compactMap(Quote.init(dto:))
            } catch let error as APIError where !quotes.isEmpty && (error.status == 429 || error.status == 503) {
              // A later chunk hit the limit: hand back what we have (plan 02's PartialQuotesError contract).
              throw PartialQuotesError(quotes: quotes, retryAfter: error.retryAfter)
            }
          }
          return quotes
        }
      },
      series: { symbol, range, _ in
        try await mapAPIErrors { try PriceSeries(dto: try await api.history(symbol, range)) }
      },
      search: { query in
        // The server accepts 1–30 characters with at least one non-space.
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !trimmed.isEmpty else { return [] }
        return try await mapAPIErrors { try await api.search(trimmed).results.map(SymbolSearchResult.init(dto:)) }
      },
      profile: { symbol in
        try await mapAPIErrors { CompanyProfile(dto: try await api.profile(symbol)) }
      }
    )
  }
}

// MARK: - MarketDataError + APIError

extension MarketDataError {
  init(apiError: APIError) {
    switch apiError.status {
      case 429, 503: self = .rateLimited(retryAfter: apiError.retryAfter)
      case 404: self = .notFound
      case 0: self = .network(apiError.message)
      default: self = apiError.code == "DECODING" ? .decoding(apiError.message) : .unavailable
    }
  }
}

private func mapAPIErrors<T>(_ work: () async throws -> T) async throws -> T {
  do {
    return try await work()
  } catch let error as APIError {
    throw MarketDataError(apiError: error)
  } catch let partial as PartialQuotesError {
    throw partial // the decorator keeps partial.quotes and starts the cooldown
  } catch {
    throw try MarketDataError(error) // rethrows cancellation unchanged
  }
}

// MARK: - DTO → Domain

extension Quote {
  /// Nil when the price is not a plain decimal literal; such rows are dropped, never shown as 0.
  init?(dto: QuoteDTO) {
    guard let price = DecimalCoding.parse(dto.price) else { return nil }
    self.init(
      symbol: dto.symbol,
      price: price,
      previousClose: dto.previousClose.flatMap(DecimalCoding.parse),
      open: dto.open.flatMap(DecimalCoding.parse),
      high: dto.high.flatMap(DecimalCoding.parse),
      low: dto.low.flatMap(DecimalCoding.parse),
      change: dto.change.flatMap(DecimalCoding.parse),
      changePercent: dto.changePercent,
      volume: dto.volume,
      fiftyTwoWeekHigh: dto.fiftyTwoWeekHigh.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: dto.fiftyTwoWeekLow.flatMap(DecimalCoding.parse),
      asOf: dto.asOf,
      isStale: dto.stale
    )
  }
}

extension PriceSeries {
  init(dto: HistoryResponseDTO) throws {
    guard let range = ChartRange(rawValue: dto.range) else { throw MarketDataError.decoding("Unknown chart range \(dto.range)") }
    self.init(
      symbol: dto.symbol,
      range: range,
      points: dto.points.compactMap { point in DecimalCoding.parse(point.c).map { PricePoint(date: point.t, close: $0) } },
      asOf: dto.asOf,
      delayedMinutes: dto.delayedMinutes,
      isStale: dto.stale
    )
  }
}

extension SymbolSearchResult {
  init(dto: SearchResultDTO) {
    self.init(symbol: dto.symbol, name: dto.name, exchange: dto.exchange, type: dto.type)
  }
}

extension CompanyProfile {
  init(dto: ProfileDTO) {
    self.init(
      symbol: dto.symbol,
      name: dto.name,
      exchange: dto.exchange,
      industry: dto.industry,
      logoURL: dto.logoUrl.flatMap(URL.init(string:)),
      marketCap: dto.marketCap.flatMap(DecimalCoding.parse),
      peRatio: dto.peRatio,
      pbRatio: dto.pbRatio,
      dividendYield: dto.dividendYield,
      roe: dto.roe,
      roa: dto.roa,
      profitMargin: dto.profitMargin,
      fiftyTwoWeekHigh: dto.fiftyTwoWeekHigh.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: dto.fiftyTwoWeekLow.flatMap(DecimalCoding.parse),
      beta: dto.beta,
      asOf: dto.asOf
    )
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests`
Expected: `** TEST SUCCEEDED **`. The 8 new tests pass, and so do all of plan 02's MarketDataClient suites.

- [ ] **Step 6: Swap the live value to the backend**

In `Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift`:
1. Add `import APIClient` with the other imports.
2. Replace plan 02's `extension MarketDataClient: DependencyKey { … }` block with:
```swift
extension MarketDataClient: DependencyKey {
  /// Plan 04: quotes, charts, search and profiles all come from the Wait backend. No provider key ships in the app.
  public static let liveValue = MarketDataClient.cached(
    .backend(.liveValue),
    disk: .live,
    now: { Date() }
  )
}
```

- [ ] **Step 7: Point the app at the backend `(manual: user)` for the host**

Ask the user for the production host from Task 21 Step 6, for example `wait-server.vercel.app`. Then run:
```bash
cd /Users/ckai/code/Wait/Wait
HOST=wait-server.vercel.app   # replace with the user's host
python3 -I - "$HOST" <<'PY'
import pathlib, sys
host = sys.argv[1]
path = pathlib.Path("Config/Base.xcconfig")
text = path.read_text()
assert '#include? "Secrets.xcconfig"' in text and "WAIT_API_BASE_URL" not in text
block = ("// The Wait backend (plan 04). `/$()/` keeps xcconfig from reading `//` as a comment (risk 27).\n"
         f"WAIT_API_BASE_URL = https:/$()/{host}\n\n")
path.write_text(text.replace('#include? "Secrets.xcconfig"', block + '#include? "Secrets.xcconfig"', 1))
PY
printf '\n// Optional: point the app at a local server (`npm run dev` in server/).\n// WAIT_API_BASE_URL = http:/$()/localhost:3000\n' >> Config/Secrets.example.xcconfig
plutil -replace WaitAPIBaseURL -string '$(WAIT_API_BASE_URL)' Wait/Info.plist
grep -n "WAIT_API_BASE_URL" Config/Base.xcconfig && plutil -p Wait/Info.plist | grep WaitAPIBaseURL
```
Expected:
- The default line `WAIT_API_BASE_URL = https:/$()/<host>` comes **above** the `#include?` line, so a local `Secrets.xcconfig` can override it.
- `plutil -p` shows `"WaitAPIBaseURL" => "$(WAIT_API_BASE_URL)"`.

- [ ] **Step 8: Allow local networking in Debug builds only (risk 27)**

`Wait/Info.plist` is shared by every configuration, and ATS keys are booleans inside a dictionary, which build-setting substitution can't express. So the Debug-only key is added to the **built** Info.plist by a build phase:
- The phase runs before code signing.
- It never touches the source plist.
- It keeps any existing `NSAppTransportSecurity` entries.

In `Wait/project.yml`, add this key to the `Wait` target, as a sibling of `settings:`. If the target already has `postBuildScripts:`, append the entry.
```yaml
    postBuildScripts:
      - name: "ATS: allow local networking (Debug only)"
        basedOnDependencyAnalysis: false
        script: |
          # Debug builds may talk to `npm run dev` on http://localhost:3000. Release builds never get this key.
          [ "${CONFIGURATION}" = "Debug" ] || exit 0
          plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
          /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$plist" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Delete :NSAppTransportSecurity:NSAllowsLocalNetworking" "$plist" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist"
```
Then regenerate the project and check both configurations:
```bash
cd /Users/ckai/code/Wait/Wait && xcodegen generate
for config in Debug Release; do
  xcodebuild -project Wait.xcodeproj -scheme Wait -configuration "$config" \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
    -derivedDataPath "/tmp/wait-ats-$config" -quiet build
  echo "-- $config"
  plutil -p "/tmp/wait-ats-$config/Build/Products/$config-iphonesimulator/Wait.app/Info.plist" | grep -E "WaitAPIBaseURL|NSAllowsLocalNetworking"
done
```
Expected:
- **Debug** shows `"WaitAPIBaseURL" => "https://<host>"` and `"NSAllowsLocalNetworking" => true`.
- **Release** shows only the `WaitAPIBaseURL` line.
- If the build fails with `Sandbox: … deny file-write-data`, add `ENABLE_USER_SCRIPT_SANDBOXING: NO` to the `Wait` target's `settings.base`, then regenerate.

Then run: `cd /Users/ckai/code/Wait && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/MarketDataClient Wait/Packages/WaitKit/Tests/MarketDataClientTests/BackendMarketDataTests.swift \
  Wait/Config/Base.xcconfig Wait/Config/Secrets.example.xcconfig Wait/Wait/Info.plist Wait/project.yml Wait/Wait.xcodeproj
git commit -m "feat(marketdata): serve market data from the Wait backend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 27: Fundamentals in Stock Details

**Files:**
- Modify: `Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsFeature.swift`, `StatsSection.swift`, `StockDetailsView.swift`
- Modify: `Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsFeatureTests.swift` (plan 02's `makeStore` and its task test)
- Test: `Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsProfileTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsProfileTests.swift`. It reuses `detailsItem()` and `detailsNow` from plan 02's `StockDetailsFeatureTests.swift`.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import StockDetailsFeature
import Testing

// MARK: - StockDetailsProfileTests

@MainActor
@Suite
struct StockDetailsProfileTests {
  private let profile = CompanyProfile(symbol: "AAPL", name: "Apple Inc", marketCap: 2_650_000_500_000, peRatio: 28.4, asOf: detailsNow)
  private let quote = Quote(symbol: "AAPL", price: 140, asOf: detailsNow)

  private func makeStore(profile: @escaping @Sendable (String) async throws -> CompanyProfile) -> TestStoreOf<StockDetailsFeature> {
    let quote = quote
    return TestStore(initialState: StockDetailsFeature.State(item: Shared(value: detailsItem()))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.date.now = detailsNow
      $0.marketData.quotes = { _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return [quote]
      }
      $0.marketData.profile = profile
    }
  }

  @Test
  func taskLoadsTheQuoteThenTheProfile() async {
    let profile = profile
    let store = makeStore { _ in profile }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = self.quote }
    await store.receive(\.profileLoaded) { $0.profile = profile }
  }

  @Test
  func aMissingProfileKeepsTheScreenUsable() async {
    let store = makeStore { _ in throw MarketDataError.notFound }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = self.quote }
    await store.receive(\.profileFailed)
    #expect(store.state.profile == nil)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests/StockDetailsProfileTests`
Expected: the build fails with `value of type 'StockDetailsFeature.State' has no member 'profile'` and `no member 'profileLoaded'`.

- [ ] **Step 3: Extend the reducer**

In `Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsFeature.swift`:
1. In `State`, add after `public var quote: Quote?`:
```swift
    public var profile: CompanyProfile?
```
2. In `Action`, add after `case quoteFailed(MarketDataError)`:
```swift
    case profileLoaded(CompanyProfile)
    case profileFailed(MarketDataError)
```
3. Replace the whole `case .task:` branch with the version below. The profile loads **after** the quote in the same effect, so the action order is deterministic for tests:
```swift
        case .task:
          let symbol = state.item.symbol
          return .run { [marketData] send in
            if let cached = try? await marketData.quotes([symbol], .cacheOnly).first {
              await send(.quoteLoaded(cached))
            }
            do {
              if let fresh = try await marketData.quotes([symbol], .useCache).first {
                await send(.quoteLoaded(fresh))
              }
            } catch {
              try await send(.quoteFailed(MarketDataError(error))) // rethrows cancellation
            }
            do {
              await send(.profileLoaded(try await marketData.profile(symbol)))
            } catch {
              try await send(.profileFailed(MarketDataError(error))) // rethrows cancellation
            }
          }
```
4. Add these cases after `case .quoteFailed: return .none`:
```swift
        case let .profileLoaded(profile):
          state.profile = profile
          return .none

        case .profileFailed:
          return .none
```

- [ ] **Step 4: Keep plan 02's task test exhaustive**

In `Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsFeatureTests.swift`:
1. Inside `makeStore`'s `withDependencies` closure, add `$0.marketData.profile = { _ in throw MarketDataError.notFound }` after `$0.date.now = detailsNow`.
2. Two plan 02 tests send `.task`, and both now also receive the profile failure:
   - In `taskLoadsTheQuoteAndDerivesTheStatus`, add `await store.receive(\.profileFailed)` after the `receive(\.quoteLoaded)` line.
   - In `failedRefreshKeepsTheCachedQuote`, add `await store.receive(\.profileFailed)` after the `receive(\.quoteFailed)` line.

- [ ] **Step 5: Show the fundamentals**

Replace `Packages/WaitKit/Sources/StockDetailsFeature/StatsSection.swift` with:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - StatsSection

/// Today's quote plus fundamentals from the backend profile (Finnhub ratios are percentages).
struct StatsSection: View {
  // MARK: Internal

  let quote: Quote?
  let profile: CompanyProfile?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      Text("Stats").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.m) {
        GridRow {
          price("Open", quote?.open)
          price("Prev Close", quote?.previousClose)
        }
        GridRow {
          price("High", quote?.high)
          price("Low", quote?.low)
        }
        GridRow {
          price("52W High", profile?.fiftyTwoWeekHigh ?? quote?.fiftyTwoWeekHigh)
          price("52W Low", profile?.fiftyTwoWeekLow ?? quote?.fiftyTwoWeekLow)
        }
        GridRow {
          stat("Mkt Cap", profile?.marketCap.map { "$" + $0.formatted(.number.notation(.compactName)) })
          stat("P/E", ratio(profile?.peRatio))
        }
        GridRow {
          stat("P/B", ratio(profile?.pbRatio))
          stat("Div Yield", percent(profile?.dividendYield))
        }
        GridRow {
          stat("ROE", percent(profile?.roe))
          stat("Beta", ratio(profile?.beta))
        }
        GridRow {
          stat("Volume", quote?.volume.map { $0.formatted(.number.notation(.compactName)) })
          stat("Change", quote?.changePercent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) })
        }
      }
      if let industry = profile?.industry {
        Text(industry).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: Private

  private func price(_ title: String, _ value: Decimal?) -> some View {
    stat(title, value.map { $0.formatted(.currency(code: "USD")) })
  }

  private func ratio(_ value: Double?) -> String? {
    value.map { $0.formatted(.number.precision(.fractionLength(2))) }
  }

  private func percent(_ value: Double?) -> String? {
    value.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) }
  }

  private func stat(_ title: String, _ value: String?) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value ?? "—").font(.subheadline.monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
```
In `StockDetailsView.swift`, change `card { StatsSection(quote: store.quote) }` to `card { StatsSection(quote: store.quote, profile: store.profile) }`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests && scripts/build-app.sh`
Expected: `** TEST SUCCEEDED **` (including plan 02's suites), then `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/StockDetailsFeature Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests
git commit -m "feat(details): show backend fundamentals in Stock Details

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 12: iOS account, provider-key removal, docs

### Task 28: Settings account section (anonymous ID, Delete Account, attribution)

**Files:**
- Modify: `Packages/WaitKit/Package.swift` (add `"APIClient"` to the `SettingsFeature` target)
- Modify: `Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`, `Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`
- Create: `Packages/WaitKit/Sources/SettingsFeature/AccountSection.swift`
- Test: `Packages/WaitKit/Tests/SettingsFeatureTests/SettingsAccountTests.swift`

- [ ] **Step 1: Add the dependency**

In `Package.swift`, add `"APIClient"` to the `SettingsFeature` target's `dependencies`, and also to `SettingsFeatureTests`.

- [ ] **Step 2: Write the failing tests**

Create `Packages/WaitKit/Tests/SettingsFeatureTests/SettingsAccountTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Foundation
@testable import SettingsFeature
import Testing

// MARK: - SettingsAccountTests

@MainActor
@Suite
struct SettingsAccountTests {
  @Test
  func taskShowsTheAnonymousID() async {
    let id = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "1.0 (1)")) {
      SettingsFeature()
    } withDependencies: {
      $0.identity.anonymousID = { id }
    }
    await store.send(.task)
    await store.receive(\.accountLoaded) { $0.account.anonymousID = id.uuidString }
  }

  @Test
  func deletingAsksForConfirmationThenDeletesAndResetsTheIdentity() async {
    let deleted = LockIsolated(false)
    let resets = LockIsolated(0)
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    let store = TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = { deleted.setValue(true) }
      $0.identity.reset = { resets.withValue { $0 += 1 } }
    }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeleted) {
      $0.account.isDeleting = false
      $0.account.anonymousID = nil
    }
    #expect(deleted.value)
    #expect(resets.value == 1)
  }

  @Test
  func cancellingTheAlertDeletesNothing() async {
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "1.0 (1)")) { SettingsFeature() }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.dismiss)) { $0.alert = nil }
  }

  @Test
  func aFailedDeleteKeepsTheIdentityAndShowsWhy() async {
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    let store = TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = { throw APIError.transport("The Internet connection appears to be offline.") }
    }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeletionFailed) {
      $0.account.isDeleting = false
      $0.account.errorMessage = "The Internet connection appears to be offline."
    }
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `scripts/test-waitkit.sh SettingsFeatureTests/SettingsAccountTests`
Expected: the build fails with `type 'SettingsFeature.Action' has no member 'task'` and `no member 'deleteAccountTapped'`.

- [ ] **Step 4: Extend `SettingsFeature`**

All edits are in `Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`.

1. Add `import APIClient` to the imports.
2. Add this type at the end of the file:
```swift
// MARK: - AccountState

public struct AccountState: Equatable, Sendable {
  // MARK: Lifecycle

  public init(anonymousID: String? = nil) {
    self.anonymousID = anonymousID
  }

  // MARK: Public

  /// Nil after a deletion, until the next server call mints a new ID.
  public var anonymousID: String?
  public var isDeleting = false
  public var errorMessage: String?
}

// MARK: - AlertState + Delete account

extension AlertState where Action == SettingsFeature.Action.Alert {
  static var deleteAccount: Self {
    AlertState {
      TextState("Delete your Wait account?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDeleteAccount) {
        TextState("Delete Account")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("This removes your synced watchlist, notes and alert settings from the Wait server. The stocks on this iPhone stay.")
    }
  }
}
```
3. In `State`, add after `public var appVersion: String`:
```swift
    public var account = AccountState()
    @Presents public var alert: AlertState<Action.Alert>?
```
4. Replace `public enum Action { … }` with:
```swift
  public enum Action {
    case task
    case checklistTemplateTapped
    case path(StackActionOf<Path>)
    case accountLoaded(String)
    case deleteAccountTapped
    case alert(PresentationAction<Alert>)
    case accountDeleted
    case accountDeletionFailed(String)

    public enum Alert: Equatable, Sendable {
      case confirmDeleteAccount
    }
  }
```
5. Add the dependencies after the last Public member (the `body` property). Put them under a new `// MARK: Internal` header, so the order stays Lifecycle → Public → Internal → Private:
```swift
  // MARK: Internal

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.identity) var identity
```
6. Inside the `Reduce` switch, add these cases before `case .path:`:
```swift
        case .task:
          return .run { [identity] send in
            if let id = try? identity.anonymousID() {
              await send(.accountLoaded(id.uuidString))
            }
          }

        case let .accountLoaded(id):
          state.account.anonymousID = id
          return .none

        case .deleteAccountTapped:
          state.alert = .deleteAccount
          return .none

        case .alert(.presented(.confirmDeleteAccount)):
          state.account.isDeleting = true
          state.account.errorMessage = nil
          // Plan 05 adds `syncClient` to this capture list and calls `await syncClient.reset()` after `deleteAccount()`.
          return .run { [apiClient, identity] send in
            do {
              try await apiClient.deleteAccount()
              try identity.reset()
              await send(.accountDeleted)
            } catch {
              await send(.accountDeletionFailed(error.localizedDescription))
            }
          }

        case .alert:
          return .none

        case .accountDeleted:
          state.account.isDeleting = false
          state.account.anonymousID = nil
          return .none

        case let .accountDeletionFailed(message):
          state.account.isDeleting = false
          state.account.errorMessage = message
          return .none
```
7. Change `.forEach(\.path, action: \.path)` so the alert is wired as well:
```swift
    .forEach(\.path, action: \.path)
    .ifLet(\.$alert, action: \.alert)
```

- [ ] **Step 5: Add the view and wire it in**

Create `Packages/WaitKit/Sources/SettingsFeature/AccountSection.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - AccountSection

struct AccountSection: View {
  let store: StoreOf<SettingsFeature>

  var body: some View {
    Section {
      LabeledContent("Anonymous ID") {
        Text(store.account.anonymousID ?? "Created on next sync")
          .font(.footnote.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Button(role: .destructive) {
        store.send(.deleteAccountTapped)
      } label: {
        if store.account.isDeleting {
          ProgressView()
        } else {
          Text("Delete Account")
        }
      }
      .disabled(store.account.isDeleting)
      if let message = store.account.errorMessage {
        Text(message).font(.footnote).foregroundStyle(.red)
      }
    } header: {
      Text("Account")
    } footer: {
      Text("Your anonymous ID is kept in iCloud Keychain, so your devices share one watchlist. Deleting the account removes your data from the Wait server only.")
    }
  }
}
```
In `Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`:
1. Inside the `Form`, add `AccountSection(store: store)` directly after the `Section("Checklist") { … }` block.
2. In the About section footer, replace the Twelve Data sentence with the text below. It lists all four providers from overview §6.4 now, even though Massive's only consumer is plan 06's daily alert job. That way the attribution is complete as soon as the backend is the data source.
```swift
          Text("Data provided by Finnhub, Tiingo, Alpaca and Massive, for personal use only. 1D and 1W charts are delayed 15 minutes. Not investment advice.")
```
3. After `.navigationTitle("Settings")`, add:
```swift
      .alert($store.scope(state: \.alert, action: \.alert))
      .task { await store.send(.task).finish() }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `scripts/test-waitkit.sh SettingsFeatureTests && scripts/build-app.sh`
Expected: `** TEST SUCCEEDED **` (plan 02's 2 settings tests plus these 4), then `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/SettingsFeature Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsAccountTests.swift
git commit -m "feat(settings): show anonymous ID, delete account, data attribution

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 29: Remove Twelve Data and guard against provider keys

**Files:**
- Create: `/Users/ckai/code/Wait/scripts/check-client-has-no-provider-keys.sh`
- Delete: `Packages/WaitKit/Sources/MarketDataClient/TwelveData/`, `Packages/WaitKit/Tests/MarketDataClientTests/Fixtures/twelvedata-*.json`, `Packages/WaitKit/Tests/MarketDataClientTests/TwelveDataMarketDataTests.swift`
- Modify: `Packages/WaitKit/Package.swift` (the `MarketDataClientTests` resources), `Config/Base.xcconfig`, `Config/Secrets.example.xcconfig`, every `Info.plist` that still has `TwelveDataAPIKey`

- [ ] **Step 1: Write the guard first**

Create `/Users/ckai/code/Wait/scripts/check-client-has-no-provider-keys.sh`:
```bash
#!/bin/bash
# Fails if the iOS client references a market-data provider host or key.
# Since plan 04 the app talks only to the Wait backend (overview §6.3 item 1).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
pattern='api\.twelvedata\.com|alphavantage\.co|finnhub\.io|api\.tiingo\.com|alpaca\.markets|api\.massive\.com|api\.polygon\.io|TWELVE_DATA_API_KEY|TwelveDataAPIKey|twelveData\('
if git grep -niIE "$pattern" -- Wait; then
  echo "check-client-has-no-provider-keys: provider hosts or keys found in the iOS client (matches above)" >&2
  exit 1
fi
echo "check-client-has-no-provider-keys: ok"
```
Run: `chmod +x scripts/check-client-has-no-provider-keys.sh && scripts/check-client-has-no-provider-keys.sh; echo "exit=$?"`
Expected: it fails, listing the remaining matches. These include `TwelveData/TwelveDataMarketData.swift` (`api.twelvedata.com`), the xcconfig `TWELVE_DATA_API_KEY` lines and `Info.plist` `TwelveDataAPIKey`. The last line is `exit=1`.

- [ ] **Step 2: Delete the adapter, its tests and fixtures**

```bash
cd /Users/ckai/code/Wait
git rm -r -q Wait/Packages/WaitKit/Sources/MarketDataClient/TwelveData
git rm -q Wait/Packages/WaitKit/Tests/MarketDataClientTests/TwelveDataMarketDataTests.swift Wait/Packages/WaitKit/Tests/MarketDataClientTests/Fixtures/twelvedata-*.json
ls Wait/Packages/WaitKit/Tests/MarketDataClientTests/Fixtures 2>/dev/null || echo "Fixtures folder is gone"
```
Expected: `Fixtures folder is gone`. Plan 02 only put Twelve Data fixtures there. If the folder is gone, remove `resources: [.copy("Fixtures")]` from the `MarketDataClientTests` target in `Package.swift`, which leaves it as:
```swift
    .testTarget(name: "MarketDataClientTests", dependencies: ["MarketDataClient", "Domain", "APIClient", .dependencies, .dependenciesTestSupport]),
```
If other fixtures remain, keep the `resources` line.

- [ ] **Step 3: Remove the key from build settings and plists**

```bash
cd /Users/ckai/code/Wait/Wait
sed -i '' '/TWELVE_DATA_API_KEY/d' Config/Base.xcconfig Config/Secrets.example.xcconfig
sed -i '' '/Twelve Data is the stopgap/d' Config/Secrets.example.xcconfig
git grep -l TwelveDataAPIKey -- '*.plist' | while read -r plist; do plutil -remove TwelveDataAPIKey "$plist" && echo "removed from $plist"; done
cd /Users/ckai/code/Wait && scripts/check-client-has-no-provider-keys.sh
```
Expected: one `removed from …/Info.plist` line per plist that had the key (at least `Wait/Info.plist`), then `check-client-has-no-provider-keys: ok`. Then `(manual: user)`:
- Delete the `TWELVE_DATA_API_KEY` line from your local, gitignored `Wait/Config/Secrets.xcconfig`.
- Revoke the Twelve Data key in the Twelve Data dashboard.

- [ ] **Step 4: Scrub stale Twelve Data comments from plan 02 code**

In `Wait/Packages/WaitKit/Sources/Domain/MarketTypes.swift`, replace the `CompanyProfile` doc comment
`/// Fundamentals. Plan 02 has no source for these (Twelve Data stopgap). Plan 04 fills them from the backend.`
with
`/// Fundamentals from the Wait backend (`GET /api/market/profile`: Finnhub profile2 + metrics). Ratios are percentages.`

In `Wait/Packages/WaitKit/Sources/MarketDataClient/CachingMarketDataClient.swift`, replace the phrase `(8 symbols/min on Twelve Data)` with `(for example a provider quota)`.

Run: `git grep -niE "twelve ?data|stopgap" -- Wait/Packages/WaitKit/Sources Wait/Packages/WaitKit/Tests`
Expected: no output. If anything remains, it's a comment: rewrite it to describe the backend, and keep the code unchanged.

- [ ] **Step 5: Run every package test and build both apps**

Run: `scripts/test-waitkit.sh && scripts/build-app.sh && scripts/build-app.sh WaitWatch`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` twice.

- [ ] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add -A Wait/Packages/WaitKit Wait/Config Wait scripts/check-client-has-no-provider-keys.sh
git status --short   # expect only the deletions and edits from this task
git commit -m "chore(ios): remove the Twelve Data stopgap and guard against provider keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 30: Docs, end-to-end check, CI notes

**Files:**
- Modify: `/Users/ckai/code/Wait/CLAUDE.md`, `Packages/WaitKit/README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Make these exact replacements in `/Users/ckai/code/Wait/CLAUDE.md`. Plan 03 wrote the first two, and plan 02 may have left the third.

1. Replace the single Market data bullet, including its sub-bullets, with the block below. Remove any leftover "(keep this version…)" text:
```markdown
- **Market data:** `\.marketData` is `MarketDataClient.cached(.backend(.liveValue), disk: .live, now:)`, a caching decorator around `Sources/MarketDataClient/Backend/BackendMarketData.swift`, which calls the Wait backend through `APIClient`. Only the server holds provider keys; the app holds none.
  - The decorator applies market-hours TTLs, coalesces requests, falls back to stale data, and cools down after a 429.
  - Screens read `.cacheOnly`, then `.useCache`. Pull-to-refresh uses `.reload`. A chart fetches only its selected range.
```
2. Replace the bullet that starts `- **Secrets:**` with:
```markdown
- **Config:** `Wait/Config/Base.xcconfig` sets `WAIT_API_BASE_URL` (the Wait backend) and includes the gitignored `Wait/Config/Secrets.xcconfig` for local overrides (copy `Secrets.example.xcconfig`). The app has no provider keys; never commit a secret.
```
3. If the sentence below is still present:
```markdown
Its `liveValue` is `.cached(.twelveData(...))`, a stopgap until plan 04.
```
replace it with:
```markdown
Its `liveValue` is `.cached(.backend(.liveValue), disk: .live, now:)`.
```

Run: `grep -n -i "twelve data\|twelvedata\|alpha vantage\|TWELVE_DATA\|stopgap" /Users/ckai/code/Wait/CLAUDE.md`
Expected: no output.

Then add this section after the iOS architecture section:
```markdown
## Backend (`server/`)

- Fastify 5 + TypeBox, TypeScript ESM, Neon Postgres via raw SQL, vitest + PGlite, and Vercel (Root Directory `server`). See `server/README.md` and overview §8.
- Composition root: `server/src/container.ts`. Every repository is an interface with `Neon*` (SQL) and `Mock*` (in-memory) implementations. Route plugins stay thin and call services.
- Market data: Finnhub (quotes, search, profile, metrics), Tiingo (daily history, 1M/1Y/5Y derived from one `daily5y` pull) and Alpaca (1D/1W bars, 15 min delayed). Results are cached in Postgres per symbol, and a Postgres token bucket enforces each provider's free quota.
- Auth: an anonymous UUID from the iCloud Keychain is exchanged at `POST /api/auth/register` for a 7-day HS256 JWT. `HTTPSession` re-registers once on a 401.
- Commands: `cd server && npm test`, `npm run typecheck`, `npm run dev`, `npm run migrate`.
- Guard: `scripts/check-client-has-no-provider-keys.sh` must pass. The iOS app never contains provider hosts or keys.
```

- [ ] **Step 2: Update `Packages/WaitKit/README.md`**

Append:
```markdown
## APIClient (plan 04)

- `HTTPSession` is an actor. It sends the JWT from memory, registers on first use with `IdentityClient.anonymousID()`, re-registers once on a 401, and maps every non-2xx response to `APIError`.
- `APIClient` (`@Dependency(\.apiClient)`) exposes the market endpoints plus `deleteAccount`. Plans 05 and 06 add sync and device endpoints.
- `KeychainClient` and `IdentityClient` store the anonymous ID under service `com.chenkai.wait`, account `anonymous-id`, synchronizable. Tests always use `KeychainClient.inMemory()`.
- `MarketDataClient.backend(_:)` maps DTOs to Domain types. The live value is `.cached(.backend(.liveValue), disk: .live, now:)`.
```

- [ ] **Step 3: Run the end-to-end check on the simulator `(manual: user)` for the steps that need eyes**

1. `cd /Users/ckai/code/Wait/server && npm test && npm run typecheck`. Expected: all green.
2. `cd /Users/ckai/code/Wait && scripts/check-client-has-no-provider-keys.sh && scripts/check-secrets.sh`. Expected: both print ok.
   Then run the overview §4.1 DoD grep, excluding build output:
   `grep -rni --exclude-dir=.build --exclude-dir=DerivedData --exclude-dir=xcuserdata "twelvedata\|apikey" Wait/`
   Expected: no output.
3. Run the app on the iPhone 17 simulator from Xcode, then check:
   - The watchlist shows prices.
   - In the Vercel runtime logs there are `GET /api/market/quotes` requests and no 5xx responses.
   - Stock Details shows Mkt Cap and P/E.
   - The 1D chart loads.
   - Settings shows the Anonymous ID and the attribution footer.
4. In Settings, tap **Delete Account** and confirm. The ID row shows "Created on next sync". Pull to refresh the watchlist: quotes load again, which means the session re-registered with a new ID.
5. Physical device, iCloud Keychain on: note the Anonymous ID, delete the app, reinstall from Xcode, and open Settings. The same ID is shown (overview §4.1 DoD for plan 04, risk 9).

- [ ] **Step 4: CI notes for the user `(manual: user)`**

Tell the user to update Bitrise (overview risk 19):
1. Remove the step that writes `TWELVE_DATA_API_KEY` into `Secrets.xcconfig` (it was added in plan 03), and delete that secret.
2. Add a step that writes `WAIT_API_BASE_URL = https:/$()/<host>` into `Wait/Config/Secrets.xcconfig`, or rely on the committed default.
3. Add `scripts/check-client-has-no-provider-keys.sh`.
4. Add `cd server && npm ci && npm run typecheck && npm test`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add CLAUDE.md Wait/Packages/WaitKit/README.md
git commit -m "docs: document the Wait backend, APIClient and the provider-key guard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
