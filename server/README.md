# wait-server

Backend for the Wait iOS app: anonymous auth and a cached, rate-limited market-data proxy (plan 04), watchlist sync (plan 05) and daily ladder alerts with APNs pushes (plan 06). Shared contracts are in `../docs/superpowers/plans/2026-11-22-wait-00-overview.md`.

## Stack
Fastify 5 + TypeBox · TypeScript ESM (NodeNext, `.js` import suffixes) · Neon Postgres via raw SQL (`src/db/sql.ts`) · vitest + PGlite · Vercel (one function built from `src/server.ts`). Node 22 or newer.

## Layout
- `src/app.ts`: `buildApp({ config, container })` sets up plugins, the error envelope and the routes.
- `src/container.ts`: the composition root. `createContainer(config)` builds the Neon repositories, live providers and services. `createMockContainer()` builds in-memory versions for tests; it has no database unless a test passes `{ sql }`.
- `src/server.ts`: the Vercel entry. It loads the config from `process.env` at cold start and exports the app and a request handler. `src/index.ts` is the local dev entry (`app.listen`).
- `src/routes/**`: thin route plugins with TypeBox schemas on every route.
- `src/services/**`: business logic: `AuthService`, `MarketDataService`, `WatchlistSyncService`, `DailyCloseResolver`, `AlertJobService`, and `RateLimiter` (a token bucket in Postgres).
- `src/apns/**`: APNs: the ES256 provider token, the HTTP/2 and mock transports, the alert payload and `ApnsSender`.
- `src/db/**`: one interface per repository, each with `Neon*` (SQL) and `Mock*` (in-memory) implementations.
- `src/providers/**`: adapters for Finnhub (quotes, search, profile), Tiingo (daily history), Alpaca (intraday bars, 15 min delayed) and Massive (grouped daily closes).
- `src/domain/**`: the ET market calendar, the cache TTL rules, the New York trading-date helpers and the ladder (`ladder.ts`, including `shouldAlert`).
- `migrations/NNN_name.sql`: re-runnable SQL migrations, applied by `npm run migrate`.

## Commands
```sh
npm ci
npm run typecheck   # src + test + scripts
npm test            # vitest; repository SQL runs against in-process PGlite
npm run build       # tsc -p tsconfig.json, emits to dist/
npm run dev         # http://localhost:3000 (PORT overrides); reads .env.local and .env.development.local, .env.local wins
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
| `MASSIVE_API_KEY` | yes | Massive (ex-Polygon) grouped daily, sent as `Authorization: Bearer` |
| `MASSIVE_BASE_URL` | no | default `https://api.massive.com` |
| `CRON_SECRET` | yes | 16+ characters; Vercel Cron sends it as a bearer token |
| `APNS_KEY` | yes | the `.p8` key: PEM, PEM with literal `\n`, or base64 of the PEM |
| `APNS_KEY_ID`, `APNS_TEAM_ID` | yes | 10-character ids from the Apple Developer portal (team `5WDN96EM72`) |
| `APNS_TOPIC` | no | default `com.chenkai.wait` |
| `LOG_LEVEL` | no | `fatal`, `error`, `warn`, `info`, `debug`, `trace` or `silent`; default `info` |
| `NODE_ENV` | no | `development`, `test` or `production`; default `development`. Set to `production` on Vercel |

## API (plan 04)
All `/api/market/*` routes and `DELETE /api/auth/account` need `Authorization: Bearer <token>`. Every error is returned as `{ "error": { "code", "message" } }`.

| Route | Notes |
|---|---|
| `GET /health` | `{ status, timestamp }` |
| `POST /api/auth/register` `{ anonymousId }` | `anonymousId` must be a UUID. Returns `{ token, user: { id } }`. Idempotent. Rate-limited per IP (20/min) and per id (5/min), then `429 RATE_LIMITED` with `Retry-After`. |
| `DELETE /api/auth/account` | 204. Deletes the user and everything that belongs to them. |
| `GET /api/market/quotes?symbols=AAPL,MSFT` | 1–50 symbols, `{ quotes, missing }`. Quotes stay fresh for 3 min while the market is open. |
| `GET /api/market/history?symbol=AAPL&range=1D\|1W\|1M\|1Y\|5Y` | 1D and 1W come from Alpaca, 15 min delayed. 1M, 1Y and 5Y come from one cached Tiingo `daily5y` series. |
| `GET /api/market/search?q=app` | US common stock, ETP and ADR only. Cached 7 days. |
| `GET /api/market/profile?symbol=AAPL` | Finnhub profile2 (refreshed every 7 days) plus metrics (refreshed daily). |
| `POST /api/devices` `{ token, environment, bundleId? }` | Bearer token. `token` is a lowercase hex APNs device token (64 to 200 characters), `environment` is `sandbox` or `production`. Upserts the token for the user. 204. |
| `DELETE /api/devices/:token` | Bearer token. Removes the token if it belongs to the caller. 204, also when it was already gone. |
| `GET /api/internal/daily-alerts` | Not for the app. Needs `Authorization: Bearer $CRON_SECRET`, else `401`. Runs the daily alert job (see below). |

