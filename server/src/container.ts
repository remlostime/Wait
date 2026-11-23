import { ApnsSender } from "./apns/ApnsSender.js"
import { ApnsTokenProvider } from "./apns/ApnsTokenProvider.js"
import { Http2ApnsTransport } from "./apns/Http2ApnsTransport.js"
import { MockApnsTransport } from "./apns/MockApnsTransport.js"
import type { Config } from "./config.js"
import type { AlertRepository } from "./db/AlertRepository.js"
import type { DeviceTokenRepository } from "./db/DeviceTokenRepository.js"
import type { MarketCacheRepository } from "./db/MarketCacheRepository.js"
import { MockAlertRepository } from "./db/MockAlertRepository.js"
import { MockDeviceTokenRepository } from "./db/MockDeviceTokenRepository.js"
import { MockMarketCacheRepository } from "./db/MockMarketCacheRepository.js"
import { MockUserRepository } from "./db/MockUserRepository.js"
import { MockWatchlistRepository } from "./db/MockWatchlistRepository.js"
import { NeonAlertRepository } from "./db/NeonAlertRepository.js"
import { NeonDeviceTokenRepository } from "./db/NeonDeviceTokenRepository.js"
import { NeonMarketCacheRepository } from "./db/NeonMarketCacheRepository.js"
import { NeonUserRepository } from "./db/NeonUserRepository.js"
import { NeonWatchlistRepository } from "./db/NeonWatchlistRepository.js"
import { neonSql, type Sql } from "./db/sql.js"
import type { UserRepository } from "./db/UserRepository.js"
import type { WatchlistRepository } from "./db/WatchlistRepository.js"
import type { FastifyBaseLogger } from "fastify"
import { fixedClock, systemClock, type Clock } from "./lib/clock.js"
import { createLogger } from "./lib/logger.js"
import { AlpacaProvider } from "./providers/alpaca.js"
import { FinnhubProvider } from "./providers/finnhub.js"
import { createMassiveProvider } from "./providers/massive.js"
import { TiingoProvider } from "./providers/tiingo.js"
import { ProviderError, type ProviderName } from "./providers/types.js"
import { AlertJobService, type AlertJob } from "./services/AlertJobService.js"
import { AuthService } from "./services/AuthService.js"
import { DailyCloseResolver } from "./services/DailyCloseResolver.js"
import { MarketDataService, type MarketProviders } from "./services/MarketDataService.js"
import { MockRateLimiter, PostgresRateLimiter, type RateLimiter } from "./services/RateLimiter.js"
import { WatchlistSyncService } from "./services/WatchlistSyncService.js"

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
  watchlist: WatchlistRepository
  watchlistSync: WatchlistSyncService
  deviceTokens: DeviceTokenRepository
  alerts: AlertRepository
  alertJob: AlertJob
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
  const watchlist = new NeonWatchlistRepository(sql)
  const finnhub = new FinnhubProvider(config.finnhubApiKey)
  const providers: MarketProviders = {
    quotes: finnhub,
    search: finnhub,
    profile: finnhub,
    daily: new TiingoProvider(config.tiingoApiKey),
    intraday: new AlpacaProvider(config.alpacaKeyId, config.alpacaSecretKey, clock),
  }
  const deviceTokens = new NeonDeviceTokenRepository(sql)
  const alerts = new NeonAlertRepository(sql)
  const alertJob = new AlertJobService({
    alerts,
    devices: deviceTokens,
    closes: new DailyCloseResolver({
      grouped: createMassiveProvider({ apiKey: config.massive.apiKey, baseUrl: config.massive.baseUrl }),
      quotes: finnhub,
      rateLimiter,
    }),
    sender: new ApnsSender({
      transport: new Http2ApnsTransport(),
      tokens: new ApnsTokenProvider({ key: config.apns.key, keyId: config.apns.keyId, teamId: config.apns.teamId }, clock),
      topic: config.apns.topic,
      devices: deviceTokens,
      clock,
    }),
  })
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
    watchlist,
    watchlistSync: new WatchlistSyncService(watchlist),
    deviceTokens,
    alerts,
    alertJob,
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
  const watchlist = overrides.watchlist ?? new MockWatchlistRepository()
  const deviceTokens = overrides.deviceTokens ?? new MockDeviceTokenRepository()
  const alerts = overrides.alerts ?? new MockAlertRepository()
  const alertJob =
    overrides.alertJob ??
    new AlertJobService({
      alerts,
      devices: deviceTokens,
      closes: { resolve: async () => ({ kind: "holiday" as const }) },
      sender: new ApnsSender({
        transport: new MockApnsTransport(),
        tokens: { token: () => "mock-provider-token", invalidate: () => {} },
        topic: "com.chenkai.wait",
        devices: deviceTokens,
        clock,
      }),
    })
  return {
    clock,
    logger,
    sql: overrides.sql ?? noDatabase,
    users,
    rateLimiter,
    auth: overrides.auth ?? new AuthService(users, rateLimiter, clock),
    marketCache,
    marketData: overrides.marketData ?? new MarketDataService({ cache: marketCache, limiter: rateLimiter, providers: unavailableProviders(), clock, logger }),
    watchlist,
    watchlistSync: overrides.watchlistSync ?? new WatchlistSyncService(watchlist),
    deviceTokens,
    alerts,
    alertJob,
  }
}