When a provider is rate-limited, the API serves the cached value with `stale: true`. If nothing is cached, it returns `503 UPSTREAM_RATE_LIMITED` with `Retry-After`. If a provider fails for another reason and nothing is cached, it returns `502 UPSTREAM_UNAVAILABLE`.

## Data licensing
Finnhub, Tiingo and Alpaca free tiers are **personal use only**. This server is for the owner and a few friends. Before any public release, move to a plan that allows external display. Only the adapters in `src/providers/` would change.

## Daily alerts (plan 06)
`AlertJobService` (overview §8.6) runs once per New York trading date:
1. Skips weekends, and returns `holiday` for a day already recorded as one.
2. Claims the day in `alert_job_runs`. A second caller sees `running` and returns `skipped`.
3. Gets closes from `DailyCloseResolver`: one Massive grouped-daily call, then at most 25 same-day Finnhub quotes for the symbols it missed. Over 25, the fallback starts at an offset derived from the trading date, so a different set is covered each day, and a rerun the same day picks the same set. An empty grouped result is a holiday only when SPY's Finnhub quote is dated strictly before the trading date. A null or undated quote throws, so the run stays unfinished and the catch-up retries it.
4. Classifies each live item (not deleted, US-market symbol) with `src/domain/ladder.ts`, inserts `alert_events` (`ON CONFLICT DO NOTHING`) for transitions that pass `shouldAlert`, and updates `watchlist_items.last_status`, which never bumps the sync version. A first evaluation is stored without an event, and so is the evaluation after the anchors change. A close more than 50% away from the last evaluated price is treated as a split and sends nothing.
5. Delivers pending events through `ApnsSender`. Events for deleted items are skipped. Each event is claimed atomically before sending. `apns-expiration` is the next market open and `apns-collapse-id` is `<SYMBOL>-<tradingDate>`. `BadDeviceToken` is retried on the other APNs environment, and a token is pruned on `410`, or after both hosts reject it.

Migration `migrations/004_alerts.sql` adds `device_tokens`, `alert_events` and `alert_job_runs`. The server-owned `last_status`, `last_status_at` and `last_evaluated_price` columns on `watchlist_items` come from `003_watchlist.sql`.

Run the job by hand:
```bash
curl -H "Authorization: Bearer $CRON_SECRET" $WAIT_API_BASE_URL/api/internal/daily-alerts
```
The response is `{ tradingDate, status, evaluated, transitions, alertsCreated, alertsSent, pruned }`, with `status` one of `completed`, `holiday`, `skipped` or `resent`.

Send one push to a device (reads `APNS_*` from `.env.local`; `--status` and `--price` are optional):
```bash
npm run send-test-push -- --token <hex> --env sandbox --symbol AAPL
```

To re-run a day from scratch (debugging only), delete that day's row from `alert_job_runs`.

### Cron
`GET /api/internal/daily-alerts` is called by Vercel Cron with `Authorization: Bearer $CRON_SECRET`. `vercel.json` has two entries for the same path: `0 22 * * 1-5` (the run) and `30 23 * * 1-5` (a catch-up). Hobby crons fire at most once a day each, so a retry needs its own entry.

- **Catch-up:** the second call on the same trading day takes over a crashed run (a `running` row older than 10 min) or, when the day is `completed`, only delivers events that are still unsent (`attempts < 3`) and returns `resent`. Events are claimed one at a time (`attempts + 1 WHERE attempts = <read value>`), so overlapping calls never push the same alert twice.
- **Delivery budget:** pushes go out 5 at a time. No new send starts 45 s after the run began; what is left stays pending for the catch-up. Each APNs request times out after 3 s, with one retry after 1 s. The job closes its HTTP/2 sessions at the end of every run.
- **maxDuration:** the function needs **at least 60 s**. The legacy `builds` config in `vercel.json` cannot set `maxDuration`, so rely on the project default: with Fluid Compute on (the default for new projects) the default duration is 300 s on every plan; with it off, Hobby is capped at 10 s and the run would be killed mid-delivery. To verify, open Project Settings → Functions and check that Fluid Compute is enabled (or Function Max Duration is ≥ 60 s), then trigger the cron from the dashboard (Settings → Cron Jobs → Run) and look at the invocation in Logs: its duration, the `alerts.daily` line, and no `alerts.delivery_deadline` warning (that warning means the budget ran out and the catch-up had to finish the job).

## Watchlist sync

- `POST /api/watchlist/sync` with `{ cursor, changes[] }` (at most 200 changes) returns `{ changes[], cursor, hasMore }`. `GET /api/watchlist` returns the live items. Shapes and rules are in `docs/superpowers/plans/2026-11-22-wait-00-overview.md` §8.4–§8.5.
- Migration: `migrations/003_watchlist.sql`. `npm run migrate` applies it.
- Tests:
  - `test/db/watchlistRepositoryContract.ts` runs against both `NeonWatchlistRepository` (on PGlite) and `MockWatchlistRepository`.
  - The service is tested in `test/services/WatchlistSyncService.test.ts`, and the routes in `test/routes/watchlist.test.ts`.
- `src/domain/ladder.ts` mirrors the Swift ladder. `test/domain/ladder.test.ts` reads `../shared/ladder-test-vectors.json`.
