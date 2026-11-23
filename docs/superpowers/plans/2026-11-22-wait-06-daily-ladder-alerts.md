# Daily Ladder Alerts Implementation Plan (Plan 06)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After every US trading day, the server checks each synced watchlist item's price ladder against the closing price. It sends an APNs push when a stock moves down into BUY_ZONE/DEEP_BUY or up into TRIM/SELL. Tapping the push opens that stock in the app.

**Architecture:**
- **Trigger:** Vercel Cron (`0 22 * * 1-5` UTC) calls `GET /api/internal/daily-alerts`, which is guarded by `CRON_SECRET`.
- **Closing prices:** `DailyCloseResolver` makes one Massive grouped-daily call. A Finnhub fallback covers up to 25 symbols, and an SPY date check detects market holidays.
- **Evaluation:** `AlertJobService` classifies each item with `domain/ladder.ts`.
  - It records idempotent `alert_events`.
  - It updates the server-owned `last_status` column.
  - It delivers pending events through `ApnsSender` (ES256 provider token, `node:http2` transport).
- **iOS:**
  - A new `NotificationClient` handles permission, remote registration and taps.
  - `PushFeature`, a child of `AppFeature`, registers the device token through `POST /api/devices`.
  - Settings gets a "Daily alerts" toggle.

**Tech Stack:**
- Server: TypeScript, Fastify 5, TypeBox, Neon / PGlite, vitest, `node:crypto`, `node:http2`.
- iOS: Swift 6, TCA 1.26, swift-dependencies, swift-sharing, UserNotifications.

**Spec:** `docs/superpowers/plans/2026-11-22-wait-00-overview.md` §7.3 (alert rule), §8.3 (schema), §8.4 (endpoints), §8.6 (job), §8.7 (APNs), §9, §12.

> **Deviations from overview** (all small; none change a wire format):
> 1. **Bad device tokens:**
>    - On `400 BadDeviceToken`, `ApnsSender` retries **once against the other APNs environment** before pruning, and on success updates the stored environment. A token is therefore pruned only after both hosts reject it, which makes §8.7's "prune only if the environment matches" concrete.
>    - `DeviceTokenNotForTopic` is never pruned: it means our topic is misconfigured, and pruning on it would wipe every token. It returns `failed` and is logged.
> 2. **Extra files** not listed in §8.1/§12.1:
>    - `server/src/apns/types.ts`
>    - `server/src/services/DailyCloseResolver.ts` (steps 4–6 of §8.6)
>    - `server/src/schemas/alerts.ts`
>    - `server/test/support/apnsKey.ts`
>    - `Sources/NotificationClient/NotificationPayload.swift`
>    - `Sources/NotificationClient/NotificationClient+Live.swift`
>    - `Sources/AppFeature/PushFeature.swift`
> 3. **`AlertRepository` owns its SQL** on the server-owned `watchlist_items` columns. Plan 05's `WatchlistRepository` is not changed.
>    - `applyEvaluations` only overwrites a row whose `last_status` is still the value the job read (`IS NOT DISTINCT FROM`). A concurrent anchor reset by sync, which sets it to NULL, therefore wins.
> 4. **Concurrent cron deliveries** (§8.6 step 2 refinement): `beginRun` claims the day atomically.
>    - A `running` row started less than 10 minutes ago makes the second caller return `skipped` (in progress).
>    - An older `running` row is treated as crashed and taken over.
> 5. **Notification logic lives in a child reducer** (`PushFeature`) scoped into `AppFeature`.
>    - `AppFeature` forwards `AppDelegateAction`s to it.
>    - `PushFeature.Delegate.openStock` becomes the existing `.openURL(wait://stock/SYM)`.
>    - This keeps §12.3's "tap stream → openURL", but is testable without plan 02–05 launch effects.
> 6. **Two app-storage keys** in `Persistence/SharedKeys.swift`: `.alertsEnabled` (`Bool`) and `.apnsDeviceToken` (`String?`).
>    - The token is cleared only after `DELETE /api/devices/:token` succeeds. Launch retries a pending unregistration.
> 7. **Massive failures don't fail the job.** Any non-OK Massive response (including a 403 before the day is published) counts as "no grouped data", and the job falls back to the SPY check plus Finnhub.
> 8. **The APNs key is parsed lazily**, on the first `token()` call. A bad `APNS_KEY` breaks only push delivery, never cold start for the auth, market and sync routes.
> 9. **Chunks:** the spec's "Devices and job" chunk is split into Chunks 5 and 6, and the iOS work into Chunks 7–9, to keep every chunk under 1000 lines.

---

## Prerequisites

- [x] **Worktree.** Not created: the session rules say to work in place on `ck/sever` in `/Users/ckai/code/Wait`.
  - Use `superpowers:using-git-worktrees` to create a worktree off `ck/new-version`. Never `master`.
  - Every path below is relative to the worktree's root (`/Users/ckai/code/Wait` in the examples).
- [ ] **Plans 01–05 are done.** Each of these must pass:
  - `cd server && npm run typecheck && npm test` is green. (Server green: 209/209 on 2026-11-23.)
  - The `WaitKit-Package` tests are green. (NOT RUN (code-only); plan 05 iOS (`SyncClient`) still pending.)
  - `POST /api/watchlist/sync` is deployed. (server tests green; deploy pending, manual)
  - Migrations 001–003 are applied in production. (server tests green; deploy pending, manual)
- [ ] **(manual: user) Massive.** — SKIPPED (manual) Sign up at https://massive.com (free "Basic" stocks plan) and copy the API key.
- [ ] **(manual: user) APNs key.** — SKIPPED (manual)
  1. Go to https://developer.apple.com/account/resources/authkeys/list and click **+**.
  2. Enable **Apple Push Notifications service (APNs)**, then **Continue → Register**.
  3. **Download** `AuthKey_<KEYID>.p8`. It can be downloaded only once.
  4. Note the 10-character **Key ID**. The Team ID is `5WDN96EM72`.
  5. Store the key base64-encoded:
     ```bash
     base64 -i AuthKey_<KEYID>.p8 | tr -d '\n'
     ```
- [ ] **(manual: user) Cron secret.** — SKIPPED (manual) Generate it with `openssl rand -hex 32`.
- [ ] **(manual: user) Push capability.** — SKIPPED (manual) In Certificates, IDs & Profiles → Identifiers → `com.chenkai.wait`, check that **Push Notifications** is enabled. Xcode's automatic signing usually turns it on once the entitlement is present; Task 23 checks it again.
- [ ] **(manual: user) Local env.** — SKIPPED (manual) Add these lines to `server/.env.local`, which is gitignored. Every config-loading command in this plan needs them.
  ```
  MASSIVE_API_KEY=<massive key>
  CRON_SECRET=<64 hex chars>
  APNS_KEY=<base64 of the .p8>
  APNS_KEY_ID=<KEYID>
  APNS_TEAM_ID=5WDN96EM72
  ```
- [ ] **Skills to load:**
  - `superpowers:test-driven-development` for every task.
  - `swiftui-expert:swiftui-expert-skill` for Task 22 (the `AlertsSection` view).
  - `ios-code-best-practice:ios-code-best-practice` for Swift concurrency in Task 19. Use only its concurrency guidance; the Pinterest-only parts don't apply.

### Interfaces this plan uses from plans 02–05

Task 1 checks every row. If a name differs, use the real name everywhere this plan uses it, and record each substitution in the commit message of the first task that touches it.

| Name | Definition | File (plan) |
|---|---|---|
| `Sql`, `Row` | `type Sql = (strings: TemplateStringsArray, ...values: unknown[]) => Promise<Row[]>` | `server/src/db/sql.ts` (04) |
| `createTestDb`, `TestDb` | `createTestDb(): Promise<TestDb>`, where `TestDb = { db: TestDatabase; sql: Sql; close(): Promise<void> }` and every migration is applied | `server/test/support/pglite.ts` (04) |
| `buildTestApp`, `testConfig` | `buildTestApp(overrides?: Partial<Container>) → { app, container, user, authHeaders(userId?) }`; `testConfig: Config` | `server/test/support/app.ts` (04) |
| `Clock`, `fixedClock` | `interface Clock { now(): Date }`<br>`fixedClock(start: Date): FixedClock` with `set(date)` and `advance(ms)` | `server/src/lib/clock.ts` (04) |
| `asDate`, `asNullableDate` | normalize a timestamp from a `Date` or a string | `server/src/lib/time.ts` (04) |
| `sendError`, `AppError` | `sendError(reply, statusCode, code, message)`; `new AppError(code, message, statusCode)` | `server/src/lib/errors.ts` (04) |
| `safeEqual` | `(a: string, b: string) => boolean` | `server/src/lib/safeEqual.ts` (04) |
| `ErrorResponseSchema`, `SYMBOL_REGEX` | TypeBox schema for `{ error: { code, message } }`; the US market symbol regex `^[A-Z]{1,5}([.-][A-Z]{1,2})?$` | `server/src/schemas/common.ts` (04) |
| `etDateString`, `MarketLogger` | `etDateString(at: Date): string` (New York date); `MarketLogger { warn(details, message) }`. `LogSink` (Task 8) is a superset, so a `LogSink` can be passed wherever a `MarketLogger` is expected | `server/src/domain/marketCalendar.ts`, `server/src/services/MarketDataService.ts` (04) |
| `RateLimiter`, `BucketPolicy`, `PROVIDER_BUCKETS` | `tryTake(key, policy, cost?)`, `block(key, seconds)`<br>`PROVIDER_BUCKETS.massive` and `.finnhub` are `{ key, policy }` | `server/src/services/RateLimiter.ts` (04) |
| `ProviderError`, `ProviderName` | `new ProviderError(provider, kind, retryAfterSec?, status?)`<br>`ProviderName` already includes `"massive"` | `server/src/providers/types.ts` (04) |
| `QuoteProvider`, `ProviderQuote` | `getQuote(symbol): Promise<ProviderQuote \| null>`<br>`ProviderQuote { symbol, price, previousClose, open, high, low, change, changePercent, asOf: string }` | `server/src/providers/types.ts` (04) |
| `FetchLike`, `parseRetryAfter` | `(url, init?) => Promise<Response>`; `parseRetryAfter(header): number \| undefined` | `server/src/providers/http.ts` (04) |
| `loadConfig`, `Config`, `ConfigError` | zod-based. Inside `loadConfig`, the parsed env is `const e = parsed.data`. It returns camelCase fields. `ConfigError` names the bad variables | `server/src/config.ts` (04) |
| `Container`, `RouteOptions` | fields `clock`, `logger` (`FastifyBaseLogger`), `sql`, `users`, `rateLimiter`, `auth`, `marketCache`, `marketData` (04) and `watchlist`, `watchlistSync` (05)<br>`createContainer(config)` has a local `finnhub` provider<br>`createMockContainer(overrides)` uses `overrides.x ?? default`<br>`RouteOptions = { container }` | `server/src/container.ts` (04/05) |
| Route registration | `await app.register(plugin, { prefix, container })` in `buildApp({ config, container })`<br>Ajv runs with `coerceTypes: false, removeAdditional: false` (overview §8.1) | `server/src/app.ts` (04) |
| `buildAuthMiddleware` | `buildAuthMiddleware(container.users) → { authenticate }`; sets `request.authenticatedUser: User` | `server/src/middleware/auth.ts` (04) |
| Ladder domain | `LadderInput = Partial<Record<Rung, string \| null>>`<br>`Rung`, `RUNGS`, `LADDER_STATUSES` (`as const`), `LadderStatus`<br>`classifyStatus(ladder, price: number)`, `temperature(ladder, price: number)` | `server/src/domain/ladder.ts` (05) |
| Package.swift helpers | `.tca`, `.dependencies`, `.dependenciesMacros`, `.dependenciesTestSupport`, `.sharing` | `Wait/Packages/WaitKit/Package.swift` (02) |
| `scripts/test-waitkit.sh` | `scripts/test-waitkit.sh <TestTarget[/Suite]> …`, run from the repo root | `scripts/test-waitkit.sh` (02) |
| `Log.push` | a `LogChannel` with `error(_ message: String)` (public privacy); use plain interpolation | `Sources/Logging/Log.swift` (02) |
| `HTTPSession`, `APIClient.live` | `post(_ path:, body:) async throws` (no-response overload; 204 is fine), `delete(_ path:) async throws`<br>`APIClient.live(session:)`, `APIClient.misconfigured`<br>`HTTPSession(baseURL:session:anonymousID:)` | `Sources/APIClient/` (04) |
| `AppFeature`, `AppDelegate` | `State`, `Action` (`.appDelegate`, `.openURL`), `body` with `Scope`s<br>`AppDelegate` with `lazy var store`, inside the AppFeature target | `Sources/AppFeature/AppFeature.swift`, `Sources/AppFeature/AppDelegate.swift` (02) |
| Plans 03/05 clients | `ConnectivityClient.noop`; `\.syncClient` (`sync`, `reset`) returning `SyncReport()` (all fields default) | `Sources/Connectivity`, `Sources/SyncClient` (03, 05) |
| `SettingsFeature` | `State`, `Action` (`.task`, plan 05's `syncNowTapped`), `SettingsView` | `Sources/SettingsFeature/` (02–05) |

Every `.run` closure captures its dependencies explicitly, e.g. `.run { [notifications] send in … }` (overview §12.3).

---

## File Structure

### Server (`/Users/ckai/code/Wait/server`)

| Path | Action | Responsibility |
|---|---|---|
| `src/domain/ladder.ts` | Modify | Append `AlertStatus`, `parseLadderStatus`, `isAlertStatus`, `statusRank` and `shouldAlert`, reusing `LADDER_STATUSES` |
| `src/domain/tradingDate.ts` | Create | Convert an instant to its America/New_York date; detect weekends |
| `migrations/004_alerts.sql` | Create | Tables `device_tokens`, `alert_events`, `alert_job_runs` |
| `src/db/DeviceTokenRepository.ts` | Create | `ApnsEnvironment`, `DeviceToken`, `DeviceRegistration` and the repository interface |
| `src/db/NeonDeviceTokenRepository.ts`, `src/db/MockDeviceTokenRepository.ts` | Create | SQL and in-memory implementations |
| `src/db/AlertRepository.ts` | Create | Types for job items, evaluations, events and runs, plus the interface |
| `src/db/NeonAlertRepository.ts`, `src/db/MockAlertRepository.ts` | Create | SQL over the server-owned `watchlist_items` columns, `alert_events` and `alert_job_runs`; in-memory twin |
| `src/providers/types.ts` | Modify | Append `DailyClose` and `GroupedDailyProvider` |
| `src/providers/massive.ts` | Create | Massive grouped-daily adapter |
| `src/lib/logSink.ts` | Create | `LogSink` (the `info`/`warn` subset of pino) and `silentLog` |
| `src/services/DailyCloseResolver.ts` | Create | Grouped closes, then the holiday check, then the Finnhub fallback |
| `src/apns/types.ts` | Create | `ApnsRequest`, `ApnsResponse`, `ApnsTransport` |
| `src/apns/ApnsTokenProvider.ts` | Create | `normalizeApnsKey`, plus an ES256 provider JWT that parses the key lazily and caches the token for 50 minutes |
| `src/apns/payload.ts` | Create | `buildPayload`: alert JSON and collapse id |
| `src/apns/Http2ApnsTransport.ts`, `src/apns/MockApnsTransport.ts` | Create | `node:http2` transport (one session per host, destroyed on timeout) and a scripted mock |
| `src/apns/ApnsSender.ts` | Create | Headers, retries, pruning, environment repair, failure logging (never logs the token) |
| `src/services/AlertJobService.ts` | Create | Overview §8.6, with run claiming and an injected logger |
| `src/schemas/devices.ts`, `src/schemas/alerts.ts` | Create | TypeBox schemas, with nullable unions written null-first |
| `src/routes/api/devices.ts` | Create | `POST /api/devices`, `DELETE /api/devices/:token` (`RouteOptions`) |
| `src/routes/api/internal/dailyAlerts.ts` | Create | `GET /api/internal/daily-alerts` (`RouteOptions` plus `cronSecret`) |
| `src/config.ts`, `src/container.ts`, `src/app.ts` | Modify | Config keys, wiring, route registration |
| `vercel.json`, `.env.example`, `README.md`, `package.json` | Modify | Cron entry, env names, docs, `send-test-push` script |
| `scripts/send-test-push.ts` | Create | Manual end-to-end push check |
| `test/config.test.ts`, `test/server.test.ts`, `test/support/app.ts` | Modify | Add the new required env and config values |
| `test/support/apnsKey.ts` | Create | A P-256 key pair generated at test start (PEM and base64) |
| `test/support/alertFixtures.ts`, `test/support/alertFakes.ts`, `test/support/alertScenario.ts` | Create | PGlite row inserts; fake rate limiter, quote and grouped providers; the shared job scenario |
| `test/support/fixtures/massive/*.json` | Create | Massive response fixtures |
| `test/**/*.test.ts` | Create | One test file per unit; each task lists its own |

### iOS (`/Users/ckai/code/Wait/Wait`)

| Path | Action | Responsibility |
|---|---|---|
| `Packages/WaitKit/Package.swift` | Modify | The `NotificationClient` target and its test target; dependencies of `AppFeature`, `SettingsFeature` and their test targets |
| `Sources/NotificationClient/NotificationClient.swift` | Create | Interface, `NotificationAuthorization`, and the `\.notifications` key |
| `Sources/NotificationClient/NotificationPayload.swift` | Create | Reads the symbol out of a push `userInfo` |
| `Sources/NotificationClient/NotificationClient+Live.swift` | Create | `UNUserNotificationCenterDelegate` and the live value |
| `Sources/APIClient/DTOs/DeviceRegistrationDTO.swift` | Create | DTO, `Environment.current`, `APNsToken.hexString` |
| `Sources/APIClient/APIClient.swift` | Modify | `registerDevice` and `unregisterDevice`, via the existing `HTTPSession.post`/`delete` |
| `Sources/Persistence/SharedKeys.swift` | Modify | `.alertsEnabled`, `.apnsDeviceToken` |
| `Sources/AppFeature/PushFeature.swift` | Create | Launch registration, pending unregistration, tap stream, device-token upload |
| `Sources/AppFeature/AppFeature.swift`, `AppDelegateAction.swift`, `AppDelegate.swift` | Modify | Scope `PushFeature`; forward the APNs callbacks; install the notification delegate |
| `Sources/SettingsFeature/SettingsFeature.swift`, `SettingsView.swift` | Modify | Alerts state and actions; show the section |
| `Sources/SettingsFeature/AlertsSection.swift` | Create | "Daily alerts" toggle and the "Open Settings" link |
| `Tests/NotificationClientTests/…`, `Tests/APIClientTests/DeviceEndpointTests.swift`, `Tests/AppFeatureTests/PushFeatureTests.swift`, `Tests/AppFeatureTests/AppFeaturePushRoutingTests.swift`, `Tests/SettingsFeatureTests/SettingsAlertsTests.swift` | Create | Tests |
| `project.yml`, `/Users/ckai/code/Wait/CLAUDE.md`, `Packages/WaitKit/README.md` | Modify | Entitlement check, docs |

---

## Chunk 1: Interfaces, alert rule, trading date, migration

### Task 1: Verify cross-plan interfaces

**Files:** none (read-only check)

- [x] **Step 1: Check the server names this plan depends on**

> Result (2026-11-23): all 28 greps print `1`; the shouldAlert/parseLadderStatus/statusRank grep prints nothing; the config-builder grep prints one line per file (`test/config.test.ts:4`, `test/server.test.ts:3`, `test/support/app.ts:5`). No substitutions. The remaining table rows (`Clock`/`FixedClock`, `asNullableDate`, `AppError`, `MarketLogger`, `BucketPolicy`, `PROVIDER_BUCKETS.massive/.finnhub`, `QuoteProvider`, `Container` fields, `RouteOptions`) were also found as described.

Run each line from `/Users/ckai/code/Wait/server`. Every line must print exactly one match. A `grep -c` printing `0` means the name differs: find the real one and substitute it (see the Interfaces table).
```bash
cd /Users/ckai/code/Wait/server
grep -c "^export type Sql\b" src/db/sql.ts
grep -c "^export async function createTestDb\b" test/support/pglite.ts
grep -c "^export interface TestDb\b" test/support/pglite.ts
grep -c "^export async function buildTestApp\b" test/support/app.ts
grep -c "^export const testConfig\b" test/support/app.ts
grep -c "^export function fixedClock\b" src/lib/clock.ts
grep -c "^export function asDate\b" src/lib/time.ts
grep -c "^export function sendError\b" src/lib/errors.ts
grep -c "^export function safeEqual\b" src/lib/safeEqual.ts
grep -c "^export const ErrorResponseSchema\b" src/schemas/common.ts
grep -c "^export const SYMBOL_REGEX\b" src/schemas/common.ts
grep -c "^export function etDateString\b" src/domain/marketCalendar.ts
grep -c "^export const PROVIDER_BUCKETS\b" src/services/RateLimiter.ts
grep -c "^export interface RateLimiter\b" src/services/RateLimiter.ts
grep -c "^export class ProviderError\b" src/providers/types.ts
grep -c '^export type ProviderName = .*"massive"' src/providers/types.ts
grep -c "^export interface ProviderQuote\b" src/providers/types.ts
grep -c "^export type FetchLike\b" src/providers/http.ts
grep -c "^export function parseRetryAfter\b" src/providers/http.ts
grep -c "^export type LadderInput\b" src/domain/ladder.ts
grep -c "^export const LADDER_STATUSES\b" src/domain/ladder.ts
grep -c "^export type LadderStatus\b" src/domain/ladder.ts
grep -c "^export function classifyStatus\b" src/domain/ladder.ts
grep -c "^export function temperature\b" src/domain/ladder.ts
grep -c "^export function loadConfig\b" src/config.ts
grep -c "^export interface Container\b" src/container.ts
grep -c "^export interface RouteOptions\b" src/container.ts
grep -c "^export function buildAuthMiddleware\b" src/middleware/auth.ts
grep -c "coerceTypes: false, removeAdditional: false" src/app.ts
```
Then run these, which must print **nothing**. If plan 05 already defines one of these names, keep its definition and leave that function out of Task 2.
```bash
grep -n "^export function shouldAlert\b\|^export function parseLadderStatus\b\|^export function statusRank\b" src/domain/ladder.ts
```
Finally, find the three places that build a config or env for tests. Task 13 edits each one:
```bash
grep -n "const validEnv\|const env = {\|export const testConfig" test/config.test.ts test/server.test.ts test/support/app.ts
```
Expected: one line for each of the three files.

- [x] **Step 2: Check the iOS names this plan depends on**

> Result (2026-11-23), verified now: `scripts/test-waitkit.sh` (executable), the `.dependenciesTestSupport` helper (and `.tca`, `.dependencies`, `.dependenciesMacros`, `.sharing`), `Log.push`, `HTTPSession.post` (no-response overload), `HTTPSession.delete`, `APIClient.live(session:)`, `APIClient.misconfigured`, `HTTPSession.init(baseURL:session:anonymousID:)`, `AppDelegate` `lazy var store`, `AppFeature` `case .appDelegate(.didFinishLaunching):`, `ConnectivityClient.noop`, and `aps-environment` in both `Wait.entitlements` and `WaitRelease.entitlements` (not in `project.yml`, which only references the entitlement files). No substitutions.
> Verified before Chunk 7 (2026-11-23, plan 05 code-complete): `Sources/SyncClient/SyncChange.swift` has `public struct SyncReport` with `public init(pushed: Int = 0, pulled: Int = 0, applied: Int = 0, rounds: Int = 0)` and `static let empty`; `SyncClient.swift` has `\.syncClient` (`sync: () async throws -> SyncReport`, `reset: () async -> Void`); `SettingsFeature.Action` has `case task` and `case syncNowTapped` (plus `syncFinished(SyncReport)` and `syncFailed(String)`). No substitutions.

Run each line from `/Users/ckai/code/Wait`. Each `grep -c` must print `1` or more:
```bash
cd /Users/ckai/code/Wait
test -x scripts/test-waitkit.sh && echo "test-waitkit ok"
grep -c "static let dependenciesTestSupport\b" Wait/Packages/WaitKit/Package.swift
grep -c "static let push = LogChannel" Wait/Packages/WaitKit/Sources/Logging/Log.swift
grep -c "public func post<Body: Encodable & Sendable>(_ path: String, body: Body) async throws {" Wait/Packages/WaitKit/Sources/APIClient/HTTPSession.swift
grep -c "public func delete(_ path: String) async throws" Wait/Packages/WaitKit/Sources/APIClient/HTTPSession.swift
grep -c "public static func live(session: HTTPSession) -> APIClient" Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift
grep -c "static let misconfigured = APIClient(" Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift
grep -c "lazy var store" Wait/Packages/WaitKit/Sources/AppFeature/AppDelegate.swift
grep -c "case .appDelegate(.didFinishLaunching):" Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift
grep -c "static let noop = ConnectivityClient" Wait/Packages/WaitKit/Sources/Connectivity/ConnectivityClient.swift
grep -c "public init(pushed: Int = 0" Wait/Packages/WaitKit/Sources/SyncClient/*.swift
grep -c "case task" Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift
grep -n "aps-environment" Wait/project.yml Wait/Wait/Wait.entitlements Wait/Wait/WaitRelease.entitlements
```
Expected: `test-waitkit ok`, every count at least `1`, and at least one `aps-environment` line.

- [x] **Step 3: Confirm the baseline is green** — server part only; `scripts/test-waitkit.sh` NOT RUN (code-only)

> Result (2026-11-23): `npm run typecheck` exits 0; `npm test` 29 files, 209/209 passed.

Run:
```bash
cd /Users/ckai/code/Wait/server && npm run typecheck && npm test
cd /Users/ckai/code/Wait && scripts/test-waitkit.sh
```
Expected: `tsc` exits 0, vitest reports every file passed, and the package run ends with `** TEST SUCCEEDED **`. If anything fails, stop: plans 01–05 aren't finished.

No commit for this task.

---

### Task 2: Directional alert rule (`shouldAlert`)

**Files:**
- Modify: `server/src/domain/ladder.ts` (append at the end)
- Test: `server/test/domain/shouldAlert.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/domain/shouldAlert.test.ts`:
```ts
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { isAlertStatus, parseLadderStatus, shouldAlert, statusRank, type LadderStatus } from "../../src/domain/ladder.js"

type AlertVector = { previous: LadderStatus | null; next: LadderStatus; alert: boolean }

const vectors = JSON.parse(
  readFileSync(new URL("../../../shared/ladder-test-vectors.json", import.meta.url), "utf8"),
) as { alerts: AlertVector[] }

describe("shouldAlert (shared vectors)", () => {
  it("has the alert vectors from the overview", () => {
    expect(vectors.alerts.length).toBeGreaterThanOrEqual(11)
  })

  it.each(vectors.alerts)("$previous -> $next alerts: $alert", ({ previous, next, alert }) => {
    expect(shouldAlert(previous, next)).toBe(alert)
  })
})

describe("shouldAlert edge cases", () => {
  it("never alerts into or out of NO_ANCHORS", () => {
    expect(shouldAlert("NO_ANCHORS", "BUY_ZONE")).toBe(false)
    expect(shouldAlert("WATCH", "NO_ANCHORS")).toBe(false)
  })

  it("alerts on a crash straight from SELL to DEEP_BUY", () => {
    expect(shouldAlert("SELL", "DEEP_BUY")).toBe(true)
  })

  it("stays quiet when falling from SELL to AT_OR_ABOVE_FAIR", () => {
    expect(shouldAlert("SELL", "AT_OR_ABOVE_FAIR")).toBe(false)
  })
})

describe("statusRank", () => {
  it("orders statuses from cheapest to richest", () => {
    const order: LadderStatus[] = ["DEEP_BUY", "BUY_ZONE", "WATCH", "AT_OR_ABOVE_FAIR", "TRIM", "SELL"]
    expect(order.map((status) => statusRank(status))).toEqual([0, 1, 2, 3, 4, 5])
    expect(statusRank("NO_ANCHORS")).toBeNull()
  })
})

describe("parseLadderStatus / isAlertStatus", () => {
  it("accepts only known status strings", () => {
    expect(parseLadderStatus("BUY_ZONE")).toBe("BUY_ZONE")
    expect(parseLadderStatus("buy_zone")).toBeNull()
    expect(parseLadderStatus(null)).toBeNull()
    expect(parseLadderStatus(7)).toBeNull()
  })

  it("treats only the four push-worthy statuses as alert statuses", () => {
    expect(["DEEP_BUY", "BUY_ZONE", "TRIM", "SELL"].every((status) => isAlertStatus(status))).toBe(true)
    expect(["WATCH", "AT_OR_ABOVE_FAIR", "NO_ANCHORS"].some((status) => isAlertStatus(status))).toBe(false)
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ckai/code/Wait/server && npx vitest run test/domain/shouldAlert.test.ts`
Expected: FAIL. The new exports don't exist yet, so vitest reports `… is not a function` or a missing-export error.

- [x] **Step 3: Implement the rule**

Append to `server/src/domain/ladder.ts`. It reuses the file's existing `LADDER_STATUSES` and `LadderStatus`, so don't redeclare them. If Task 1 found that plan 05 already exports `parseLadderStatus`, leave that function out.
```ts
/** Statuses that can trigger a push (overview §7.3). */
export type AlertStatus = "DEEP_BUY" | "BUY_ZONE" | "TRIM" | "SELL"

const STATUS_RANK = {
  DEEP_BUY: 0,
  BUY_ZONE: 1,
  WATCH: 2,
  AT_OR_ABOVE_FAIR: 3,
  TRIM: 4,
  SELL: 5,
} as const satisfies Record<Exclude<LadderStatus, "NO_ANCHORS">, number>

const ALERT_STATUSES: readonly string[] = ["DEEP_BUY", "BUY_ZONE", "TRIM", "SELL"]

/** Parses a stored status string (reusing plan 05's `LADDER_STATUSES`); unknown values become null. */
export function parseLadderStatus(value: unknown): LadderStatus | null {
  return typeof value === "string" && (LADDER_STATUSES as readonly string[]).includes(value) ? (value as LadderStatus) : null
}

export function isAlertStatus(value: string): value is AlertStatus {
  return ALERT_STATUSES.includes(value)
}

/** DEEP_BUY = 0 … SELL = 5; NO_ANCHORS has no rank. */
export function statusRank(status: LadderStatus): number | null {
  return status === "NO_ANCHORS" ? null : STATUS_RANK[status]
}

/**
 * Directional alert rule: push only when moving *down* into DEEP_BUY/BUY_ZONE or *up* into TRIM/SELL.
 * A null previous status seeds silently.
 */
export function shouldAlert(previous: LadderStatus | null, next: LadderStatus): boolean {
  if (previous === null || previous === next) return false
  const previousRank = statusRank(previous)
  const nextRank = statusRank(next)
  if (previousRank === null || nextRank === null) return false
  if ((next === "DEEP_BUY" || next === "BUY_ZONE") && nextRank < previousRank) return true
  if ((next === "TRIM" || next === "SELL") && nextRank > previousRank) return true
  return false
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `npx vitest run test/domain/shouldAlert.test.ts && npm run typecheck`
Expected: PASS (`Tests  18 passed (18)`), and `tsc` exits 0.

- [x] **Step 5: Commit**

```bash
git add server/src/domain/ladder.ts server/test/domain/shouldAlert.test.ts
git commit -m "feat(server): add directional shouldAlert rule driven by shared vectors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Trading date helpers

**Files:**
- Create: `server/src/domain/tradingDate.ts` (re-exports plan 04's `etDateString` as `easternDate`, and adds `isWeekend`)
- Test: `server/test/domain/tradingDate.test.ts` (pins the DST behavior this plan relies on)

- [x] **Step 1: Write the failing test**

Create `server/test/domain/tradingDate.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { easternDate, isWeekend } from "../../src/domain/tradingDate.js"

describe("easternDate", () => {
  it.each([
    { instant: "2026-11-20T22:00:00.000Z", expected: "2026-11-20", note: "Fri 5pm EST, the cron time" },
    { instant: "2026-07-10T22:00:00.000Z", expected: "2026-07-10", note: "Fri 6pm EDT" },
    { instant: "2026-11-21T04:30:00.000Z", expected: "2026-11-20", note: "Fri 11:30pm EST" },
    { instant: "2026-03-08T04:30:00.000Z", expected: "2026-03-07", note: "Sat 11:30pm EST, before DST starts" },
    { instant: "2026-03-08T07:30:00.000Z", expected: "2026-03-08", note: "Sun 3:30am EDT, after DST starts" },
    { instant: "2026-11-01T03:59:00.000Z", expected: "2026-10-31", note: "Sat 11:59pm EDT, before DST ends" },
    { instant: "2026-11-01T06:30:00.000Z", expected: "2026-11-01", note: "Sun 1:30am EST, after DST ends" },
  ])("$instant is $expected in New York ($note)", ({ instant, expected }) => {
    expect(easternDate(new Date(instant))).toBe(expected)
  })
})

describe("isWeekend", () => {
  it.each([
    { date: "2026-11-20", weekend: false },
    { date: "2026-11-21", weekend: true },
    { date: "2026-11-22", weekend: true },
    { date: "2026-11-23", weekend: false },
    { date: "2026-11-26", weekend: false }, // Thanksgiving is a weekday; DailyCloseResolver detects holidays
  ])("$date weekend: $weekend", ({ date, weekend }) => {
    expect(isWeekend(date)).toBe(weekend)
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/domain/tradingDate.test.ts`
Expected: FAIL with `Failed to load url ../../src/domain/tradingDate.js … Does the file exist?`

- [x] **Step 3: Implement**

Create `server/src/domain/tradingDate.ts`:
```ts
/** The America/New_York calendar date ("YYYY-MM-DD") of an instant. Plan 04's calendar already computes it. */
export { etDateString as easternDate } from "./marketCalendar.js"

/** True for Saturday and Sunday. US market holidays are detected separately (DailyCloseResolver's SPY check). */
export function isWeekend(tradingDate: string): boolean {
  const weekday = new Date(`${tradingDate}T12:00:00.000Z`).getUTCDay()
  return weekday === 0 || weekday === 6
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `npx vitest run test/domain/tradingDate.test.ts && npm run typecheck`
Expected: PASS (`Tests  12 passed (12)`).

- [x] **Step 5: Commit**

```bash
git add server/src/domain/tradingDate.ts server/test/domain/tradingDate.test.ts
git commit -m "feat(server): add New York trading-date helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Migration `004_alerts.sql`

**Files:**
- Create: `server/migrations/004_alerts.sql`
- Test: `server/test/db/migration004.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/db/migration004.test.ts`:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { Sql } from "../../src/db/sql.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

describe("004_alerts.sql", () => {
  let created: TestDb
  let sql: Sql

  beforeEach(async () => {
    created = await createTestDb()
    sql = created.sql
    await sql`INSERT INTO users (id, anonymous_id) VALUES ('user-1', 'anon-1')`
  })

  afterEach(async () => {
    await created.close()
  })

  it("creates the alert tables", async () => {
    const rows = await sql`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('device_tokens', 'alert_events', 'alert_job_runs')
      ORDER BY table_name`
    expect(rows.map((row) => row.table_name)).toEqual(["alert_events", "alert_job_runs", "device_tokens"])
  })

  it("only accepts sandbox or production device tokens", async () => {
    await expect(sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'development')`).rejects.toThrow()
    await sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'sandbox')`
    expect(await sql`SELECT bundle_id FROM device_tokens WHERE token = 't1'`).toEqual([{ bundle_id: "com.chenkai.wait" }])
  })

  it("keeps one event per user, symbol, trading day and status", async () => {
    const insert = (id: string) => sql`
      INSERT INTO alert_events (id, user_id, symbol, trading_date, status, price)
      VALUES (${id}, 'user-1', 'AAPL', '2026-11-20', 'BUY_ZONE', 172.1)
      ON CONFLICT (user_id, symbol, trading_date, status) DO NOTHING
      RETURNING id`
    expect(await insert("e1")).toEqual([{ id: "e1" }])
    expect(await insert("e2")).toEqual([])
  })

  it("cascades device tokens and events when the user is deleted", async () => {
    await sql`INSERT INTO device_tokens (token, user_id, environment) VALUES ('t1', 'user-1', 'sandbox')`
    await sql`INSERT INTO alert_events (id, user_id, symbol, trading_date, status, price) VALUES ('e1', 'user-1', 'AAPL', '2026-11-20', 'BUY_ZONE', 172.1)`
    await sql`DELETE FROM users WHERE id = 'user-1'`
    const counts = await sql`SELECT (SELECT count(*)::int FROM device_tokens) AS devices, (SELECT count(*)::int FROM alert_events) AS events`
    expect(counts).toEqual([{ devices: 0, events: 0 }])
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/db/migration004.test.ts`
Expected: FAIL with `relation "device_tokens" does not exist`, or an empty table list.

- [x] **Step 3: Write the migration**

Create `server/migrations/004_alerts.sql`. It is copied verbatim from overview §8.3:
```sql
-- 004_alerts.sql (plan 06): APNs device tokens, alert events, daily job runs
CREATE TABLE IF NOT EXISTS device_tokens (
  token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox','production')), bundle_id TEXT NOT NULL DEFAULT 'com.chenkai.wait',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_success_at TIMESTAMPTZ);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE TABLE IF NOT EXISTS alert_events (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, symbol TEXT NOT NULL,
  trading_date DATE NOT NULL, status TEXT NOT NULL, previous_status TEXT, price NUMERIC(18,6) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), sent_at TIMESTAMPTZ, attempts INT NOT NULL DEFAULT 0,
  UNIQUE (user_id, symbol, trading_date, status));
CREATE TABLE IF NOT EXISTS alert_job_runs (
  trading_date DATE PRIMARY KEY, status TEXT NOT NULL,      -- running | completed | holiday
  started_at TIMESTAMPTZ NOT NULL, finished_at TIMESTAMPTZ, stats JSONB NOT NULL DEFAULT '{}');
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/db/migration004.test.ts && npm test`
Expected: PASS (`Tests  4 passed (4)`), and the full suite stays green.

- [x] **Step 5: Commit**

```bash
git add server/migrations/004_alerts.sql server/test/db/migration004.test.ts
git commit -m "feat(server): add 004_alerts migration

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 2: Repositories

### Task 5: `DeviceTokenRepository` (interface, Neon, Mock)

**Files:**
- Create: `server/src/db/DeviceTokenRepository.ts`
- Create: `server/src/db/NeonDeviceTokenRepository.ts`
- Create: `server/src/db/MockDeviceTokenRepository.ts`
- Create: `server/test/support/alertFixtures.ts`
- Test: `server/test/db/DeviceTokenRepository.test.ts`

- [x] **Step 1: Write the fixture helpers**

Create `server/test/support/alertFixtures.ts`:
```ts
import type { Sql } from "../../src/db/sql.js"

export type ItemFixture = {
  userId: string
  symbol: string
  buyLow?: string
  buyHigh?: string
  fair?: string
  trim?: string
  sell?: string
  lastStatus?: string
  lastEvaluatedPrice?: string
  deleted?: boolean
  version?: number
}

export async function insertUser(sql: Sql, id: string): Promise<void> {
  await sql`INSERT INTO users (id, anonymous_id) VALUES (${id}, ${`anon-${id}`}) ON CONFLICT (id) DO NOTHING`
}

export async function insertItem(sql: Sql, item: ItemFixture): Promise<void> {
  await insertUser(sql, item.userId)
  await sql`
    INSERT INTO watchlist_items (user_id, symbol, name, buy_low, buy_high, fair, "trim", sell,
      client_updated_at, version, deleted_at, last_status, last_evaluated_price)
    VALUES (${item.userId}, ${item.symbol}, ${item.symbol},
      ${item.buyLow ?? null}::numeric, ${item.buyHigh ?? null}::numeric, ${item.fair ?? null}::numeric,
      ${item.trim ?? null}::numeric, ${item.sell ?? null}::numeric,
      '2026-11-01T00:00:00.000Z'::timestamptz, ${item.version ?? 1},
      ${item.deleted === true ? "2026-11-02T00:00:00.000Z" : null}::timestamptz,
      ${item.lastStatus ?? null}, ${item.lastEvaluatedPrice ?? null}::numeric)`
}
```

- [x] **Step 2: Write the failing contract test**

Create `server/test/db/DeviceTokenRepository.test.ts`. The same suite runs against the Neon implementation (on PGlite) and against the Mock:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { DeviceTokenRepository } from "../../src/db/DeviceTokenRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { NeonDeviceTokenRepository } from "../../src/db/NeonDeviceTokenRepository.js"
import { insertUser } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"

type Harness = { repo: DeviceTokenRepository; close: () => Promise<void> }

const harnesses: Array<[string, () => Promise<Harness>]> = [
  [
    "NeonDeviceTokenRepository (PGlite)",
    async () => {
      const created = await createTestDb()
      for (const id of ["user-1", "user-2"]) await insertUser(created.sql, id)
      return { repo: new NeonDeviceTokenRepository(created.sql), close: () => created.close() }
    },
  ],
  ["MockDeviceTokenRepository", async () => ({ repo: new MockDeviceTokenRepository(), close: async () => {} })],
]

const TOKEN_A = "a".repeat(64)
const TOKEN_B = "b".repeat(64)
const T0 = new Date("2026-11-20T10:00:00.000Z")
const T1 = new Date("2026-11-20T11:00:00.000Z")
const BUNDLE = "com.chenkai.wait"

describe.each(harnesses)("%s", (_name, makeHarness) => {
  let harness: Harness

  beforeEach(async () => {
    harness = await makeHarness()
  })

  afterEach(async () => {
    await harness.close()
  })

  it("upserts and lists a user's device", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([
      { token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE, createdAt: T0, updatedAt: T0, lastSuccessAt: null },
    ])
  })

  it("moves a re-registered token to the new user and environment", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-2", environment: "production", bundleId: BUNDLE }, T1)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
    expect(await harness.repo.listByUsers(["user-2"])).toEqual([
      { token: TOKEN_A, userId: "user-2", environment: "production", bundleId: BUNDLE, createdAt: T0, updatedAt: T1, lastSuccessAt: null },
    ])
  })

  it("lists devices for several users ordered by user, then creation", async () => {
    await harness.repo.upsert({ token: TOKEN_B, userId: "user-2", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T1)
    const devices = await harness.repo.listByUsers(["user-2", "user-1"])
    expect(devices.map((device) => [device.userId, device.token])).toEqual([
      ["user-1", TOKEN_A],
      ["user-2", TOKEN_B],
    ])
  })

  it("returns nothing for an empty user list", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    expect(await harness.repo.listByUsers([])).toEqual([])
  })

  it("only removes a token for its owner", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.removeForUser(TOKEN_A, "user-2")
    expect(await harness.repo.listByUsers(["user-1"])).toHaveLength(1)
    await harness.repo.removeForUser(TOKEN_A, "user-1")
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
  })

  it("prunes a token regardless of owner", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.prune(TOKEN_A)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
  })

  it("records the last successful delivery", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.markSuccess(TOKEN_A, T1)
    const [device] = await harness.repo.listByUsers(["user-1"])
    expect(device?.lastSuccessAt).toEqual(T1)
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/db/DeviceTokenRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/MockDeviceTokenRepository.js`.

- [x] **Step 4: Write the interface**

Create `server/src/db/DeviceTokenRepository.ts`:
```ts
export type ApnsEnvironment = "sandbox" | "production"

export type DeviceToken = {
  token: string
  userId: string
  environment: ApnsEnvironment
  bundleId: string
  createdAt: Date
  updatedAt: Date
  lastSuccessAt: Date | null
}

export type DeviceRegistration = { token: string; userId: string; environment: ApnsEnvironment; bundleId: string }

export interface DeviceTokenRepository {
  /** Insert or move the token to `userId` (a token belongs to exactly one user). */
  upsert(registration: DeviceRegistration, now: Date): Promise<void>
  /** DELETE /api/devices/:token: removes the token only if `userId` owns it. */
  removeForUser(token: string, userId: string): Promise<void>
  /** Devices for the given users, ordered by user id, then creation time, then token. */
  listByUsers(userIds: string[]): Promise<DeviceToken[]>
  /** APNs said the token is dead. */
  prune(token: string): Promise<void>
  markSuccess(token: string, now: Date): Promise<void>
}
```

- [x] **Step 5: Write the Neon implementation**

Create `server/src/db/NeonDeviceTokenRepository.ts`:
```ts
import { asDate, asNullableDate } from "../lib/time.js"
import type { ApnsEnvironment, DeviceRegistration, DeviceToken, DeviceTokenRepository } from "./DeviceTokenRepository.js"
import type { Sql } from "./sql.js"

type DeviceTokenRow = {
  token: string
  user_id: string
  environment: string
  bundle_id: string
  created_at: unknown
  updated_at: unknown
  last_success_at: unknown
}

function toEnvironment(value: string): ApnsEnvironment {
  if (value === "sandbox" || value === "production") return value
  throw new Error(`Unknown APNs environment in device_tokens: ${value}`)
}

function mapRow(row: DeviceTokenRow): DeviceToken {
  return {
    token: row.token,
    userId: row.user_id,
    environment: toEnvironment(row.environment),
    bundleId: row.bundle_id,
    createdAt: asDate(row.created_at),
    updatedAt: asDate(row.updated_at),
    lastSuccessAt: asNullableDate(row.last_success_at),
  }
}

export class NeonDeviceTokenRepository implements DeviceTokenRepository {
  private readonly sql: Sql

  constructor(sql: Sql) {
    this.sql = sql
  }

  async upsert(registration: DeviceRegistration, now: Date): Promise<void> {
    const at = now.toISOString()
    await this.sql`
      INSERT INTO device_tokens (token, user_id, environment, bundle_id, created_at, updated_at)
      VALUES (${registration.token}, ${registration.userId}, ${registration.environment}, ${registration.bundleId},
        ${at}::timestamptz, ${at}::timestamptz)
      ON CONFLICT (token) DO UPDATE SET
        user_id = EXCLUDED.user_id, environment = EXCLUDED.environment,
        bundle_id = EXCLUDED.bundle_id, updated_at = EXCLUDED.updated_at`
  }

  async removeForUser(token: string, userId: string): Promise<void> {
    await this.sql`DELETE FROM device_tokens WHERE token = ${token} AND user_id = ${userId}`
  }

  async listByUsers(userIds: string[]): Promise<DeviceToken[]> {
    if (userIds.length === 0) return []
    const rows = await this.sql`
      SELECT token, user_id, environment, bundle_id, created_at, updated_at, last_success_at
      FROM device_tokens
      WHERE user_id IN (SELECT jsonb_array_elements_text(${JSON.stringify(userIds)}::jsonb))
      ORDER BY user_id, created_at, token`
    return rows.map((row) => mapRow(row as DeviceTokenRow))
  }

  async prune(token: string): Promise<void> {
    await this.sql`DELETE FROM device_tokens WHERE token = ${token}`
  }

  async markSuccess(token: string, now: Date): Promise<void> {
    await this.sql`UPDATE device_tokens SET last_success_at = ${now.toISOString()}::timestamptz WHERE token = ${token}`
  }
}
```

- [x] **Step 6: Write the Mock implementation**

Create `server/src/db/MockDeviceTokenRepository.ts`:
```ts
import type { DeviceRegistration, DeviceToken, DeviceTokenRepository } from "./DeviceTokenRepository.js"

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

export class MockDeviceTokenRepository implements DeviceTokenRepository {
  private readonly devices = new Map<string, DeviceToken>()

  seed(devices: DeviceToken[]): void {
    for (const device of devices) this.devices.set(device.token, { ...device })
  }

  all(): DeviceToken[] {
    return [...this.devices.values()].map((device) => ({ ...device }))
  }

  clear(): void {
    this.devices.clear()
  }

  async upsert(registration: DeviceRegistration, now: Date): Promise<void> {
    const existing = this.devices.get(registration.token)
    this.devices.set(registration.token, {
      ...registration,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastSuccessAt: existing?.lastSuccessAt ?? null,
    })
  }

  async removeForUser(token: string, userId: string): Promise<void> {
    if (this.devices.get(token)?.userId === userId) this.devices.delete(token)
  }

  async listByUsers(userIds: string[]): Promise<DeviceToken[]> {
    const wanted = new Set(userIds)
    return this.all()
      .filter((device) => wanted.has(device.userId))
      .sort((a, b) => compare(a.userId, b.userId) || a.createdAt.getTime() - b.createdAt.getTime() || compare(a.token, b.token))
  }

  async prune(token: string): Promise<void> {
    this.devices.delete(token)
  }

  async markSuccess(token: string, now: Date): Promise<void> {
    const device = this.devices.get(token)
    if (device) this.devices.set(token, { ...device, lastSuccessAt: now })
  }
}
```

- [x] **Step 7: Run the tests to verify they pass**

Run: `npx vitest run test/db/DeviceTokenRepository.test.ts && npm run typecheck`
Expected: PASS (`Tests  14 passed (14)`: 7 tests × 2 implementations).

- [x] **Step 8: Commit**

```bash
git add server/src/db/DeviceTokenRepository.ts server/src/db/NeonDeviceTokenRepository.ts server/src/db/MockDeviceTokenRepository.ts \
  server/test/support/alertFixtures.ts server/test/db/DeviceTokenRepository.test.ts
git commit -m "feat(server): add device token repository (Neon + Mock)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `AlertRepository` (job items, events, runs)

**Files:**
- Create: `server/src/db/AlertRepository.ts`
- Create: `server/src/db/NeonAlertRepository.ts`
- Create: `server/src/db/MockAlertRepository.ts`
- Modify: `server/test/support/alertFixtures.ts` (add `toEvaluableItem`)
- Test: `server/test/db/AlertRepository.test.ts`

- [x] **Step 1: Add the fixture mapper**

Append to `server/test/support/alertFixtures.ts`:
```ts
import type { EvaluableItem } from "../../src/db/AlertRepository.js"
import { parseLadderStatus } from "../../src/domain/ladder.js"

export function toEvaluableItem(item: ItemFixture): EvaluableItem & { deleted: boolean } {
  return {
    userId: item.userId,
    symbol: item.symbol,
    ladder: {
      buyLow: item.buyLow ?? null,
      buyHigh: item.buyHigh ?? null,
      fair: item.fair ?? null,
      trim: item.trim ?? null,
      sell: item.sell ?? null,
    },
    lastStatus: parseLadderStatus(item.lastStatus ?? null),
    lastEvaluatedPrice: item.lastEvaluatedPrice ?? null,
    deleted: item.deleted === true,
  }
}
```
Move the two new `import` lines to the top of the file, next to the existing `import type { Sql }`.

- [x] **Step 2: Write the failing contract test**

Create `server/test/db/AlertRepository.test.ts`:
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { AlertRepository, NewAlertEvent } from "../../src/db/AlertRepository.js"
import { MockAlertRepository } from "../../src/db/MockAlertRepository.js"
import { NeonAlertRepository } from "../../src/db/NeonAlertRepository.js"
import type { Sql } from "../../src/db/sql.js"
import { insertItem, toEvaluableItem, type ItemFixture } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"

type Status = { lastStatus: string | null; lastEvaluatedPrice: string | null }
type Harness = {
  repo: AlertRepository
  seed: (items: ItemFixture[]) => Promise<void>
  statusOf: (userId: string, symbol: string) => Promise<Status>
  close: () => Promise<void>
}

const harnesses: Array<[string, () => Promise<Harness>]> = [
  [
    "NeonAlertRepository (PGlite)",
    async () => {
      const created = await createTestDb()
      const sql = created.sql
      return {
        repo: new NeonAlertRepository(sql),
        seed: async (items) => {
          for (const item of items) await insertItem(sql, item)
        },
        statusOf: async (userId, symbol) => {
          const [row] = await sql`
            SELECT last_status, trim_scale(last_evaluated_price)::text AS price
            FROM watchlist_items WHERE user_id = ${userId} AND symbol = ${symbol}`
          return { lastStatus: (row?.last_status as string | null) ?? null, lastEvaluatedPrice: (row?.price as string | null) ?? null }
        },
        close: () => created.close(),
      }
    },
  ],
  [
    "MockAlertRepository",
    async () => {
      const repo = new MockAlertRepository()
      return {
        repo,
        seed: async (items) => repo.seedItems(items.map(toEvaluableItem)),
        statusOf: async (userId, symbol) => {
          const item = repo.item(userId, symbol)
          return { lastStatus: item?.lastStatus ?? null, lastEvaluatedPrice: item?.lastEvaluatedPrice ?? null }
        },
        close: async () => {},
      }
    },
  ],
]

const NOW = new Date("2026-11-20T22:00:00.000Z")

function event(overrides: Partial<NewAlertEvent> & Pick<NewAlertEvent, "id">): NewAlertEvent {
  return { userId: "user-1", symbol: "AAPL", tradingDate: "2026-11-20", status: "BUY_ZONE", previousStatus: "WATCH", price: "172.1", ...overrides }
}

const SEED: ItemFixture[] = [
  { userId: "user-1", symbol: "AAPL", buyLow: "150", buyHigh: "175", fair: "210", lastStatus: "WATCH", lastEvaluatedPrice: "180.5" },
  { userId: "user-2", symbol: "AAPL", buyHigh: "160" },
  { userId: "user-1", symbol: "MSFT" },
  { userId: "user-1", symbol: "TSLA", buyHigh: "200", deleted: true },
]

describe.each(harnesses)("%s", (_name, makeHarness) => {
  let harness: Harness

  beforeEach(async () => {
    harness = await makeHarness()
    await harness.seed(SEED)
  })

  afterEach(async () => {
    await harness.close()
  })

  it("lists live items with at least one anchor, ordered by symbol then user", async () => {
    expect(await harness.repo.listEvaluableItems()).toEqual([
      {
        userId: "user-1",
        symbol: "AAPL",
        ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
        lastStatus: "WATCH",
        lastEvaluatedPrice: "180.5",
      },
      {
        userId: "user-2",
        symbol: "AAPL",
        ladder: { buyLow: null, buyHigh: "160", fair: null, trim: null, sell: null },
        lastStatus: null,
        lastEvaluatedPrice: null,
      },
    ])
  })

  it("inserts events once per user, symbol, day and status", async () => {
    expect(await harness.repo.insertEvents([event({ id: "e1" })], NOW)).toEqual(["e1"])
    expect(await harness.repo.insertEvents([event({ id: "e2" }), event({ id: "e3", userId: "user-2" })], NOW)).toEqual(["e3"])
    expect(await harness.repo.insertEvents([], NOW)).toEqual([])
  })

  it("applies evaluated statuses and prices", async () => {
    await harness.repo.applyEvaluations(
      [
        { userId: "user-1", symbol: "AAPL", previousStatus: "WATCH", status: "BUY_ZONE", price: "172.1" },
        { userId: "user-2", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "158" },
      ],
      NOW,
    )
    expect(await harness.statusOf("user-1", "AAPL")).toEqual({ lastStatus: "BUY_ZONE", lastEvaluatedPrice: "172.1" })
    expect(await harness.statusOf("user-2", "AAPL")).toEqual({ lastStatus: "BUY_ZONE", lastEvaluatedPrice: "158" })
    await harness.repo.applyEvaluations([], NOW)
  })

  it("leaves a row alone when its status changed since the job read it (e.g. sync reset it to NULL)", async () => {
    await harness.repo.applyEvaluations([{ userId: "user-1", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "172.1" }], NOW)
    expect(await harness.statusOf("user-1", "AAPL")).toEqual({ lastStatus: "WATCH", lastEvaluatedPrice: "180.5" })
  })

  it("lists only unsent events of the day under the attempt limit, with the item's ladder", async () => {
    await harness.repo.insertEvents([event({ id: "e1" })], NOW)
    await harness.repo.insertEvents([event({ id: "e2", userId: "user-2" })], NOW)
    await harness.repo.insertEvents([event({ id: "e3", tradingDate: "2026-11-19" })], NOW)
    await harness.repo.insertEvents([event({ id: "e4", status: "DEEP_BUY", previousStatus: "BUY_ZONE" })], NOW)
    await harness.repo.markSent("e2", NOW)
    await harness.repo.incrementAttempts("e1")
    await harness.repo.incrementAttempts("e1")
    for (let attempt = 0; attempt < 3; attempt += 1) await harness.repo.incrementAttempts("e4")

    expect(await harness.repo.listPendingEvents("2026-11-20", 3)).toEqual([
      {
        id: "e1",
        userId: "user-1",
        symbol: "AAPL",
        tradingDate: "2026-11-20",
        status: "BUY_ZONE",
        previousStatus: "WATCH",
        price: "172.1",
        attempts: 2,
        ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
      },
    ])
  })

  it("claims a day once, refuses a fresh running claim, and takes over a stale one", async () => {
    const nineMinutesLater = new Date(NOW.getTime() + 9 * 60_000)
    const elevenMinutesLater = new Date(NOW.getTime() + 11 * 60_000)
    expect(await harness.repo.beginRun("2026-11-20", NOW)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: true })
    expect(await harness.repo.beginRun("2026-11-20", nineMinutesLater)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: false })
    expect(await harness.repo.beginRun("2026-11-20", elevenMinutesLater)).toEqual({ tradingDate: "2026-11-20", status: "running", claimed: true })
    await harness.repo.finishRun("2026-11-20", "completed", { evaluated: 2 }, elevenMinutesLater)
    expect(await harness.repo.beginRun("2026-11-20", new Date(NOW.getTime() + 60 * 60_000))).toEqual({
      tradingDate: "2026-11-20",
      status: "completed",
      claimed: false,
    })
  })
})

describe("NeonAlertRepository (PGlite only)", () => {
  it("does not bump the sync version or server_updated_at when applying evaluations", async () => {
    const created = await createTestDb()
    const sql: Sql = created.sql
    await insertItem(sql, { userId: "user-1", symbol: "AAPL", buyHigh: "175", version: 7 })
    const [before] = await sql`SELECT version, server_updated_at FROM watchlist_items WHERE symbol = 'AAPL'`
    await new NeonAlertRepository(sql).applyEvaluations([{ userId: "user-1", symbol: "AAPL", previousStatus: null, status: "BUY_ZONE", price: "170" }], NOW)
    const [after] = await sql`SELECT version, server_updated_at, last_status_at FROM watchlist_items WHERE symbol = 'AAPL'`
    expect(String(after?.version)).toBe("7")
    expect(after?.server_updated_at).toEqual(before?.server_updated_at)
    expect(after?.last_status_at).toEqual(NOW)
    await created.close()
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/db/AlertRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/AlertRepository.js`.

- [x] **Step 4: Write the interface**

Create `server/src/db/AlertRepository.ts`:
```ts
import type { LadderInput, LadderStatus } from "../domain/ladder.js"

/** A live watchlist item with at least one anchor, plus the server-owned evaluation columns. */
export type EvaluableItem = {
  userId: string
  symbol: string
  ladder: LadderInput
  lastStatus: LadderStatus | null
  lastEvaluatedPrice: string | null
}

/** `previousStatus` is the `last_status` the job read; the update applies only if the row still has it. */
export type EvaluationUpdate = { userId: string; symbol: string; previousStatus: LadderStatus | null; status: LadderStatus; price: string }

export type NewAlertEvent = {
  id: string
  userId: string
  symbol: string
  tradingDate: string
  status: LadderStatus
  previousStatus: LadderStatus | null
  price: string
}

export type PendingAlertEvent = NewAlertEvent & { attempts: number; ladder: LadderInput }

export type JobRunStatus = "running" | "completed" | "holiday"
/** `claimed` = this caller owns the day's run (new row, or a stale `running` row taken over). */
export type JobRun = { tradingDate: string; status: JobRunStatus; claimed: boolean }
export type JobStats = Record<string, number>

/** A `running` row older than this is treated as a crashed run and may be taken over. */
export const RUN_STALE_AFTER_MS = 10 * 60 * 1000

export interface AlertRepository {
  listEvaluableItems(): Promise<EvaluableItem[]>
  /** Inserts with ON CONFLICT DO NOTHING; returns the ids that were actually inserted. */
  insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]>
  /** Sets last_status / last_status_at / last_evaluated_price where last_status is still `previousStatus`. Never touches version. */
  applyEvaluations(updates: EvaluationUpdate[], now: Date): Promise<void>
  listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]>
  markSent(eventId: string, now: Date): Promise<void>
  incrementAttempts(eventId: string): Promise<void>
  /** Atomically claims the day: inserts the run row, or takes over a `running` row older than RUN_STALE_AFTER_MS. */
  beginRun(tradingDate: string, now: Date): Promise<JobRun>
  finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats, now: Date): Promise<void>
}
```

- [x] **Step 5: Write the Neon implementation**

Create `server/src/db/NeonAlertRepository.ts`:
```ts
import { parseLadderStatus, type LadderInput, type LadderStatus } from "../domain/ladder.js"
import {
  RUN_STALE_AFTER_MS,
  type AlertRepository,
  type EvaluableItem,
  type EvaluationUpdate,
  type JobRun,
  type JobRunStatus,
  type JobStats,
  type NewAlertEvent,
  type PendingAlertEvent,
} from "./AlertRepository.js"
import type { Sql } from "./sql.js"

type LadderColumns = { buy_low: string | null; buy_high: string | null; fair: string | null; trim_value: string | null; sell: string | null }
type EvaluableRow = LadderColumns & { user_id: string; symbol: string; last_status: string | null; last_evaluated_price: string | null }
type PendingRow = LadderColumns & {
  id: string
  user_id: string
  symbol: string
  trading_date: string
  status: string
  previous_status: string | null
  price: string
  attempts: number
}
type JobRunRow = { status: string; claimed: boolean }

function toLadder(row: LadderColumns): LadderInput {
  return { buyLow: row.buy_low, buyHigh: row.buy_high, fair: row.fair, trim: row.trim_value, sell: row.sell }
}

function requireStatus(value: unknown): LadderStatus {
  const status = parseLadderStatus(value)
  if (status === null) throw new Error(`Unknown ladder status in alert_events: ${String(value)}`)
  return status
}

function toJobRunStatus(value: string): JobRunStatus {
  if (value === "running" || value === "completed" || value === "holiday") return value
  throw new Error(`Unknown alert_job_runs status: ${value}`)
}

export class NeonAlertRepository implements AlertRepository {
  private readonly sql: Sql

  constructor(sql: Sql) {
    this.sql = sql
  }

  async listEvaluableItems(): Promise<EvaluableItem[]> {
    const rows = await this.sql`
      SELECT user_id, symbol,
        trim_scale(buy_low)::text AS buy_low, trim_scale(buy_high)::text AS buy_high, trim_scale(fair)::text AS fair,
        trim_scale("trim")::text AS trim_value, trim_scale(sell)::text AS sell,
        last_status, trim_scale(last_evaluated_price)::text AS last_evaluated_price
      FROM watchlist_items
      WHERE deleted_at IS NULL
        AND (buy_low IS NOT NULL OR buy_high IS NOT NULL OR fair IS NOT NULL OR "trim" IS NOT NULL OR sell IS NOT NULL)
      ORDER BY symbol, user_id`
    return rows.map((raw) => {
      const row = raw as EvaluableRow
      return {
        userId: row.user_id,
        symbol: row.symbol,
        ladder: toLadder(row),
        lastStatus: parseLadderStatus(row.last_status),
        lastEvaluatedPrice: row.last_evaluated_price,
      }
    })
  }

  async insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]> {
    if (events.length === 0) return []
    const records = events.map((event) => ({
      id: event.id,
      user_id: event.userId,
      symbol: event.symbol,
      trading_date: event.tradingDate,
      status: event.status,
      previous_status: event.previousStatus,
      price: event.price,
    }))
    const rows = await this.sql`
      INSERT INTO alert_events (id, user_id, symbol, trading_date, status, previous_status, price, created_at)
      SELECT e.id, e.user_id, e.symbol, e.trading_date::date, e.status, e.previous_status, e.price::numeric, ${now.toISOString()}::timestamptz
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb)
        AS e(id text, user_id text, symbol text, trading_date text, status text, previous_status text, price text)
      ON CONFLICT (user_id, symbol, trading_date, status) DO NOTHING
      RETURNING id`
    return rows.map((row) => String(row.id))
  }

  async applyEvaluations(updates: EvaluationUpdate[], now: Date): Promise<void> {
    if (updates.length === 0) return
    const records = updates.map((update) => ({
      user_id: update.userId,
      symbol: update.symbol,
      prev_status: update.previousStatus,
      status: update.status,
      price: update.price,
    }))
    await this.sql`
      UPDATE watchlist_items AS w
      SET last_status = u.status, last_status_at = ${now.toISOString()}::timestamptz, last_evaluated_price = u.price::numeric
      FROM jsonb_to_recordset(${JSON.stringify(records)}::jsonb) AS u(user_id text, symbol text, prev_status text, status text, price text)
      WHERE w.user_id = u.user_id AND w.symbol = u.symbol AND w.last_status IS NOT DISTINCT FROM u.prev_status`
  }

  async listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]> {
    const rows = await this.sql`
      SELECT e.id, e.user_id, e.symbol, to_char(e.trading_date, 'YYYY-MM-DD') AS trading_date, e.status, e.previous_status,
        trim_scale(e.price)::text AS price, e.attempts,
        trim_scale(w.buy_low)::text AS buy_low, trim_scale(w.buy_high)::text AS buy_high, trim_scale(w.fair)::text AS fair,
        trim_scale(w."trim")::text AS trim_value, trim_scale(w.sell)::text AS sell
      FROM alert_events e
      LEFT JOIN watchlist_items w ON w.user_id = e.user_id AND w.symbol = e.symbol
      WHERE e.sent_at IS NULL AND e.trading_date = ${tradingDate}::date AND e.attempts < ${maxAttempts}
      ORDER BY e.created_at, e.id`
    return rows.map((raw) => {
      const row = raw as PendingRow
      return {
        id: row.id,
        userId: row.user_id,
        symbol: row.symbol,
        tradingDate: row.trading_date,
        status: requireStatus(row.status),
        previousStatus: parseLadderStatus(row.previous_status),
        price: row.price,
        attempts: Number(row.attempts),
        ladder: toLadder(row),
      }
    })
  }

  async markSent(eventId: string, now: Date): Promise<void> {
    await this.sql`UPDATE alert_events SET sent_at = ${now.toISOString()}::timestamptz WHERE id = ${eventId}`
  }

  async incrementAttempts(eventId: string): Promise<void> {
    await this.sql`UPDATE alert_events SET attempts = attempts + 1 WHERE id = ${eventId}`
  }

  async beginRun(tradingDate: string, now: Date): Promise<JobRun> {
    const staleSeconds = RUN_STALE_AFTER_MS / 1000
    const rows = await this.sql`
      WITH claimed AS (
        INSERT INTO alert_job_runs (trading_date, status, started_at)
        VALUES (${tradingDate}::date, 'running', ${now.toISOString()}::timestamptz)
        ON CONFLICT (trading_date) DO UPDATE SET started_at = EXCLUDED.started_at
        WHERE alert_job_runs.status = 'running'
          AND alert_job_runs.started_at <= EXCLUDED.started_at - make_interval(secs => ${staleSeconds})
        RETURNING status
      )
      SELECT status, true AS claimed FROM claimed
      UNION ALL
      SELECT status, false AS claimed FROM alert_job_runs
      WHERE trading_date = ${tradingDate}::date AND NOT EXISTS (SELECT 1 FROM claimed)`
    const row = rows[0] as JobRunRow | undefined
    if (row !== undefined) return { tradingDate, status: toJobRunStatus(row.status), claimed: row.claimed === true }
    // A truly concurrent delivery: the other insert committed after this statement's snapshot, so the UNION saw
    // neither row. Read again (new snapshot) and report it as someone else's run.
    const [existing] = await this.sql`SELECT status FROM alert_job_runs WHERE trading_date = ${tradingDate}::date`
    if (existing === undefined) throw new Error(`alert_job_runs row for ${tradingDate} was neither claimed nor found`)
    return { tradingDate, status: toJobRunStatus(String(existing.status)), claimed: false }
  }

  async finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats, now: Date): Promise<void> {
    await this.sql`
      UPDATE alert_job_runs
      SET status = ${status}, finished_at = ${now.toISOString()}::timestamptz, stats = ${JSON.stringify(stats)}::jsonb
      WHERE trading_date = ${tradingDate}::date`
  }
}
```

- [x] **Step 6: Write the Mock implementation**

Create `server/src/db/MockAlertRepository.ts`:
```ts
import type { LadderInput } from "../domain/ladder.js"
import {
  RUN_STALE_AFTER_MS,
  type AlertRepository,
  type EvaluableItem,
  type EvaluationUpdate,
  type JobRun,
  type JobRunStatus,
  type JobStats,
  type NewAlertEvent,
  type PendingAlertEvent,
} from "./AlertRepository.js"

type StoredItem = EvaluableItem & { deleted: boolean }
export type StoredAlertEvent = NewAlertEvent & { createdAt: Date; sentAt: Date | null; attempts: number }

const EMPTY_LADDER: LadderInput = { buyLow: null, buyHigh: null, fair: null, trim: null, sell: null }

function key(userId: string, symbol: string): string {
  return `${userId}\u0000${symbol}`
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

function hasAnchor(ladder: LadderInput): boolean {
  return [ladder.buyLow, ladder.buyHigh, ladder.fair, ladder.trim, ladder.sell].some((value) => value !== null && value !== undefined)
}

export class MockAlertRepository implements AlertRepository {
  private readonly items = new Map<string, StoredItem>()
  private events: StoredAlertEvent[] = []
  private readonly runs = new Map<string, { status: JobRunStatus; startedAt: Date; stats: JobStats }>()

  seedItems(items: Array<EvaluableItem & { deleted?: boolean }>): void {
    for (const item of items) this.items.set(key(item.userId, item.symbol), { ...item, ladder: { ...item.ladder }, deleted: item.deleted ?? false })
  }

  item(userId: string, symbol: string): EvaluableItem | undefined {
    const stored = this.items.get(key(userId, symbol))
    if (stored === undefined) return undefined
    const { deleted: _deleted, ...item } = stored
    return { ...item, ladder: { ...item.ladder } }
  }

  allEvents(): StoredAlertEvent[] {
    return this.events.map((event) => ({ ...event }))
  }

  runStatus(tradingDate: string): JobRunStatus | undefined {
    return this.runs.get(tradingDate)?.status
  }

  clear(): void {
    this.items.clear()
    this.events = []
    this.runs.clear()
  }

  async listEvaluableItems(): Promise<EvaluableItem[]> {
    return [...this.items.values()]
      .filter((item) => !item.deleted && hasAnchor(item.ladder))
      .sort((a, b) => compare(a.symbol, b.symbol) || compare(a.userId, b.userId))
      .map(({ deleted: _deleted, ...item }) => ({ ...item, ladder: { ...item.ladder } }))
  }

  async insertEvents(events: NewAlertEvent[], now: Date): Promise<string[]> {
    const inserted: string[] = []
    for (const event of events) {
      const duplicate = this.events.some(
        (existing) =>
          existing.userId === event.userId &&
          existing.symbol === event.symbol &&
          existing.tradingDate === event.tradingDate &&
          existing.status === event.status,
      )
      if (duplicate) continue
      this.events.push({ ...event, createdAt: now, sentAt: null, attempts: 0 })
      inserted.push(event.id)
    }
    return inserted
  }

  async applyEvaluations(updates: EvaluationUpdate[]): Promise<void> {
    for (const update of updates) {
      const stored = this.items.get(key(update.userId, update.symbol))
      if (stored === undefined || stored.lastStatus !== update.previousStatus) continue
      this.items.set(key(update.userId, update.symbol), { ...stored, lastStatus: update.status, lastEvaluatedPrice: update.price })
    }
  }

  /** Test hook: simulates plan 05's sync resetting `last_status` after an anchor change. */
  resetStatus(userId: string, symbol: string): void {
    const stored = this.items.get(key(userId, symbol))
    if (stored) this.items.set(key(userId, symbol), { ...stored, lastStatus: null })
  }

  async listPendingEvents(tradingDate: string, maxAttempts: number): Promise<PendingAlertEvent[]> {
    return this.events
      .filter((event) => event.sentAt === null && event.tradingDate === tradingDate && event.attempts < maxAttempts)
      .map(({ createdAt: _createdAt, sentAt: _sentAt, ...event }) => ({
        ...event,
        ladder: { ...(this.items.get(key(event.userId, event.symbol))?.ladder ?? EMPTY_LADDER) },
      }))
  }

  async markSent(eventId: string, now: Date): Promise<void> {
    this.events = this.events.map((event) => (event.id === eventId ? { ...event, sentAt: now } : event))
  }

  async incrementAttempts(eventId: string): Promise<void> {
    this.events = this.events.map((event) => (event.id === eventId ? { ...event, attempts: event.attempts + 1 } : event))
  }

  async beginRun(tradingDate: string, now: Date): Promise<JobRun> {
    const existing = this.runs.get(tradingDate)
    const stale = existing?.status === "running" && now.getTime() - existing.startedAt.getTime() >= RUN_STALE_AFTER_MS
    if (existing === undefined || stale) {
      this.runs.set(tradingDate, { status: "running", startedAt: now, stats: {} })
      return { tradingDate, status: "running", claimed: true }
    }
    return { tradingDate, status: existing.status, claimed: false }
  }

  async finishRun(tradingDate: string, status: Exclude<JobRunStatus, "running">, stats: JobStats): Promise<void> {
    const existing = this.runs.get(tradingDate)
    this.runs.set(tradingDate, { status, startedAt: existing?.startedAt ?? new Date(0), stats })
  }
}
```

- [x] **Step 7: Run the tests to verify they pass**

Run: `npx vitest run test/db/AlertRepository.test.ts && npm run typecheck`
Expected: PASS (`Tests  13 passed (13)`: 6 contract tests × 2 implementations, plus 1 PGlite-only test).
If PGlite rejects `trim_scale` (it needs Postgres 13 or later), stop and report the PGlite version. Don't switch to a client-side workaround.

- [x] **Step 8: Commit**

```bash
git add server/src/db/AlertRepository.ts server/src/db/NeonAlertRepository.ts server/src/db/MockAlertRepository.ts \
  server/test/support/alertFixtures.ts server/test/db/AlertRepository.test.ts
git commit -m "feat(server): add alert repository for job items, events and runs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 3: Closing prices (Massive + holiday check + Finnhub fallback)

### Task 7: Massive grouped-daily adapter

**Files:**
- Modify: `server/src/providers/types.ts` (append `DailyClose` and `GroupedDailyProvider`; `ProviderName` already includes `"massive"`)
- Create: `server/src/providers/massive.ts`
- Create: `server/test/support/fixtures/massive/grouped-2026-11-20.json`
- Create: `server/test/support/fixtures/massive/grouped-empty.json`
- Test: `server/test/providers/massive.test.ts`

- [x] **Step 1: Add the fixtures**

Create `server/test/support/fixtures/massive/grouped-2026-11-20.json`. This is the Polygon/Massive grouped-daily response shape; `t` is 2026-11-20T21:00:00Z in milliseconds.
```json
{
  "adjusted": true,
  "queryCount": 3,
  "resultsCount": 3,
  "status": "OK",
  "request_id": "fixture-grouped-1",
  "results": [
    { "T": "AAPL", "v": 51234567, "vw": 171.9, "o": 170.5, "c": 172.1, "h": 173.0, "l": 169.8, "t": 1795208400000, "n": 612345 },
    { "T": "NVDA", "v": 41234567, "vw": 184.2, "o": 181.0, "c": 185, "h": 186.4, "l": 180.2, "t": 1795208400000, "n": 512345 },
    { "T": "BRK.B", "v": 3123456, "vw": 480.1, "o": 479.0, "c": 481.25, "h": 482.0, "l": 478.5, "t": 1795208400000, "n": 45678 }
  ]
}
```
Create `server/test/support/fixtures/massive/grouped-empty.json`:
```json
{ "adjusted": true, "queryCount": 0, "resultsCount": 0, "status": "OK", "request_id": "fixture-grouped-2" }
```

- [x] **Step 2: Write the failing test**

Create `server/test/providers/massive.test.ts`:
```ts
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { createMassiveProvider } from "../../src/providers/massive.js"

const fixture = (name: string): string => readFileSync(new URL(`../support/fixtures/massive/${name}`, import.meta.url), "utf8")

type Call = { url: string; init: RequestInit | undefined }

function fakeFetch(respond: () => Response | Promise<Response>) {
  const calls: Call[] = []
  const impl = async (url: string, init?: RequestInit): Promise<Response> => {
    calls.push({ url, init })
    return respond()
  }
  return { calls, impl }
}

const json = (body: string, status = 200, headers: Record<string, string> = {}) =>
  new Response(body, { status, headers: { "content-type": "application/json", ...headers } })

describe("createMassiveProvider", () => {
  it("requests grouped daily bars with a bearer token and maps closes", async () => {
    const fake = fakeFetch(() => json(fixture("grouped-2026-11-20.json")))
    const provider = createMassiveProvider({ apiKey: "test-key", baseUrl: "https://api.massive.com/", fetchImpl: fake.impl })

    const closes = await provider.getGroupedDaily("2026-11-20")

    expect(fake.calls).toHaveLength(1)
    expect(fake.calls[0]?.url).toBe("https://api.massive.com/v2/aggs/grouped/locale/us/market/stocks/2026-11-20?adjusted=true")
    expect(fake.calls[0]?.url).not.toContain("test-key")
    expect(new Headers(fake.calls[0]?.init?.headers).get("authorization")).toBe("Bearer test-key")
    expect([...closes.keys()]).toEqual(["AAPL", "NVDA", "BRK.B"])
    expect(closes.get("AAPL")).toEqual({ symbol: "AAPL", close: "172.1", at: new Date("2026-11-20T21:00:00.000Z") })
    expect(closes.get("NVDA")?.close).toBe("185")
  })

  it("returns an empty map when the day has no results", async () => {
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json(fixture("grouped-empty.json"))).impl })
    expect((await provider.getGroupedDaily("2026-11-26")).size).toBe(0)
  })

  it("skips malformed rows", async () => {
    const body = JSON.stringify({ results: [{ T: "AAPL", c: 172.1, t: 1795208400000 }, { T: "MSFT", t: 1795208400000 }, { T: "TSLA", c: "30", t: 1795208400000 }] })
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json(body)).impl })
    expect([...(await provider.getGroupedDaily("2026-11-20")).keys()]).toEqual(["AAPL"])
  })

  it("maps 429 to rate_limited with Retry-After", async () => {
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("{}", 429, { "retry-after": "30" })).impl })
    await expect(provider.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ provider: "massive", kind: "rate_limited", retryAfterSec: 30 })
  })

  it("maps 5xx to upstream and other non-OK responses to bad_response", async () => {
    const upstream = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("{}", 502)).impl })
    await expect(upstream.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "upstream" })
    const forbidden = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json('{"status":"NOT_AUTHORIZED"}', 403)).impl })
    await expect(forbidden.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "bad_response" })
  })

  it("maps a network failure to upstream", async () => {
    const provider = createMassiveProvider({
      apiKey: "k",
      baseUrl: "https://api.massive.com",
      fetchImpl: fakeFetch(() => Promise.reject(new TypeError("fetch failed"))).impl,
    })
    await expect(provider.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "upstream" })
  })

  it("rejects a malformed trading date before calling the network", async () => {
    const fake = fakeFetch(() => json("{}"))
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fake.impl })
    await expect(provider.getGroupedDaily("2026/11/20")).rejects.toThrow("Invalid trading date")
    expect(fake.calls).toHaveLength(0)
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/providers/massive.test.ts`
Expected: FAIL with `Failed to load url ../../src/providers/massive.js`.

- [x] **Step 4: Extend the provider types**

Append to `server/src/providers/types.ts`:
```ts
/** One symbol's close for a trading day (decimal string). */
export type DailyClose = { symbol: string; close: string; at: Date }

export interface GroupedDailyProvider {
  /** All US stocks' closes for `date` ("YYYY-MM-DD") in one call. Empty map = no data for that day (yet). */
  getGroupedDaily(date: string): Promise<Map<string, DailyClose>>
}
```

- [x] **Step 5: Implement the adapter**

Create `server/src/providers/massive.ts`:
```ts
import { parseRetryAfter, type FetchLike } from "./http.js"
import { ProviderError, type DailyClose, type GroupedDailyProvider } from "./types.js"

type GroupedResult = { T?: unknown; c?: unknown; t?: unknown }

export type MassiveOptions = { apiKey: string; baseUrl: string; fetchImpl?: FetchLike; timeoutMs?: number }

/** One call inside a cron run that must finish well under 10 s (overview §8.6). */
export const MASSIVE_TIMEOUT_MS = 4_000

/** Massive (ex-Polygon) grouped daily: GET /v2/aggs/grouped/locale/us/market/stocks/{date}. One call covers every US stock. */
export function createMassiveProvider(options: MassiveOptions): GroupedDailyProvider {
  const fetchImpl: FetchLike = options.fetchImpl ?? ((url, init) => fetch(url, init))
  const baseUrl = options.baseUrl.replace(/\/+$/, "")

  return {
    async getGroupedDaily(date: string): Promise<Map<string, DailyClose>> {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error(`Invalid trading date: ${date}`)
      const url = `${baseUrl}/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true`

      let response: Response
      try {
        response = await fetchImpl(url, {
          headers: { Authorization: `Bearer ${options.apiKey}`, Accept: "application/json" },
          signal: AbortSignal.timeout(options.timeoutMs ?? MASSIVE_TIMEOUT_MS),
        })
      } catch (error) {
        throw new ProviderError("massive", error instanceof Error && error.name === "TimeoutError" ? "timeout" : "upstream")
      }

      if (response.status === 429) throw new ProviderError("massive", "rate_limited", parseRetryAfter(response.headers.get("retry-after")), 429)
      if (response.status >= 500) throw new ProviderError("massive", "upstream", undefined, response.status)
      if (!response.ok) throw new ProviderError("massive", "bad_response", undefined, response.status)

      let body: unknown
      try {
        body = await response.json()
      } catch {
        throw new ProviderError("massive", "bad_response")
      }
      return parseGroupedDaily(body)
    },
  }
}

export function parseGroupedDaily(body: unknown): Map<string, DailyClose> {
  const closes = new Map<string, DailyClose>()
  const results = typeof body === "object" && body !== null ? (body as { results?: unknown }).results : undefined
  if (!Array.isArray(results)) return closes
  for (const entry of results as GroupedResult[]) {
    if (typeof entry.T !== "string" || typeof entry.c !== "number" || !Number.isFinite(entry.c) || typeof entry.t !== "number") continue
    closes.set(entry.T, { symbol: entry.T, close: String(entry.c), at: new Date(entry.t) })
  }
  return closes
}
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run test/providers/massive.test.ts && npm run typecheck`
Expected: PASS (`Tests  7 passed (7)`).

- [x] **Step 7: Commit**

```bash
git add server/src/providers/types.ts server/src/providers/massive.ts server/test/providers/massive.test.ts server/test/support/fixtures/massive
git commit -m "feat(server): add Massive grouped-daily provider

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `DailyCloseResolver` (holiday check + Finnhub fallback)

**Files:**
- Create: `server/src/lib/logSink.ts`
- Create: `server/test/support/alertFakes.ts`
- Create: `server/src/services/DailyCloseResolver.ts`
- Test: `server/test/services/DailyCloseResolver.test.ts`

- [x] **Step 1: Write the shared fakes**

Create `server/test/support/alertFakes.ts`:
```ts
import type { DailyClose, GroupedDailyProvider, ProviderQuote, QuoteProvider } from "../../src/providers/types.js"
import type { BucketPolicy, RateLimiter } from "../../src/services/RateLimiter.js"

export class FakeRateLimiter implements RateLimiter {
  readonly taken: string[] = []
  readonly blocked: Array<{ key: string; seconds: number }> = []
  readonly denied = new Set<string>()

  async tryTake(key: string, _policy: BucketPolicy): Promise<boolean> {
    this.taken.push(key)
    return !this.denied.has(key)
  }

  async block(key: string, seconds: number): Promise<void> {
    this.blocked.push({ key, seconds })
  }
}

export class FakeQuoteProvider implements QuoteProvider {
  readonly calls: string[] = []
  private readonly answers = new Map<string, ProviderQuote | Error>()

  answer(symbol: string, price: string, asOf: string): this {
    this.answers.set(symbol, { symbol, price, previousClose: null, open: null, high: null, low: null, change: null, changePercent: null, asOf })
    return this
  }

  fail(symbol: string, error: Error): this {
    this.answers.set(symbol, error)
    return this
  }

  async getQuote(symbol: string): Promise<ProviderQuote | null> {
    this.calls.push(symbol)
    const answer = this.answers.get(symbol)
    if (answer instanceof Error) throw answer
    return answer ?? null
  }
}

export class FakeGroupedProvider implements GroupedDailyProvider {
  readonly calls: string[] = []
  private readonly result: Map<string, DailyClose> | Error

  constructor(result: Map<string, DailyClose> | Error = new Map()) {
    this.result = result
  }

  async getGroupedDaily(date: string): Promise<Map<string, DailyClose>> {
    this.calls.push(date)
    if (this.result instanceof Error) throw this.result
    return this.result
  }
}

export function groupedCloses(tradingDate: string, closes: Record<string, string>): Map<string, DailyClose> {
  return new Map(Object.entries(closes).map(([symbol, close]) => [symbol, { symbol, close, at: new Date(`${tradingDate}T21:00:00.000Z`) }]))
}

/** Collects `warn`/`info` calls so tests can assert what the job logged. */
export class RecordingLogger {
  readonly entries: Array<{ level: "info" | "warn"; message: string; details: object }> = []

  info(details: object, message: string): void {
    this.entries.push({ level: "info", message, details })
  }

  warn(details: object, message: string): void {
    this.entries.push({ level: "warn", message, details })
  }
}
```
Tests use plan 04's `fixedClock(new Date(…))` from `src/lib/clock.ts` wherever they need a clock they can move.

- [x] **Step 2: Write the failing test**

Create `server/test/services/DailyCloseResolver.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { ProviderError } from "../../src/providers/types.js"
import { DailyCloseResolver } from "../../src/services/DailyCloseResolver.js"
import { FakeGroupedProvider, FakeQuoteProvider, FakeRateLimiter, groupedCloses, RecordingLogger } from "../support/alertFakes.js"

const TRADING_DAY = "2026-11-20"
const THANKSGIVING = "2026-11-26"

function setup(grouped: FakeGroupedProvider) {
  const rateLimiter = new FakeRateLimiter()
  const quotes = new FakeQuoteProvider()
  const resolver = new DailyCloseResolver({ grouped, quotes, rateLimiter })
  return { rateLimiter, quotes, resolver }
}

describe("DailyCloseResolver", () => {
  it("uses grouped closes and never calls Finnhub when every symbol is present", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1", NVDA: "185" })))
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "NVDA"])).toEqual({
      kind: "closes",
      closes: new Map([["AAPL", "172.1"], ["NVDA", "185"]]),
      groupedCount: 2,
      fallbackCount: 0,
      missing: [],
    })
    expect(quotes.calls).toEqual([])
    expect(rateLimiter.taken).toEqual(["provider:massive"])
  })

  it("reports a holiday when Massive is empty and SPY last traded on an earlier day", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.answer("SPY", "590.12", "2026-11-25T21:00:00.000Z")
    expect(await resolver.resolve(THANKSGIVING, ["AAPL"])).toEqual({ kind: "holiday" })
    expect(quotes.calls).toEqual(["SPY"])
  })

  it("falls back to same-day Finnhub quotes when grouped data is not published yet", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes
      .answer("SPY", "590.12", "2026-11-20T21:00:00.000Z")
      .answer("AAPL", "172.1", "2026-11-20T21:00:00.000Z")
      .answer("MSFT", "415", "2026-11-19T21:00:00.000Z")
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "MSFT"])).toEqual({
      kind: "closes",
      closes: new Map([["AAPL", "172.1"]]),
      groupedCount: 0,
      fallbackCount: 1,
      missing: ["MSFT"],
    })
    expect(quotes.calls).toEqual(["SPY", "AAPL", "MSFT"])
  })

  it("fetches at most 25 fallback symbols", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" })))
    const others = Array.from({ length: 30 }, (_, index) => `S${String(index + 1).padStart(2, "0")}`)
    for (const symbol of others) quotes.answer(symbol, "10", "2026-11-20T21:00:00.000Z")

    const result = await resolver.resolve(TRADING_DAY, ["AAPL", ...others])

    expect(quotes.calls).toHaveLength(25)
    expect(result).toMatchObject({ kind: "closes", groupedCount: 1, fallbackCount: 25, missing: ["S26", "S27", "S28", "S29", "S30"] })
  })

  it("treats an exhausted Massive bucket as missing grouped data", async () => {
    const grouped = new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" }))
    const { rateLimiter, quotes, resolver } = setup(grouped)
    rateLimiter.denied.add("provider:massive")
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z").answer("AAPL", "172.3", "2026-11-20T20:59:00.000Z")

    expect(await resolver.resolve(TRADING_DAY, ["AAPL"])).toMatchObject({ kind: "closes", closes: new Map([["AAPL", "172.3"]]), fallbackCount: 1 })
    expect(grouped.calls).toEqual([])
  })

  it("blocks the Massive bucket after a 429 and falls back", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(new ProviderError("massive", "rate_limited", 120)))
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z").answer("AAPL", "172.1", "2026-11-20T21:00:00.000Z")

    await resolver.resolve(TRADING_DAY, ["AAPL"])

    expect(rateLimiter.blocked).toEqual([{ key: "provider:massive", seconds: 120 }])
  })

  it("marks symbols missing when the Finnhub bucket is exhausted", async () => {
    const { rateLimiter, quotes, resolver } = setup(new FakeGroupedProvider(groupedCloses(TRADING_DAY, { AAPL: "172.1" })))
    rateLimiter.denied.add("provider:finnhub")
    expect(await resolver.resolve(TRADING_DAY, ["AAPL", "MSFT"])).toMatchObject({ kind: "closes", missing: ["MSFT"], fallbackCount: 0 })
    expect(quotes.calls).toEqual([])
  })

  it("logs Massive failures through the logger passed to resolve()", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider(new ProviderError("massive", "upstream", undefined, 502)))
    quotes.answer("SPY", "590.12", "2026-11-20T21:00:00.000Z")
    const log = new RecordingLogger()
    await resolver.resolve(TRADING_DAY, [], log)
    expect(log.entries).toContainEqual({ level: "warn", message: "alerts.massive.failed", details: { tradingDate: TRADING_DAY, kind: "upstream", status: 502 } })
  })

  it("fails instead of guessing a holiday when the SPY check errors", async () => {
    const { quotes, resolver } = setup(new FakeGroupedProvider())
    quotes.fail("SPY", new ProviderError("finnhub", "upstream"))
    await expect(resolver.resolve(TRADING_DAY, ["AAPL"])).rejects.toMatchObject({ kind: "upstream" })
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/services/DailyCloseResolver.test.ts`
Expected: FAIL with `Failed to load url ../../src/services/DailyCloseResolver.js`.

- [x] **Step 4: Implement the resolver**

Create `server/src/lib/logSink.ts`, the logger shape that the alert job, resolver and sender accept:
```ts
/** The subset of pino's logger the alert job uses. Fastify's `request.log` satisfies it. */
export type LogSink = { info(details: object, message: string): void; warn(details: object, message: string): void }

export const silentLog: LogSink = { info: () => {}, warn: () => {} }
```

Create `server/src/services/DailyCloseResolver.ts`:
```ts
import { easternDate } from "../domain/tradingDate.js"
import { ProviderError, type DailyClose, type GroupedDailyProvider, type QuoteProvider } from "../providers/types.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import { PROVIDER_BUCKETS, type RateLimiter } from "./RateLimiter.js"

export const FALLBACK_LIMIT = 25
const FALLBACK_CONCURRENCY = 5
const HOLIDAY_PROBE = "SPY"

export type CloseResolution =
  | { kind: "holiday" }
  | { kind: "closes"; closes: Map<string, string>; groupedCount: number; fallbackCount: number; missing: string[] }

export interface CloseResolver {
  resolve(tradingDate: string, symbols: string[], log?: LogSink): Promise<CloseResolution>
}

export type DailyCloseResolverDependencies = { grouped: GroupedDailyProvider; quotes: QuoteProvider; rateLimiter: RateLimiter }

const { massive: MASSIVE, finnhub: FINNHUB } = PROVIDER_BUCKETS

/** Overview §8.6 steps 4–6: one grouped call, a holiday check when it is empty, then ≤ 25 same-day Finnhub quotes. */
export class DailyCloseResolver implements CloseResolver {
  private readonly deps: DailyCloseResolverDependencies

  constructor(deps: DailyCloseResolverDependencies) {
    this.deps = deps
  }

  async resolve(tradingDate: string, symbols: string[], log: LogSink = silentLog): Promise<CloseResolution> {
    const grouped = await this.fetchGrouped(tradingDate, log)
    if (grouped.size === 0) {
      const probe = await this.closeOn(HOLIDAY_PROBE, tradingDate, true)
      if (probe === null) return { kind: "holiday" }
    }

    const closes = new Map<string, string>()
    const needed: string[] = []
    for (const symbol of symbols) {
      const hit = grouped.get(symbol)
      if (hit === undefined) needed.push(symbol)
      else closes.set(symbol, hit.close)
    }

    const fallback = needed.slice(0, FALLBACK_LIMIT)
    const missing = needed.slice(FALLBACK_LIMIT)
    const fallbackCloses = await mapWithConcurrency(fallback, FALLBACK_CONCURRENCY, (symbol) => this.closeOn(symbol, tradingDate, false))
    let fallbackCount = 0
    fallback.forEach((symbol, index) => {
      const close = fallbackCloses[index] ?? null
      if (close === null) {
        missing.push(symbol)
      } else {
        closes.set(symbol, close)
        fallbackCount += 1
      }
    })
    missing.sort()

    const groupedCount = symbols.length - needed.length
    log.info({ tradingDate, grouped: groupedCount, fallback: fallbackCount, missing: missing.length }, "alerts.closes")
    return { kind: "closes", closes, groupedCount, fallbackCount, missing }
  }

  private async fetchGrouped(tradingDate: string, log: LogSink): Promise<Map<string, DailyClose>> {
    try {
      if (!(await this.deps.rateLimiter.tryTake(MASSIVE.key, MASSIVE.policy))) {
        log.warn({ tradingDate }, "alerts.massive.bucket_exhausted")
        return new Map()
      }
      return await this.deps.grouped.getGroupedDaily(tradingDate)
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error
      if (error.kind === "rate_limited") await this.deps.rateLimiter.block(MASSIVE.key, error.retryAfterSec ?? 60)
      log.warn({ tradingDate, kind: error.kind, status: error.status }, "alerts.massive.failed")
      return new Map()
    }
  }

  /** The symbol's price if Finnhub's latest quote is from `tradingDate` (ET), else null. Throws only when `strict`. */
  private async closeOn(symbol: string, tradingDate: string, strict: boolean): Promise<string | null> {
    try {
      if (!(await this.deps.rateLimiter.tryTake(FINNHUB.key, FINNHUB.policy))) {
        if (strict) throw new Error(`Finnhub bucket exhausted while checking ${symbol}`)
        return null
      }
      const quote = await this.deps.quotes.getQuote(symbol)
      if (quote === null) return null
      return easternDate(new Date(quote.asOf)) === tradingDate ? quote.price : null
    } catch (error) {
      if (error instanceof ProviderError && error.kind === "rate_limited") {
        await this.deps.rateLimiter.block(FINNHUB.key, error.retryAfterSec ?? 60)
      }
      if (strict) throw error
      return null
    }
  }
}

async function mapWithConcurrency<T, R>(items: T[], limit: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length)
  let next = 0
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next
      next += 1
      results[index] = await work(items[index] as T)
    }
  })
  await Promise.all(workers)
  return results
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/services/DailyCloseResolver.test.ts && npm run typecheck`
Expected: PASS (`Tests  9 passed (9)`).

- [x] **Step 6: Commit**

```bash
git add server/src/lib/logSink.ts server/src/services/DailyCloseResolver.ts server/test/services/DailyCloseResolver.test.ts server/test/support/alertFakes.ts
git commit -m "feat(server): resolve daily closes with holiday detection and Finnhub fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 4: APNs

### Task 9: `ApnsTokenProvider` (ES256 provider JWT, lazy key)

**Files:**
- Create: `server/test/support/apnsKey.ts`
- Create: `server/src/apns/ApnsTokenProvider.ts`
- Test: `server/test/apns/ApnsTokenProvider.test.ts`

- [x] **Step 1: Write the test key helper**

Create `server/test/support/apnsKey.ts`. It generates a P-256 key pair once per test process. Task 13 uses `TEST_APNS_KEY_BASE64` in every test env/config fixture, so no fixture contains a fake or real `.p8`.
```ts
import { generateKeyPairSync } from "node:crypto"

const pair = generateKeyPairSync("ec", {
  namedCurve: "prime256v1",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
})

export const TEST_APNS_PRIVATE_KEY_PEM: string = pair.privateKey
export const TEST_APNS_PUBLIC_KEY_PEM: string = pair.publicKey
/** The shape APNS_KEY has in Vercel: base64 of the PEM. */
export const TEST_APNS_KEY_BASE64: string = Buffer.from(pair.privateKey).toString("base64")
```

- [x] **Step 2: Write the failing test**

Create `server/test/apns/ApnsTokenProvider.test.ts`:
```ts
import { verify } from "node:crypto"
import { describe, expect, it } from "vitest"
import { ApnsTokenProvider, normalizeApnsKey } from "../../src/apns/ApnsTokenProvider.js"
import { fixedClock } from "../../src/lib/clock.js"
import { TEST_APNS_KEY_BASE64, TEST_APNS_PRIVATE_KEY_PEM, TEST_APNS_PUBLIC_KEY_PEM } from "../support/apnsKey.js"

const decode = (segment: string | undefined): unknown => JSON.parse(Buffer.from(segment ?? "", "base64url").toString("utf8"))
const issuedAt = (token: string): unknown => (decode(token.split(".")[1]) as { iat: number }).iat
const KEY = { key: TEST_APNS_KEY_BASE64, keyId: "ABC123DEFG", teamId: "5WDN96EM72" }

describe("ApnsTokenProvider", () => {
  it("signs an ES256 JWT with the key id, team id and issue time", () => {
    const provider = new ApnsTokenProvider(KEY, fixedClock(new Date("2026-11-20T22:00:00.000Z")))
    const [header, claims, signature] = provider.token().split(".")

    expect(decode(header)).toEqual({ alg: "ES256", kid: "ABC123DEFG" })
    expect(decode(claims)).toEqual({ iss: "5WDN96EM72", iat: 1795212000 })
    const raw = Buffer.from(signature ?? "", "base64url")
    expect(raw).toHaveLength(64) // raw r||s, not DER
    expect(verify("sha256", Buffer.from(`${header}.${claims}`), { key: TEST_APNS_PUBLIC_KEY_PEM, dsaEncoding: "ieee-p1363" }, raw)).toBe(true)
  })

  it("reuses the token for just under 50 minutes", () => {
    const clock = fixedClock(new Date("2026-11-20T22:00:00.000Z"))
    const provider = new ApnsTokenProvider(KEY, clock)
    const first = provider.token()
    clock.set(new Date("2026-11-20T22:49:59.000Z"))
    expect(provider.token()).toBe(first)
    clock.set(new Date("2026-11-20T22:50:00.000Z"))
    const second = provider.token()
    expect(second).not.toBe(first)
    expect(issuedAt(second)).toBe(1795215000)
  })

  it("issues a fresh token after invalidate()", () => {
    const clock = fixedClock(new Date("2026-11-20T22:00:00.000Z"))
    const provider = new ApnsTokenProvider(KEY, clock)
    const first = provider.token()
    clock.advance(5_000)
    provider.invalidate()
    const second = provider.token()
    expect(second).not.toBe(first)
    expect(issuedAt(second)).toBe(1795212005)
  })

  it("does not parse the key until the first token is needed", () => {
    const provider = new ApnsTokenProvider({ ...KEY, key: "not-a-key" }, fixedClock(new Date("2026-11-20T22:00:00.000Z")))
    expect(() => provider.token()).toThrow("APNS_KEY")
  })
})

describe("normalizeApnsKey", () => {
  const pem = TEST_APNS_PRIVATE_KEY_PEM.trim()

  it("keeps a raw PEM", () => {
    expect(normalizeApnsKey(TEST_APNS_PRIVATE_KEY_PEM)).toBe(pem)
  })

  it("turns literal \\n sequences into newlines", () => {
    expect(normalizeApnsKey(pem.replaceAll("\n", "\\n"))).toBe(pem)
  })

  it("decodes a base64-encoded PEM", () => {
    expect(normalizeApnsKey(TEST_APNS_KEY_BASE64)).toBe(pem)
  })

  it("rejects anything else", () => {
    expect(() => normalizeApnsKey("not-a-key")).toThrow("APNS_KEY")
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/apns/ApnsTokenProvider.test.ts`
Expected: FAIL with `Failed to load url ../../src/apns/ApnsTokenProvider.js`.

- [x] **Step 4: Implement**

Create `server/src/apns/ApnsTokenProvider.ts`:
```ts
import { createPrivateKey, sign, type KeyObject } from "node:crypto"
import type { Clock } from "../lib/clock.js"

export type ApnsKeyConfig = { key: string; keyId: string; teamId: string }

/** Apple accepts provider tokens for 20–60 minutes; refresh well inside that window. */
export const APNS_TOKEN_MAX_AGE_MS = 50 * 60 * 1000

/** Accepts a raw PEM, a PEM with literal "\n" sequences (env vars), or a base64-encoded PEM. */
export function normalizeApnsKey(raw: string): string {
  const pem = raw.includes("-----BEGIN") ? raw : Buffer.from(raw.trim(), "base64").toString("utf8")
  if (!pem.includes("-----BEGIN") || !pem.includes("PRIVATE KEY-----")) {
    throw new Error("APNS_KEY must be a PEM private key or a base64-encoded PEM")
  }
  return pem.replaceAll("\\n", "\n").trim()
}

/**
 * ES256 provider token for APNs. The key is parsed on the first `token()` call, never in the constructor,
 * so a malformed APNS_KEY breaks only push delivery, not the cold start of every other route.
 */
export class ApnsTokenProvider {
  private readonly config: ApnsKeyConfig
  private readonly clock: Clock
  private readonly maxAgeMs: number
  private privateKey: KeyObject | null = null
  private cached: { token: string; issuedAtMs: number } | null = null

  constructor(config: ApnsKeyConfig, clock: Clock, maxAgeMs: number = APNS_TOKEN_MAX_AGE_MS) {
    this.config = config
    this.clock = clock
    this.maxAgeMs = maxAgeMs
  }

  /** `<header>.<claims>.<signature>`, cached for up to `maxAgeMs`. */
  token(): string {
    const nowMs = this.clock.now().getTime()
    if (this.cached !== null && nowMs - this.cached.issuedAtMs < this.maxAgeMs) return this.cached.token

    this.privateKey ??= createPrivateKey(normalizeApnsKey(this.config.key))
    const input = `${base64url({ alg: "ES256", kid: this.config.keyId })}.${base64url({ iss: this.config.teamId, iat: Math.floor(nowMs / 1000) })}`
    const signature = sign("sha256", Buffer.from(input), { key: this.privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")
    const token = `${input}.${signature}`
    this.cached = { token, issuedAtMs: nowMs }
    return token
  }

  /** Call after APNs answers 403 ExpiredProviderToken. */
  invalidate(): void {
    this.cached = null
  }
}

function base64url(value: object): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url")
}
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `npx vitest run test/apns/ApnsTokenProvider.test.ts && npm run typecheck`
Expected: PASS (`Tests  8 passed (8)`).

- [x] **Step 6: Commit**

```bash
git add server/src/apns/ApnsTokenProvider.ts server/test/apns/ApnsTokenProvider.test.ts server/test/support/apnsKey.ts
git commit -m "feat(server): add lazily-keyed ES256 APNs provider token with 50-minute cache

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Alert payload

**Files:**
- Create: `server/src/apns/payload.ts`
- Test: `server/test/apns/payload.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/apns/payload.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { buildPayload } from "../../src/apns/payload.js"
import type { LadderInput } from "../../src/domain/ladder.js"

const FULL: LadderInput = { buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260" }

describe("buildPayload", () => {
  it("renders the BUY_ZONE alert exactly (overview §8.7)", () => {
    const payload = buildPayload({
      symbol: "AAPL",
      status: "BUY_ZONE",
      price: "172.1",
      ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
      temperature: 27.4,
      tradingDate: "2026-11-20",
    })
    expect(payload.body).toBe(
      '{"aps":{"alert":{"title":"AAPL · BUY ZONE","body":"Closed $172.10, at or below buy-high $175.00 · 27°"},"sound":"default","thread-id":"AAPL"},"symbol":"AAPL","status":"BUY_ZONE","deepLink":"wait://stock/AAPL"}',
    )
    expect(payload.collapseId).toBe("AAPL-2026-11-20")
  })

  it.each([
    { status: "DEEP_BUY", price: "140", temperature: 8.2, title: "AAPL · DEEP BUY", body: "Closed $140.00, at or below buy-low $150.00 · 8°" },
    { status: "TRIM", price: "245.5", temperature: 82.6, title: "AAPL · TRIM", body: "Closed $245.50, at or above trim $240.00 · 83°" },
    { status: "SELL", price: "261", temperature: null, title: "AAPL · SELL", body: "Closed $261.00, at or above sell $260.00" },
  ] as const)("describes $status against its rung", ({ status, price, temperature, title, body }) => {
    const parsed = JSON.parse(buildPayload({ symbol: "AAPL", status, price, ladder: FULL, temperature, tradingDate: "2026-11-20" }).body) as {
      aps: { alert: { title: string; body: string } }
    }
    expect(parsed.aps.alert).toEqual({ title, body })
  })

  it("falls back to the price alone when the rung is missing", () => {
    const parsed = JSON.parse(
      buildPayload({ symbol: "AAPL", status: "BUY_ZONE", price: "100", ladder: { ...FULL, buyHigh: null }, temperature: 30, tradingDate: "2026-11-20" }).body,
    ) as { aps: { alert: { body: string } } }
    expect(parsed.aps.alert.body).toBe("Closed $100.00 · 30°")
  })

  it("stays far below the 4 KB APNs payload limit", () => {
    const payload = buildPayload({ symbol: "BRK.B", status: "SELL", price: "481.25", ladder: FULL, temperature: 99.9, tradingDate: "2026-11-20" })
    expect(Buffer.byteLength(payload.body)).toBeLessThan(4096)
    expect(payload.collapseId).toBe("BRK.B-2026-11-20")
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/apns/payload.test.ts`
Expected: FAIL with `Failed to load url ../../src/apns/payload.js`.

- [x] **Step 3: Implement**

Create `server/src/apns/payload.ts`:
```ts
import type { LadderInput, LadderStatus } from "../domain/ladder.js"

export type ApnsPayload = { body: string; collapseId: string }

export type AlertPayloadInput = {
  symbol: string
  status: LadderStatus
  price: string
  ladder: LadderInput
  temperature: number | null
  tradingDate: string
}

const TITLES: Record<LadderStatus, string> = {
  DEEP_BUY: "DEEP BUY",
  BUY_ZONE: "BUY ZONE",
  WATCH: "WATCH",
  AT_OR_ABOVE_FAIR: "AT/ABOVE FAIR",
  TRIM: "TRIM",
  SELL: "SELL",
  NO_ANCHORS: "NO ANCHORS",
}

function money(value: string): string {
  return `$${Number(value).toFixed(2)}`
}

function rungPhrase(status: LadderStatus, ladder: LadderInput): string | null {
  switch (status) {
    case "DEEP_BUY":
      return ladder.buyLow ? `at or below buy-low ${money(ladder.buyLow)}` : null
    case "BUY_ZONE":
      return ladder.buyHigh ? `at or below buy-high ${money(ladder.buyHigh)}` : null
    case "TRIM":
      return ladder.trim ? `at or above trim ${money(ladder.trim)}` : null
    case "SELL":
      return ladder.sell ? `at or above sell ${money(ladder.sell)}` : null
    default:
      return null
  }
}

/** The APNs JSON body (key order is part of the contract) and its collapse id "<SYMBOL>-<tradingDate>". */
export function buildPayload(input: AlertPayloadInput): ApnsPayload {
  const phrase = rungPhrase(input.status, input.ladder)
  let body = phrase === null ? `Closed ${money(input.price)}` : `Closed ${money(input.price)}, ${phrase}`
  if (input.temperature !== null) body += ` · ${Math.round(input.temperature)}°`

  const payload = {
    aps: { alert: { title: `${input.symbol} · ${TITLES[input.status]}`, body }, sound: "default", "thread-id": input.symbol },
    symbol: input.symbol,
    status: input.status,
    deepLink: `wait://stock/${input.symbol}`,
  }
  return { body: JSON.stringify(payload), collapseId: `${input.symbol}-${input.tradingDate}` }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/apns/payload.test.ts && npm run typecheck`
Expected: PASS (`Tests  6 passed (6)`).

- [x] **Step 5: Commit**

```bash
git add server/src/apns/payload.ts server/test/apns/payload.test.ts
git commit -m "feat(server): build APNs alert payloads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: APNs transports (HTTP/2 and mock)

**Files:**
- Create: `server/src/apns/types.ts`
- Create: `server/src/apns/Http2ApnsTransport.ts`
- Create: `server/src/apns/MockApnsTransport.ts`
- Test: `server/test/apns/transports.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/apns/transports.test.ts`. The HTTP/2 transport is exercised against a local cleartext HTTP/2 server; no Apple host is contacted:
```ts
import { createServer, type Http2Server, type IncomingHttpHeaders } from "node:http2"
import type { AddressInfo } from "node:net"
import { afterAll, beforeAll, describe, expect, it } from "vitest"
import { Http2ApnsTransport } from "../../src/apns/Http2ApnsTransport.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"

describe("Http2ApnsTransport", () => {
  let server: Http2Server
  let baseUrl = ""
  let sessions = 0
  const received: Array<{ headers: IncomingHttpHeaders; body: string }> = []

  beforeAll(async () => {
    server = createServer()
    server.on("session", () => {
      sessions += 1
    })
    server.on("stream", (stream, headers) => {
      let body = ""
      stream.setEncoding("utf8")
      stream.on("data", (chunk: string) => {
        body += chunk
      })
      stream.on("end", () => {
        received.push({ headers, body })
        if (headers[":path"] === "/3/device/slow-token") return // never answers; the client must time out
        if (headers[":path"] === "/3/device/bad-token") {
          stream.respond({ ":status": 400, "apns-id": "apns-2", "content-type": "application/json" })
          stream.end(JSON.stringify({ reason: "BadDeviceToken" }))
        } else {
          stream.respond({ ":status": 200, "apns-id": "apns-1" })
          stream.end()
        }
      })
    })
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
    baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })

  afterAll(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()))
  })

  it("POSTs to /3/device/<token> with the given headers, parses the reason, and reuses one session", async () => {
    const transport = new Http2ApnsTransport({ hosts: { sandbox: baseUrl, production: baseUrl } })

    const ok = await transport.send({
      environment: "sandbox",
      deviceToken: "good-token",
      headers: { authorization: "bearer jwt", "apns-topic": "com.chenkai.wait", "apns-push-type": "alert" },
      body: '{"aps":{}}',
    })
    const bad = await transport.send({ environment: "sandbox", deviceToken: "bad-token", headers: { authorization: "bearer jwt" }, body: "{}" })
    await transport.close()

    expect(ok).toEqual({ status: 200, apnsId: "apns-1", reason: undefined })
    expect(bad).toEqual({ status: 400, apnsId: "apns-2", reason: "BadDeviceToken" })
    expect(received[0]?.headers[":method"]).toBe("POST")
    expect(received[0]?.headers[":path"]).toBe("/3/device/good-token")
    expect(received[0]?.headers["apns-topic"]).toBe("com.chenkai.wait")
    expect(received[0]?.headers["authorization"]).toBe("bearer jwt")
    expect(received[0]?.body).toBe('{"aps":{}}')
    expect(sessions).toBe(1)
  })

  it("destroys the session on timeout so the next send opens a fresh one", async () => {
    const transport = new Http2ApnsTransport({ hosts: { sandbox: baseUrl, production: baseUrl }, timeoutMs: 100 })
    const before = sessions

    await expect(transport.send({ environment: "sandbox", deviceToken: "slow-token", headers: {}, body: "{}" })).rejects.toThrow("timed out")
    const after = await transport.send({ environment: "sandbox", deviceToken: "good-token", headers: {}, body: "{}" })
    await transport.close()

    expect(after.status).toBe(200)
    expect(sessions - before).toBe(2)
  })
})

describe("MockApnsTransport", () => {
  it("records requests, replays scripted responses in order, then answers 200", async () => {
    const transport = new MockApnsTransport()
    transport.script({ status: 410, reason: "Unregistered" }, new Error("socket hang up"))
    const request = { environment: "sandbox" as const, deviceToken: "t", headers: {}, body: "{}" }

    expect(await transport.send(request)).toEqual({ status: 410, reason: "Unregistered" })
    await expect(transport.send(request)).rejects.toThrow("socket hang up")
    expect(await transport.send(request)).toEqual({ status: 200, apnsId: "mock-3" })
    expect(transport.calls).toHaveLength(3)
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/apns/transports.test.ts`
Expected: FAIL with `Failed to load url ../../src/apns/Http2ApnsTransport.js`.

- [x] **Step 3: Write the transport types**

Create `server/src/apns/types.ts`:
```ts
import type { ApnsEnvironment } from "../db/DeviceTokenRepository.js"

export type { ApnsEnvironment }

export type ApnsRequest = { environment: ApnsEnvironment; deviceToken: string; headers: Record<string, string>; body: string }
export type ApnsResponse = { status: number; reason?: string | undefined; apnsId?: string | undefined }

export interface ApnsTransport {
  send(request: ApnsRequest): Promise<ApnsResponse>
  close(): Promise<void>
}
```

- [x] **Step 4: Write the HTTP/2 transport**

Create `server/src/apns/Http2ApnsTransport.ts`:
```ts
import { connect, constants, type ClientHttp2Session } from "node:http2"
import type { ApnsEnvironment, ApnsRequest, ApnsResponse, ApnsTransport } from "./types.js"

export const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
}

export type Http2ApnsTransportOptions = { hosts?: Record<ApnsEnvironment, string>; timeoutMs?: number }

/** One HTTP/2 session per APNs host, opened lazily and reused across sends. */
export class Http2ApnsTransport implements ApnsTransport {
  private readonly hosts: Record<ApnsEnvironment, string>
  private readonly timeoutMs: number
  private readonly sessions = new Map<ApnsEnvironment, ClientHttp2Session>()

  constructor(options: Http2ApnsTransportOptions = {}) {
    this.hosts = options.hosts ?? APNS_HOSTS
    this.timeoutMs = options.timeoutMs ?? 10_000
  }

  send(request: ApnsRequest): Promise<ApnsResponse> {
    const session = this.session(request.environment)
    return new Promise((resolve, reject) => {
      const stream = session.request({
        ":method": "POST",
        ":path": `/3/device/${request.deviceToken}`,
        "content-type": "application/json",
        ...request.headers,
      })
      let status = 0
      let apnsId: string | undefined
      let data = ""
      stream.setEncoding("utf8")
      stream.setTimeout(this.timeoutMs, () => {
        stream.close(constants.NGHTTP2_CANCEL)
        // A hung stream usually means a dead connection: drop the session so the next send reconnects.
        if (this.sessions.get(request.environment) === session) this.sessions.delete(request.environment)
        session.destroy()
        reject(new Error(`APNs request timed out after ${this.timeoutMs} ms`))
      })
      stream.on("response", (headers) => {
        status = Number(headers[":status"] ?? 0)
        const id = headers["apns-id"]
        apnsId = typeof id === "string" ? id : undefined
      })
      stream.on("data", (chunk: string) => {
        data += chunk
      })
      stream.on("end", () => resolve({ status, apnsId, reason: parseReason(data) }))
      stream.on("error", reject)
      stream.end(request.body)
    })
  }

  async close(): Promise<void> {
    const open = [...this.sessions.values()]
    this.sessions.clear()
    await Promise.all(open.map((session) => new Promise<void>((resolve) => session.close(() => resolve()))))
  }

  private session(environment: ApnsEnvironment): ClientHttp2Session {
    const existing = this.sessions.get(environment)
    if (existing !== undefined && !existing.closed && !existing.destroyed) return existing
    const session = connect(this.hosts[environment])
    const forget = (): void => {
      if (this.sessions.get(environment) === session) this.sessions.delete(environment)
    }
    session.on("error", forget)
    session.on("close", forget)
    this.sessions.set(environment, session)
    return session
  }
}

function parseReason(body: string): string | undefined {
  if (body === "") return undefined
  try {
    const parsed = JSON.parse(body) as { reason?: unknown }
    return typeof parsed.reason === "string" ? parsed.reason : undefined
  } catch {
    return undefined
  }
}
```

- [x] **Step 5: Write the mock transport**

Create `server/src/apns/MockApnsTransport.ts`:
```ts
import type { ApnsRequest, ApnsResponse, ApnsTransport } from "./types.js"

export class MockApnsTransport implements ApnsTransport {
  readonly calls: ApnsRequest[] = []
  private readonly scripted: Array<ApnsResponse | Error> = []

  /** Queue responses (or thrown errors) for the next sends; unscripted sends answer 200. */
  script(...responses: Array<ApnsResponse | Error>): void {
    this.scripted.push(...responses)
  }

  async send(request: ApnsRequest): Promise<ApnsResponse> {
    this.calls.push(request)
    const next = this.scripted.shift()
    if (next instanceof Error) throw next
    return next ?? { status: 200, apnsId: `mock-${this.calls.length}` }
  }

  async close(): Promise<void> {}
}
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run test/apns/transports.test.ts && npm run typecheck`
Expected: PASS (`Tests  3 passed (3)`).

- [x] **Step 7: Commit**

```bash
git add server/src/apns/types.ts server/src/apns/Http2ApnsTransport.ts server/src/apns/MockApnsTransport.ts server/test/apns/transports.test.ts
git commit -m "feat(server): add HTTP/2 and mock APNs transports

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `ApnsSender` (headers, retries, pruning)

**Files:**
- Create: `server/src/apns/ApnsSender.ts`
- Test: `server/test/apns/ApnsSender.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/apns/ApnsSender.test.ts`:
```ts
import { beforeEach, describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import type { DeviceToken } from "../../src/db/DeviceTokenRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { RecordingLogger } from "../support/alertFakes.js"

const NOW = new Date("2026-11-20T22:00:00.000Z")
const PAYLOAD = { body: '{"aps":{}}', collapseId: "AAPL-2026-11-20" }
const DEVICE: DeviceToken = {
  token: "a".repeat(64),
  userId: "user-1",
  environment: "sandbox",
  bundleId: "com.chenkai.wait",
  createdAt: NOW,
  updatedAt: NOW,
  lastSuccessAt: null,
}

class FakeTokens {
  current = 1
  invalidations = 0

  token(): string {
    return `provider-${this.current}`
  }

  invalidate(): void {
    this.invalidations += 1
    this.current += 1
  }
}

describe("ApnsSender", () => {
  let transport: MockApnsTransport
  let devices: MockDeviceTokenRepository
  let tokens: FakeTokens
  let sleeps: number[]
  let sender: ApnsSender

  beforeEach(() => {
    transport = new MockApnsTransport()
    devices = new MockDeviceTokenRepository()
    devices.seed([DEVICE])
    tokens = new FakeTokens()
    sleeps = []
    sender = new ApnsSender({
      transport,
      tokens,
      topic: "com.chenkai.wait",
      devices,
      clock: { now: () => NOW },
      sleep: async (ms) => {
        sleeps.push(ms)
      },
    })
  })

  it("sends with the APNs headers and records the success", async () => {
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(transport.calls).toEqual([
      {
        environment: "sandbox",
        deviceToken: DEVICE.token,
        body: PAYLOAD.body,
        headers: {
          authorization: "bearer provider-1",
          "apns-topic": "com.chenkai.wait",
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": "AAPL-2026-11-20",
        },
      },
    ])
    expect(devices.all()[0]?.lastSuccessAt).toEqual(NOW)
  })

  it("prunes a token APNs reports as unregistered (410)", async () => {
    transport.script({ status: 410, reason: "Unregistered" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("pruned")
    expect(devices.all()).toEqual([])
  })

  it("repairs the environment when the token only works on the other host", async () => {
    transport.script({ status: 400, reason: "BadDeviceToken" }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(transport.calls.map((call) => call.environment)).toEqual(["sandbox", "production"])
    expect(devices.all()[0]?.environment).toBe("production")
  })

  it("prunes when both hosts reject the token", async () => {
    transport.script({ status: 400, reason: "BadDeviceToken" }, { status: 400, reason: "BadDeviceToken" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("pruned")
    expect(devices.all()).toEqual([])
  })

  it("refreshes the provider token once on ExpiredProviderToken", async () => {
    transport.script({ status: 403, reason: "ExpiredProviderToken" }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(tokens.invalidations).toBe(1)
    expect(transport.calls.map((call) => call.headers.authorization)).toEqual(["bearer provider-1", "bearer provider-2"])
  })

  it("retries a 5xx once after one second", async () => {
    transport.script({ status: 503 }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(sleeps).toEqual([1000])
  })

  it("gives up after a second 429 and keeps the device", async () => {
    transport.script({ status: 429, reason: "TooManyRequests" }, { status: 429, reason: "TooManyRequests" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("failed")
    expect(transport.calls).toHaveLength(2)
    expect(devices.all()).toHaveLength(1)
  })

  it("retries once when the transport throws", async () => {
    transport.script(new Error("socket hang up"), { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
  })

  it("does not retry other rejections, and logs status and reason without the token", async () => {
    const log = new RecordingLogger()
    transport.script({ status: 400, reason: "BadTopic" })
    expect(await sender.send(DEVICE, PAYLOAD, log)).toBe("failed")
    expect(transport.calls).toHaveLength(1)
    expect(devices.all()).toHaveLength(1)
    expect(log.entries).toEqual([{ level: "warn", message: "apns.failed", details: { environment: "sandbox", status: 400, reason: "BadTopic" } }])
    expect(JSON.stringify(log.entries)).not.toContain(DEVICE.token)
  })

  it("never prunes on DeviceTokenNotForTopic (a misconfigured topic) and reports it", async () => {
    const log = new RecordingLogger()
    transport.script({ status: 400, reason: "DeviceTokenNotForTopic" })
    expect(await sender.send(DEVICE, PAYLOAD, log)).toBe("failed")
    expect(transport.calls).toHaveLength(1)
    expect(devices.all()).toHaveLength(1)
    expect(log.entries[0]?.message).toBe("apns.topic_mismatch")
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/apns/ApnsSender.test.ts`
Expected: FAIL with `Failed to load url ../../src/apns/ApnsSender.js`.

- [x] **Step 3: Implement**

Create `server/src/apns/ApnsSender.ts`:
```ts
import type { ApnsEnvironment, DeviceToken, DeviceTokenRepository } from "../db/DeviceTokenRepository.js"
import type { Clock } from "../lib/clock.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import type { ApnsPayload } from "./payload.js"
import type { ApnsResponse, ApnsTransport } from "./types.js"

export type SendOutcome = "sent" | "pruned" | "failed"

export interface AlertSender {
  send(device: DeviceToken, payload: ApnsPayload, log?: LogSink): Promise<SendOutcome>
}

export type ApnsSenderDependencies = {
  transport: ApnsTransport
  tokens: { token(): string; invalidate(): void }
  topic: string
  devices: Pick<DeviceTokenRepository, "upsert" | "prune" | "markSuccess">
  clock: Clock
  sleep?: (ms: number) => Promise<void>
}

type Kind = "ok" | "unregistered" | "badToken" | "wrongTopic" | "expiredToken" | "transient" | "rejected"
type Attempt = { kind: Kind; environment: ApnsEnvironment; status?: number; reason?: string }

const RETRY_DELAY_MS = 1_000

/** Logs carry environment, status and reason, never the device token. */
export class ApnsSender implements AlertSender {
  private readonly deps: ApnsSenderDependencies
  private readonly sleep: (ms: number) => Promise<void>

  constructor(deps: ApnsSenderDependencies) {
    this.deps = deps
    this.sleep = deps.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)))
  }

  async send(device: DeviceToken, payload: ApnsPayload, log: LogSink = silentLog): Promise<SendOutcome> {
    let result = await this.attempt(device.environment, device.token, payload)
    if (result.kind === "expiredToken") {
      this.deps.tokens.invalidate()
      result = await this.attempt(device.environment, device.token, payload)
    } else if (result.kind === "transient") {
      await this.sleep(RETRY_DELAY_MS)
      result = await this.attempt(device.environment, device.token, payload)
    }

    switch (result.kind) {
      case "ok":
        await this.deps.devices.markSuccess(device.token, this.deps.clock.now())
        return "sent"
      case "unregistered":
        await this.deps.devices.prune(device.token)
        log.info(describe(result), "apns.pruned")
        return "pruned"
      case "badToken":
        return this.retryOnOtherEnvironment(device, payload, log)
      case "wrongTopic":
        // Our APNS_TOPIC is wrong for this app: pruning here would wipe every device, so only report it.
        log.warn({ ...describe(result), topic: this.deps.topic }, "apns.topic_mismatch")
        return "failed"
      default:
        log.warn(describe(result), "apns.failed")
        return "failed"
    }
  }

  /** A sandbox/production mismatch also looks like BadDeviceToken, so prune only after both hosts reject the token. */
  private async retryOnOtherEnvironment(device: DeviceToken, payload: ApnsPayload, log: LogSink): Promise<SendOutcome> {
    const other: ApnsEnvironment = device.environment === "sandbox" ? "production" : "sandbox"
    const result = await this.attempt(other, device.token, payload)
    if (result.kind === "ok") {
      const now = this.deps.clock.now()
      await this.deps.devices.upsert({ token: device.token, userId: device.userId, environment: other, bundleId: device.bundleId }, now)
      await this.deps.devices.markSuccess(device.token, now)
      log.info({ from: device.environment, to: other }, "apns.environment_repaired")
      return "sent"
    }
    if (result.kind === "badToken" || result.kind === "unregistered") {
      await this.deps.devices.prune(device.token)
      log.info(describe(result), "apns.pruned")
      return "pruned"
    }
    log.warn(describe(result), "apns.failed")
    return "failed"
  }

  private async attempt(environment: ApnsEnvironment, deviceToken: string, payload: ApnsPayload): Promise<Attempt> {
    try {
      const response = await this.deps.transport.send({
        environment,
        deviceToken,
        body: payload.body,
        headers: {
          authorization: `bearer ${this.deps.tokens.token()}`,
          "apns-topic": this.deps.topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": payload.collapseId,
        },
      })
      return { kind: classify(response), environment, status: response.status, reason: response.reason }
    } catch (error) {
      return { kind: "transient", environment, reason: error instanceof Error ? error.message : String(error) }
    }
  }
}

function classify(response: ApnsResponse): Kind {
  if (response.status === 200) return "ok"
  if (response.status === 410) return "unregistered"
  if (response.status === 400 && response.reason === "BadDeviceToken") return "badToken"
  if (response.status === 400 && response.reason === "DeviceTokenNotForTopic") return "wrongTopic"
  if (response.status === 403 && response.reason === "ExpiredProviderToken") return "expiredToken"
  if (response.status === 429 || response.status >= 500) return "transient"
  return "rejected"
}

function describe(result: Attempt): { environment: ApnsEnvironment; status: number | undefined; reason: string | undefined } {
  return { environment: result.environment, status: result.status, reason: result.reason }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/apns && npm run typecheck`
Expected: PASS (all four `test/apns/*.test.ts` files; `Tests  27 passed (27)`).

- [x] **Step 5: Commit**

```bash
git add server/src/apns/ApnsSender.ts server/test/apns/ApnsSender.test.ts
git commit -m "feat(server): add APNs sender with retry, token refresh and pruning

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 5: Config, devices route, alert job

### Task 13: Config for Massive, cron and APNs

**Files:**
- Modify: `server/src/config.ts`
- Modify: `server/test/config.test.ts` (`validEnv`, the full-config `toEqual`, and new cases)
- Modify: `server/test/server.test.ts` (inline `env`)
- Modify: `server/test/support/app.ts` (`testConfig`)
- Modify: `server/.env.example`

Every fixture uses the generated key from `test/support/apnsKey.ts` (Task 9). No fixture contains a fake or real `.p8`.

- [x] **Step 1: Write the failing tests**

In `server/test/config.test.ts`, make these changes:

1. Add `import { TEST_APNS_KEY_BASE64 } from "./support/apnsKey.js"` below the existing imports.
2. Add five keys to `validEnv`:
   ```ts
     MASSIVE_API_KEY: "massive-key",
     CRON_SECRET: "cron-secret-cron-secret-cron-secret",
     APNS_KEY: TEST_APNS_KEY_BASE64,
     APNS_KEY_ID: "ABC123DEFG",
     APNS_TEAM_ID: "5WDN96EM72",
   ```
3. In the "maps a valid environment to a typed config" test, add these three properties to the expected object, after `alpacaSecretKey`:
   ```ts
         massive: { apiKey: "massive-key", baseUrl: "https://api.massive.com" },
         cronSecret: "cron-secret-cron-secret-cron-secret",
         apns: { key: TEST_APNS_KEY_BASE64, keyId: "ABC123DEFG", teamId: "5WDN96EM72", topic: "com.chenkai.wait" },
   ```
4. Append this `describe` block at the end of the file:
```ts
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
```

In `server/test/server.test.ts`, add `import { TEST_APNS_KEY_BASE64 } from "./support/apnsKey.js"` and the same five keys to the inline `env` object, using `APNS_KEY: TEST_APNS_KEY_BASE64`.

In `server/test/support/app.ts`, add `import { TEST_APNS_KEY_BASE64 } from "./apnsKey.js"` and these properties to `testConfig`:
```ts
  massive: { apiKey: "massive-test-key", baseUrl: "https://api.massive.com" },
  cronSecret: "cron-test-secret-cron-test-secret",
  apns: { key: TEST_APNS_KEY_BASE64, keyId: "ABC123DEFG", teamId: "5WDN96EM72", topic: "com.chenkai.wait" },
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run test/config.test.ts && npm run typecheck`
Expected: FAIL. The full-config `toEqual` misses `massive`, `cronSecret` and `apns`, and the "fails fast" cases don't throw. `tsc` reports that `testConfig` has unknown properties.

- [x] **Step 3: Extend the config**

In `server/src/config.ts`, make three additions.

1. Add these keys to `EnvSchema`:
```ts
  MASSIVE_API_KEY: z.string().min(1),
  MASSIVE_BASE_URL: z.string().url().default("https://api.massive.com"),
  CRON_SECRET: z.string().min(16),
  APNS_KEY: z.string().min(1),
  APNS_KEY_ID: z.string().length(10),
  APNS_TEAM_ID: z.string().length(10),
  APNS_TOPIC: z.string().min(1).default("com.chenkai.wait"),
```
2. Add these fields to the `Config` interface:
```ts
  massive: { apiKey: string; baseUrl: string }
  cronSecret: string
  /** `key` is the raw env value; ApnsTokenProvider parses it lazily (Task 9). */
  apns: { key: string; keyId: string; teamId: string; topic: string }
```
3. Add these properties to the object `loadConfig` returns, which is built from `const e = parsed.data`:
```ts
    massive: { apiKey: e.MASSIVE_API_KEY, baseUrl: e.MASSIVE_BASE_URL.replace(/\/+$/, "") },
    cronSecret: e.CRON_SECRET,
    apns: { key: e.APNS_KEY, keyId: e.APNS_KEY_ID, teamId: e.APNS_TEAM_ID, topic: e.APNS_TOPIC },
```

In `server/.env.example`, delete plan 04's placeholder line `# Plan 06 adds: MASSIVE_API_KEY, MASSIVE_BASE_URL, CRON_SECRET, APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC`, then append:
```
# Plan 06: daily ladder alerts (set these for Production AND Preview, or Preview deploys fail fast)
MASSIVE_API_KEY=
MASSIVE_BASE_URL=https://api.massive.com
CRON_SECRET=
# APNs .p8 key: raw PEM, PEM with literal \n, or base64 of the PEM
APNS_KEY=
APNS_KEY_ID=
APNS_TEAM_ID=5WDN96EM72
APNS_TOPIC=com.chenkai.wait
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run test/config.test.ts test/server.test.ts && npm test && npm run typecheck`
Expected: PASS. `config.test.ts` gains 8 tests, and the whole suite stays green. `tsc` exits 0.

- [x] **Step 5: Commit**

```bash
git add server/src/config.ts server/.env.example server/test/config.test.ts server/test/server.test.ts server/test/support/app.ts
git commit -m "feat(server): require Massive, cron and APNs config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: `POST /api/devices` and `DELETE /api/devices/:token`

**Files:**
- Create: `server/src/schemas/devices.ts`
- Create: `server/src/routes/api/devices.ts`
- Modify: `server/src/container.ts` (`deviceTokens`)
- Modify: `server/src/app.ts` (register the route)
- Test: `server/test/routes/devices.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/routes/devices.test.ts`. It goes through `buildTestApp`, so it exercises the real JWT middleware, error handler and Ajv options (overview §8.1):
```ts
import { afterEach, describe, expect, it } from "vitest"
import { buildTestApp } from "../support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>
const TOKEN = "a".repeat(64)
const OTHER = "b".repeat(64)

describe("devices routes", () => {
  let harness: TestApp | undefined

  afterEach(async () => {
    await harness?.app.close()
    harness = undefined
  })

  async function setup(): Promise<TestApp> {
    harness = await buildTestApp()
    return harness
  }

  it("stores the device for the signed-in user (204)", async () => {
    const { app, container, user, authHeaders } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    expect(response.statusCode).toBe(204)
    expect(await container.deviceTokens.listByUsers([user.id])).toMatchObject([
      { token: TOKEN, userId: user.id, environment: "sandbox", bundleId: "com.chenkai.wait", lastSuccessAt: null },
    ])
  })

  it("moves a token to whoever registers it last", async () => {
    const { app, container, user, authHeaders } = await setup()
    const other = await container.users.findOrCreateByAnonymousId("00000000-0000-4000-8000-000000000002", container.clock.now())
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    await app.inject({
      method: "POST",
      url: "/api/devices",
      headers: authHeaders(other.id),
      payload: { token: TOKEN, environment: "production", bundleId: "com.chenkai.wait" },
    })
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
    expect((await container.deviceTokens.listByUsers([other.id])).map((device) => device.environment)).toEqual(["production"])
  })

  it.each([
    { name: "uppercase hex", payload: { token: "A".repeat(64), environment: "sandbox" } },
    { name: "too short", payload: { token: "a".repeat(63), environment: "sandbox" } },
    { name: "unknown environment", payload: { token: TOKEN, environment: "development" } },
    { name: "extra property", payload: { token: TOKEN, environment: "sandbox", userId: "user-9" } },
    { name: "null token", payload: { token: null, environment: "sandbox" } },
  ])("rejects $name with 400 VALIDATION_ERROR", async ({ payload }) => {
    const { app, container, user, authHeaders } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
  })

  it("requires authentication", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", payload: { token: TOKEN, environment: "sandbox" } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("answers 401, not 400, when an unauthenticated request is also invalid", async () => {
    const { app } = await setup()
    const badBody = await app.inject({ method: "POST", url: "/api/devices", payload: { token: "nope" } })
    const badParam = await app.inject({ method: "DELETE", url: "/api/devices/NOT-HEX" })
    expect([badBody.statusCode, badParam.statusCode]).toEqual([401, 401])
  })

  it("deletes only the caller's own token (204 either way)", async () => {
    const { app, container, user, authHeaders } = await setup()
    const other = await container.users.findOrCreateByAnonymousId("00000000-0000-4000-8000-000000000002", container.clock.now())
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(other.id), payload: { token: OTHER, environment: "sandbox" } })

    const foreign = await app.inject({ method: "DELETE", url: `/api/devices/${OTHER}`, headers: authHeaders() })
    const own = await app.inject({ method: "DELETE", url: `/api/devices/${TOKEN}`, headers: authHeaders() })

    expect([foreign.statusCode, own.statusCode]).toEqual([204, 204])
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
    expect((await container.deviceTokens.listByUsers([other.id])).map((device) => device.token)).toEqual([OTHER])
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/routes/devices.test.ts`
Expected: FAIL. `POST /api/devices` returns 404 `NOT_FOUND`, and `tsc` reports that `container.deviceTokens` doesn't exist.

- [x] **Step 3: Write the schemas**

Create `server/src/schemas/devices.ts`:
```ts
import { Type, type Static } from "@sinclair/typebox"

export const DEVICE_TOKEN_PATTERN = "^[0-9a-f]{64,200}$"
export const DEFAULT_BUNDLE_ID = "com.chenkai.wait"

export const RegisterDeviceBodySchema = Type.Object(
  {
    token: Type.String({ pattern: DEVICE_TOKEN_PATTERN }),
    environment: Type.Union([Type.Literal("sandbox"), Type.Literal("production")]),
    bundleId: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
  },
  { additionalProperties: false },
)
export type RegisterDeviceBody = Static<typeof RegisterDeviceBodySchema>

export const DeviceTokenParamsSchema = Type.Object({ token: Type.String({ pattern: DEVICE_TOKEN_PATTERN }) }, { additionalProperties: false })
```

- [x] **Step 4: Write the route plugin**

Create `server/src/routes/api/devices.ts`. It follows plan 04's `RouteOptions` convention (see `routes/api/auth.ts`):
```ts
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import { Type } from "@sinclair/typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../container.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"
import { DEFAULT_BUNDLE_ID, DeviceTokenParamsSchema, RegisterDeviceBodySchema } from "../../schemas/devices.js"

const deviceRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)
  const errors = { 400: ErrorResponseSchema, 401: ErrorResponseSchema, 500: ErrorResponseSchema }

  // onRequest, not preHandler: a request without a valid token gets 401 before body/param validation (plan 04).
  app.post(
    "/",
    { onRequest: [authenticate], schema: { body: RegisterDeviceBodySchema, response: { 204: Type.Null(), ...errors } } },
    async (request, reply) => {
      const { token, environment, bundleId } = request.body
      await container.deviceTokens.upsert(
        { token, userId: request.authenticatedUser.id, environment, bundleId: bundleId ?? DEFAULT_BUNDLE_ID },
        container.clock.now(),
      )
      return reply.status(204).send(null)
    },
  )

  app.delete(
    "/:token",
    { onRequest: [authenticate], schema: { params: DeviceTokenParamsSchema, response: { 204: Type.Null(), ...errors } } },
    async (request, reply) => {
      await container.deviceTokens.removeForUser(request.params.token, request.authenticatedUser.id)
      return reply.status(204).send(null)
    },
  )
}

export default deviceRoutes
```

- [x] **Step 5: Wire it into the container and app**

In `server/src/container.ts`:

1. Add the imports:
```ts
import type { DeviceTokenRepository } from "./db/DeviceTokenRepository.js"
import { MockDeviceTokenRepository } from "./db/MockDeviceTokenRepository.js"
import { NeonDeviceTokenRepository } from "./db/NeonDeviceTokenRepository.js"
```
2. Add a member to the `Container` interface:
```ts
  deviceTokens: DeviceTokenRepository
```
3. In `createContainer(config)`, add `deviceTokens: new NeonDeviceTokenRepository(sql),` to the returned object.
4. In `createMockContainer(overrides)`, add `deviceTokens: overrides.deviceTokens ?? new MockDeviceTokenRepository(),` to the returned object, matching the per-field override pattern.

In `server/src/app.ts`, add `import deviceRoutes from "./routes/api/devices.js"` below the other route imports, and this line after the watchlist route registration:
```ts
  await app.register(deviceRoutes, { prefix: "/api/devices", container })
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run test/routes/devices.test.ts && npm test && npm run typecheck`
Expected: PASS (`Tests  10 passed (10)` in `devices.test.ts`), and the whole suite stays green.

- [x] **Step 7: Commit**

```bash
git add server/src/schemas/devices.ts server/src/routes/api/devices.ts server/src/container.ts server/src/app.ts server/test/routes/devices.test.ts
git commit -m "feat(server): add device registration endpoints

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: `AlertJobService`

**Files:**
- Create: `server/src/services/AlertJobService.ts`
- Create: `server/test/support/alertScenario.ts`
- Test: `server/test/services/AlertJobService.test.ts`
- Test: `server/test/services/AlertJobService.pglite.test.ts`

The scenario that both test files use is a Friday close (2026-11-20):

| Item (user) | Ladder | `last_status` / last price | Close | Next status | Outcome |
|---|---|---|---|---|---|
| AAPL (user-1) | 150 / 175 / 210 / 240 / 260 | WATCH / 180 | 172.1 | BUY_ZONE | **push** (user-1 has a device) |
| MSFT (user-1) | buyHigh 300, trim 450 | null / null | 420 | WATCH | first evaluation, stored without a push |
| NVDA (user-2) | buyHigh 100, trim 180 | WATCH / 170 | 185 | TRIM | event created; user-2 has no device, so it is marked sent and skipped |
| TSLA (user-2) | 100 / 120 / 200 | WATCH / 300 | 30 | DEEP_BUY | split guard: the price moved 90%, so no event |
| AMD (user-1) | buyHigh 100 | BUY_ZONE / 95 | 90 | BUY_ZONE | no change |
| BRK.B (user-2) | buyHigh 400 | WATCH / 470 | – | – | no close available, so not evaluated |

Expected result: evaluated 5, transitions 3 (AAPL, NVDA, TSLA), alertsCreated 2, alertsSent 1, pruned 0.

AAPL's temperature: 10 + (172.1 − 150) / 25 × 20 = 27.68, so the push body ends in `· 28°`.

- [x] **Step 1: Write the shared scenario**

Create `server/test/support/alertScenario.ts`:
```ts
import type { EvaluableItem } from "../../src/db/AlertRepository.js"
import type { LadderInput } from "../../src/domain/ladder.js"
import type { LogSink } from "../../src/lib/logSink.js"
import type { CloseResolution, CloseResolver } from "../../src/services/DailyCloseResolver.js"

function ladder(values: Partial<Record<keyof LadderInput, string>>): LadderInput {
  return { buyLow: null, buyHigh: null, fair: null, trim: null, sell: null, ...values }
}

export function scenarioItems(): EvaluableItem[] {
  return [
    { userId: "user-1", symbol: "AAPL", ladder: ladder({ buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260" }), lastStatus: "WATCH", lastEvaluatedPrice: "180" },
    { userId: "user-1", symbol: "MSFT", ladder: ladder({ buyHigh: "300", trim: "450" }), lastStatus: null, lastEvaluatedPrice: null },
    { userId: "user-2", symbol: "NVDA", ladder: ladder({ buyHigh: "100", trim: "180" }), lastStatus: "WATCH", lastEvaluatedPrice: "170" },
    { userId: "user-2", symbol: "TSLA", ladder: ladder({ buyLow: "100", buyHigh: "120", fair: "200" }), lastStatus: "WATCH", lastEvaluatedPrice: "300" },
    { userId: "user-1", symbol: "AMD", ladder: ladder({ buyHigh: "100" }), lastStatus: "BUY_ZONE", lastEvaluatedPrice: "95" },
    { userId: "user-2", symbol: "BRK.B", ladder: ladder({ buyHigh: "400" }), lastStatus: "WATCH", lastEvaluatedPrice: "470" },
  ]
}

export const SCENARIO_RESOLUTION: CloseResolution = {
  kind: "closes",
  closes: new Map([["AAPL", "172.1"], ["MSFT", "420"], ["NVDA", "185"], ["TSLA", "30"], ["AMD", "90"]]),
  groupedCount: 5,
  fallbackCount: 0,
  missing: ["BRK.B"],
}

export class FakeCloseResolver implements CloseResolver {
  readonly calls: Array<{ tradingDate: string; symbols: string[] }> = []
  private readonly result: CloseResolution

  constructor(result: CloseResolution) {
    this.result = result
  }

  async resolve(tradingDate: string, symbols: string[], _log?: LogSink): Promise<CloseResolution> {
    this.calls.push({ tradingDate, symbols: [...symbols] })
    return this.result
  }
}
```

- [x] **Step 2: Write the failing unit test (Mock repositories)**

Create `server/test/services/AlertJobService.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import type { AlertRepository } from "../../src/db/AlertRepository.js"
import { MockAlertRepository } from "../../src/db/MockAlertRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { AlertJobService } from "../../src/services/AlertJobService.js"
import type { CloseResolution } from "../../src/services/DailyCloseResolver.js"
import { RecordingLogger } from "../support/alertFakes.js"
import { FakeCloseResolver, SCENARIO_RESOLUTION, scenarioItems } from "../support/alertScenario.js"

const NOW = new Date("2026-11-20T22:00:00.000Z") // Friday, 5pm ET
const ELEVEN_MINUTES_LATER = new Date(NOW.getTime() + 11 * 60_000) // a crashed run's claim is stale by then
const DEVICE = "a".repeat(64)

/** Wraps a repository so that the first call to `method` throws (simulates a crash mid-job). */
function failOnce<T extends object>(target: T, method: keyof T): T {
  let failed = false
  return new Proxy(target, {
    get(object, property, receiver) {
      const value = Reflect.get(object, property, receiver)
      if (typeof value !== "function") return value
      if (property === method && !failed) {
        return async () => {
          failed = true
          throw new Error(`injected failure in ${String(property)}`)
        }
      }
      return value.bind(object)
    },
  })
}

/** Simulates plan 05's sync resetting `last_status` (an anchor edit) between the job's read and its write. */
function resetBeforeApply(target: MockAlertRepository, userId: string, symbol: string): AlertRepository {
  return new Proxy(target, {
    get(object, property, receiver) {
      const value = Reflect.get(object, property, receiver)
      if (typeof value !== "function") return value
      if (property === "applyEvaluations") {
        return async (...args: Parameters<MockAlertRepository["applyEvaluations"]>) => {
          object.resetStatus(userId, symbol)
          return object.applyEvaluations(...args)
        }
      }
      return value.bind(object)
    },
  })
}

function makeJob(options: { resolution?: CloseResolution; wrap?: (repo: MockAlertRepository) => AlertRepository } = {}) {
  const alertsRepo = new MockAlertRepository()
  alertsRepo.seedItems(scenarioItems())
  const devices = new MockDeviceTokenRepository()
  devices.seed([{ token: DEVICE, userId: "user-1", environment: "sandbox", bundleId: "com.chenkai.wait", createdAt: NOW, updatedAt: NOW, lastSuccessAt: null }])
  const transport = new MockApnsTransport()
  const sender = new ApnsSender({
    transport,
    tokens: { token: () => "provider-jwt", invalidate: () => {} },
    topic: "com.chenkai.wait",
    devices,
    clock: { now: () => NOW },
    sleep: async () => {},
  })
  const closes = new FakeCloseResolver(options.resolution ?? SCENARIO_RESOLUTION)
  let counter = 0
  const job = new AlertJobService({
    alerts: options.wrap ? options.wrap(alertsRepo) : alertsRepo,
    devices,
    closes,
    sender,
    newId: () => `event-${(counter += 1)}`,
  })
  return { job, alertsRepo, devices, transport, closes }
}

const statuses = (repo: MockAlertRepository) =>
  ["AAPL", "MSFT", "NVDA", "TSLA", "AMD", "BRK.B"].map((symbol) => {
    const item = repo.item(symbol === "NVDA" || symbol === "TSLA" || symbol === "BRK.B" ? "user-2" : "user-1", symbol)
    return [symbol, item?.lastStatus ?? null, item?.lastEvaluatedPrice ?? null]
  })

describe("AlertJobService", () => {
  it("evaluates, seeds, guards splits, records events and pushes once", async () => {
    const { job, alertsRepo, transport, closes } = makeJob()
    const log = new RecordingLogger()

    expect(await job.run(NOW, log)).toEqual({
      tradingDate: "2026-11-20",
      status: "completed",
      evaluated: 5,
      transitions: 3,
      alertsCreated: 2,
      alertsSent: 1,
      pruned: 0,
    })
    expect(closes.calls).toEqual([{ tradingDate: "2026-11-20", symbols: ["AAPL", "AMD", "BRK.B", "MSFT", "NVDA", "TSLA"] }])
    expect(alertsRepo.allEvents().map((event) => [event.id, event.symbol, event.previousStatus, event.status, event.price, event.sentAt !== null])).toEqual([
      ["event-1", "AAPL", "WATCH", "BUY_ZONE", "172.1", true],
      ["event-2", "NVDA", "WATCH", "TRIM", "185", true],
    ])
    expect(statuses(alertsRepo)).toEqual([
      ["AAPL", "BUY_ZONE", "172.1"],
      ["MSFT", "WATCH", "420"],
      ["NVDA", "TRIM", "185"],
      ["TSLA", "DEEP_BUY", "30"],
      ["AMD", "BUY_ZONE", "90"],
      ["BRK.B", "WATCH", "470"],
    ])
    expect(transport.calls).toHaveLength(1)
    expect((JSON.parse(transport.calls[0]?.body ?? "{}") as { aps: { alert: unknown } }).aps.alert).toEqual({
      title: "AAPL · BUY ZONE",
      body: "Closed $172.10, at or below buy-high $175.00 · 28°",
    })
    expect(alertsRepo.runStatus("2026-11-20")).toBe("completed")
    expect(log.entries).toContainEqual({
      level: "warn",
      message: "alerts.split_guard",
      details: { tradingDate: "2026-11-20", symbol: "TSLA", previousPrice: "300", close: "30" },
    })
  })

  it("returns skipped while another delivery of the same cron is still running", async () => {
    const { job, closes } = makeJob({ wrap: (repo) => failOnce(repo, "applyEvaluations") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure")
    expect(await job.run(new Date(NOW.getTime() + 60_000))).toMatchObject({ status: "skipped", evaluated: 0 })
    expect(closes.calls).toHaveLength(1)
  })

  it("only evaluates US market symbols (plan 04's SYMBOL_REGEX)", async () => {
    const { job, alertsRepo, closes } = makeJob()
    alertsRepo.seedItems([{ userId: "user-1", symbol: "0700.HK", ladder: { buyHigh: "300" }, lastStatus: "WATCH", lastEvaluatedPrice: "320" }])
    expect(await job.run(NOW)).toMatchObject({ status: "completed", evaluated: 5 })
    expect(closes.calls[0]?.symbols).not.toContain("0700.HK")
    expect(alertsRepo.item("user-1", "0700.HK")?.lastStatus).toBe("WATCH")
  })

  it("does not overwrite a status that sync reset while the job was running", async () => {
    const { job, alertsRepo } = makeJob({ wrap: (repo) => resetBeforeApply(repo, "user-1", "AAPL") })
    await job.run(NOW)
    expect(alertsRepo.item("user-1", "AAPL")?.lastStatus).toBeNull()
  })

  it("skips weekends without touching the database", async () => {
    const { job, alertsRepo, closes } = makeJob()
    expect(await job.run(new Date("2026-11-21T22:00:00.000Z"))).toEqual({
      tradingDate: "2026-11-21",
      status: "skipped",
      evaluated: 0,
      transitions: 0,
      alertsCreated: 0,
      alertsSent: 0,
      pruned: 0,
    })
    expect(closes.calls).toEqual([])
    expect(alertsRepo.runStatus("2026-11-21")).toBeUndefined()
  })

  it("records a holiday once and does not re-resolve it", async () => {
    const { job, alertsRepo, closes } = makeJob({ resolution: { kind: "holiday" } })
    const thanksgiving = new Date("2026-11-26T22:00:00.000Z")
    expect((await job.run(thanksgiving)).status).toBe("holiday")
    expect((await job.run(thanksgiving)).status).toBe("holiday")
    expect(closes.calls).toHaveLength(1)
    expect(alertsRepo.runStatus("2026-11-26")).toBe("holiday")
    expect(alertsRepo.item("user-1", "AAPL")?.lastStatus).toBe("WATCH")
  })

  it("only re-sends pending events when the day already completed", async () => {
    const { job, transport, closes } = makeJob()
    await job.run(NOW)
    expect(await job.run(NOW)).toEqual({
      tradingDate: "2026-11-20",
      status: "resent",
      evaluated: 0,
      transitions: 0,
      alertsCreated: 0,
      alertsSent: 0,
      pruned: 0,
    })
    expect(transport.calls).toHaveLength(1)
    expect(closes.calls).toHaveLength(1)
  })

  it("recovers from a crash after inserting events without duplicating them", async () => {
    const { job, alertsRepo, transport } = makeJob({ wrap: (repo) => failOnce(repo, "applyEvaluations") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure in applyEvaluations")
    expect(await job.run(ELEVEN_MINUTES_LATER)).toMatchObject({ status: "completed", transitions: 3, alertsCreated: 0, alertsSent: 1 })
    expect(alertsRepo.allEvents()).toHaveLength(2)
    expect(transport.calls).toHaveLength(1)
  })

  it("recovers from a crash after updating statuses by sending the pending events", async () => {
    const { job, transport } = makeJob({ wrap: (repo) => failOnce(repo, "listPendingEvents") })
    await expect(job.run(NOW)).rejects.toThrow("injected failure in listPendingEvents")
    expect(await job.run(ELEVEN_MINUTES_LATER)).toMatchObject({ status: "completed", transitions: 0, alertsCreated: 0, alertsSent: 1 })
    expect(transport.calls).toHaveLength(1)
  })

  it("retries failed deliveries on the next run of the same day", async () => {
    const { job, transport, alertsRepo } = makeJob()
    transport.script({ status: 500 }, { status: 500 })
    expect(await job.run(NOW)).toMatchObject({ status: "completed", alertsCreated: 2, alertsSent: 0 })
    expect(alertsRepo.allEvents()[0]?.attempts).toBe(1)
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 1 })
  })

  it("stops retrying an event after three failed attempts", async () => {
    const { job, transport } = makeJob()
    transport.script(...Array.from({ length: 6 }, () => ({ status: 500 })))
    await job.run(NOW)
    await job.run(NOW)
    await job.run(NOW)
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 })
    expect(transport.calls).toHaveLength(6)
  })

  it("prunes dead tokens and stops retrying an event that has no devices left", async () => {
    const { job, transport, devices, alertsRepo } = makeJob()
    transport.script({ status: 410, reason: "Unregistered" })
    expect(await job.run(NOW)).toMatchObject({ status: "completed", alertsSent: 0, pruned: 1 })
    expect(devices.all()).toEqual([])
    expect(alertsRepo.allEvents().every((event) => event.sentAt !== null)).toBe(true)
  })
})
```

- [x] **Step 3: Run the test to verify it fails**

Run: `npx vitest run test/services/AlertJobService.test.ts`
Expected: FAIL with `Failed to load url ../../src/services/AlertJobService.js`.

- [x] **Step 4: Implement the job**

Create `server/src/services/AlertJobService.ts`:
```ts
import { randomUUID } from "node:crypto"
import type { AlertSender } from "../apns/ApnsSender.js"
import { buildPayload } from "../apns/payload.js"
import type { AlertRepository, EvaluationUpdate, NewAlertEvent } from "../db/AlertRepository.js"
import type { DeviceToken, DeviceTokenRepository } from "../db/DeviceTokenRepository.js"
import { classifyStatus, shouldAlert, temperature } from "../domain/ladder.js"
import { easternDate, isWeekend } from "../domain/tradingDate.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import { SYMBOL_REGEX } from "../schemas/common.js"
import type { CloseResolver } from "./DailyCloseResolver.js"

export type AlertJobStatus = "completed" | "holiday" | "skipped" | "resent"

export type AlertJobResult = {
  tradingDate: string
  status: AlertJobStatus
  evaluated: number
  transitions: number
  alertsCreated: number
  alertsSent: number
  pruned: number
}

/** What the cron route needs; `Container.alertJob` is typed with this so tests can stub it. */
export interface AlertJob {
  run(now: Date, log?: LogSink): Promise<AlertJobResult>
}

export type AlertJobDependencies = {
  alerts: AlertRepository
  devices: Pick<DeviceTokenRepository, "listByUsers">
  closes: CloseResolver
  sender: AlertSender
  newId?: () => string
}

export const MAX_SEND_ATTEMPTS = 3
/** A close more than 50% away from the last evaluated price is treated as a split (overview §8.6 step 7). */
export const SPLIT_GUARD_RATIO = 0.5

type Delivery = { sent: number; pruned: number; skipped: number; failed: number }

/** Overview §8.6. Every step is safe to rerun on the same trading day, and only one caller runs a day at a time. */
export class AlertJobService implements AlertJob {
  private readonly deps: AlertJobDependencies
  private readonly newId: () => string

  constructor(deps: AlertJobDependencies) {
    this.deps = deps
    this.newId = deps.newId ?? (() => randomUUID())
  }

  async run(now: Date, log: LogSink = silentLog): Promise<AlertJobResult> {
    const tradingDate = easternDate(now)
    const idle: AlertJobResult = { tradingDate, status: "skipped", evaluated: 0, transitions: 0, alertsCreated: 0, alertsSent: 0, pruned: 0 }
    if (isWeekend(tradingDate)) return idle

    const run = await this.deps.alerts.beginRun(tradingDate, now)
    if (!run.claimed) {
      if (run.status === "holiday") return { ...idle, status: "holiday" }
      if (run.status === "completed") {
        const delivery = await this.deliverPending(tradingDate, now, log)
        return { ...idle, status: "resent", alertsSent: delivery.sent, pruned: delivery.pruned }
      }
      log.info({ tradingDate }, "alerts.in_progress")
      return idle
    }

    // Only US market symbols (overview §8.4): synced HK/OTC items would otherwise eat the 25-call Finnhub fallback.
    const listed = await this.deps.alerts.listEvaluableItems()
    const items = listed.filter((item) => SYMBOL_REGEX.test(item.symbol))
    const symbols = [...new Set(items.map((item) => item.symbol))]
    const resolution = await this.deps.closes.resolve(tradingDate, symbols, log)
    if (resolution.kind === "holiday") {
      await this.deps.alerts.finishRun(tradingDate, "holiday", { items: items.length }, now)
      log.info({ tradingDate }, "alerts.holiday")
      return { ...idle, status: "holiday" }
    }

    const updates: EvaluationUpdate[] = []
    const events: NewAlertEvent[] = []
    let transitions = 0
    let splitSkips = 0
    for (const item of items) {
      const close = resolution.closes.get(item.symbol)
      if (close === undefined) continue
      const next = classifyStatus(item.ladder, Number(close))
      if (next === "NO_ANCHORS") continue
      updates.push({ userId: item.userId, symbol: item.symbol, previousStatus: item.lastStatus, status: next, price: close })
      if (item.lastStatus === null || item.lastStatus === next) continue
      transitions += 1
      if (!shouldAlert(item.lastStatus, next)) continue
      if (looksLikeSplit(item.lastEvaluatedPrice, close)) {
        splitSkips += 1
        log.warn({ tradingDate, symbol: item.symbol, previousPrice: item.lastEvaluatedPrice, close }, "alerts.split_guard")
        continue
      }
      events.push({ id: this.newId(), userId: item.userId, symbol: item.symbol, tradingDate, status: next, previousStatus: item.lastStatus, price: close })
    }

    const created = await this.deps.alerts.insertEvents(events, now)
    await this.deps.alerts.applyEvaluations(updates, now)
    const delivery = await this.deliverPending(tradingDate, now, log)

    const result: AlertJobResult = {
      tradingDate,
      status: "completed",
      evaluated: updates.length,
      transitions,
      alertsCreated: created.length,
      alertsSent: delivery.sent,
      pruned: delivery.pruned,
    }
    await this.deps.alerts.finishRun(
      tradingDate,
      "completed",
      {
        evaluated: result.evaluated,
        transitions,
        alertsCreated: result.alertsCreated,
        alertsSent: delivery.sent,
        pruned: delivery.pruned,
        skippedNoDevice: delivery.skipped,
        failed: delivery.failed,
        splitSkips,
        grouped: resolution.groupedCount,
        fallback: resolution.fallbackCount,
        missing: resolution.missing.length,
        nonMarketSymbols: listed.length - items.length,
      },
      now,
    )
    log.info({ ...result, splitSkips, missing: resolution.missing.length }, "alerts.completed")
    return result
  }

  /** Overview §8.6 step 10. */
  private async deliverPending(tradingDate: string, now: Date, log: LogSink): Promise<Delivery> {
    const delivery: Delivery = { sent: 0, pruned: 0, skipped: 0, failed: 0 }
    const pending = await this.deps.alerts.listPendingEvents(tradingDate, MAX_SEND_ATTEMPTS)
    if (pending.length === 0) return delivery

    const devicesByUser = groupByUser(await this.deps.devices.listByUsers([...new Set(pending.map((event) => event.userId))]))
    for (const event of pending) {
      const targets = devicesByUser.get(event.userId) ?? []
      if (targets.length === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
        continue
      }

      const payload = buildPayload({
        symbol: event.symbol,
        status: event.status,
        price: event.price,
        ladder: event.ladder,
        temperature: temperature(event.ladder, Number(event.price)),
        tradingDate,
      })
      const remaining: DeviceToken[] = []
      let delivered = false
      for (const device of targets) {
        const outcome = await this.deps.sender.send(device, payload, log)
        if (outcome === "pruned") {
          delivery.pruned += 1
          continue
        }
        remaining.push(device)
        if (outcome === "sent") delivered = true
      }
      devicesByUser.set(event.userId, remaining)

      if (delivered) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.sent += 1
      } else if (remaining.length === 0) {
        await this.deps.alerts.markSent(event.id, now)
        delivery.skipped += 1
      } else {
        await this.deps.alerts.incrementAttempts(event.id)
        delivery.failed += 1
      }
    }
    return delivery
  }
}

function looksLikeSplit(previousPrice: string | null, close: string): boolean {
  if (previousPrice === null) return false
  const previous = Number(previousPrice)
  if (!Number.isFinite(previous) || previous <= 0) return false
  return Math.abs(Number(close) / previous - 1) > SPLIT_GUARD_RATIO
}

function groupByUser(devices: DeviceToken[]): Map<string, DeviceToken[]> {
  const byUser = new Map<string, DeviceToken[]>()
  for (const device of devices) byUser.set(device.userId, [...(byUser.get(device.userId) ?? []), device])
  return byUser
}
```

- [x] **Step 5: Run the unit test to verify it passes**

Run: `npx vitest run test/services/AlertJobService.test.ts`
Expected: PASS (`Tests  12 passed (12)`).

- [x] **Step 6: Write the PGlite integration test**

Create `server/test/services/AlertJobService.pglite.test.ts`. It runs the same scenario through the real SQL repositories:
```ts
import { describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import { NeonAlertRepository } from "../../src/db/NeonAlertRepository.js"
import { NeonDeviceTokenRepository } from "../../src/db/NeonDeviceTokenRepository.js"
import { AlertJobService } from "../../src/services/AlertJobService.js"
import { insertItem } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"
import { FakeCloseResolver, SCENARIO_RESOLUTION } from "../support/alertScenario.js"

const NOW = new Date("2026-11-20T22:00:00.000Z")

describe("AlertJobService on PGlite", () => {
  it("runs the scenario end to end and is idempotent on rerun", async () => {
    const { sql, close } = await createTestDb()
    await insertItem(sql, { userId: "user-1", symbol: "AAPL", buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260", lastStatus: "WATCH", lastEvaluatedPrice: "180" })
    await insertItem(sql, { userId: "user-1", symbol: "MSFT", buyHigh: "300", trim: "450" })
    await insertItem(sql, { userId: "user-2", symbol: "NVDA", buyHigh: "100", trim: "180", lastStatus: "WATCH", lastEvaluatedPrice: "170" })
    await insertItem(sql, { userId: "user-2", symbol: "TSLA", buyLow: "100", buyHigh: "120", fair: "200", lastStatus: "WATCH", lastEvaluatedPrice: "300" })
    await insertItem(sql, { userId: "user-1", symbol: "AMD", buyHigh: "100", lastStatus: "BUY_ZONE", lastEvaluatedPrice: "95" })
    await insertItem(sql, { userId: "user-2", symbol: "BRK.B", buyHigh: "400", lastStatus: "WATCH", lastEvaluatedPrice: "470" })
    const devices = new NeonDeviceTokenRepository(sql)
    await devices.upsert({ token: "a".repeat(64), userId: "user-1", environment: "sandbox", bundleId: "com.chenkai.wait" }, NOW)
    const transport = new MockApnsTransport()
    const job = new AlertJobService({
      alerts: new NeonAlertRepository(sql),
      devices,
      closes: new FakeCloseResolver(SCENARIO_RESOLUTION),
      sender: new ApnsSender({ transport, tokens: { token: () => "jwt", invalidate: () => {} }, topic: "com.chenkai.wait", devices, clock: { now: () => NOW } }),
    })

    expect(await job.run(NOW)).toEqual({ tradingDate: "2026-11-20", status: "completed", evaluated: 5, transitions: 3, alertsCreated: 2, alertsSent: 1, pruned: 0 })
    expect(await job.run(NOW)).toMatchObject({ status: "resent", alertsSent: 0 })

    const rows = await sql`SELECT symbol, last_status, trim_scale(last_evaluated_price)::text AS price FROM watchlist_items ORDER BY symbol`
    expect(rows).toEqual([
      { symbol: "AAPL", last_status: "BUY_ZONE", price: "172.1" },
      { symbol: "AMD", last_status: "BUY_ZONE", price: "90" },
      { symbol: "BRK.B", last_status: "WATCH", price: "470" },
      { symbol: "MSFT", last_status: "WATCH", price: "420" },
      { symbol: "NVDA", last_status: "TRIM", price: "185" },
      { symbol: "TSLA", last_status: "DEEP_BUY", price: "30" },
    ])
    const events = await sql`SELECT symbol, status, sent_at IS NOT NULL AS sent FROM alert_events ORDER BY symbol`
    expect(events).toEqual([
      { symbol: "AAPL", status: "BUY_ZONE", sent: true },
      { symbol: "NVDA", status: "TRIM", sent: true },
    ])
    expect(await sql`SELECT status, (stats->>'splitSkips')::int AS split_skips FROM alert_job_runs`).toEqual([{ status: "completed", split_skips: 1 }])
    expect(transport.calls).toHaveLength(1)
    await close()
  })
})
```

- [x] **Step 7: Run the integration test and the full suite**

Run: `npx vitest run test/services && npm test && npm run typecheck`
Expected: PASS (`Tests  13 passed (13)` for the two job files), and the whole suite stays green.

- [x] **Step 8: Commit**

```bash
git add server/src/services/AlertJobService.ts server/test/support/alertScenario.ts server/test/services/AlertJobService.test.ts server/test/services/AlertJobService.pglite.test.ts
git commit -m "feat(server): add idempotent daily alert job

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 6: Cron route, wiring, Vercel cron, test-push script

### Task 16: `GET /api/internal/daily-alerts` and container wiring

**Files:**
- Create: `server/src/schemas/alerts.ts`
- Create: `server/src/routes/api/internal/dailyAlerts.ts`
- Modify: `server/src/container.ts` (`alerts`, `alertJob`)
- Modify: `server/src/app.ts` (register the route)
- Test: `server/test/routes/dailyAlerts.test.ts`

- [x] **Step 1: Write the failing route test**

Create `server/test/routes/dailyAlerts.test.ts`. It runs through `buildTestApp` and overrides only `alertJob`. The secret is `testConfig.cronSecret` (Task 13).
```ts
import { afterEach, describe, expect, it } from "vitest"
import type { LogSink } from "../../src/lib/logSink.js"
import type { AlertJob, AlertJobResult } from "../../src/services/AlertJobService.js"
import { buildTestApp, testConfig } from "../support/app.js"

const RESULT: AlertJobResult = { tradingDate: "2026-11-20", status: "completed", evaluated: 5, transitions: 3, alertsCreated: 2, alertsSent: 1, pruned: 0 }

class FakeAlertJob implements AlertJob {
  readonly runs: Array<{ now: Date; hasLogger: boolean }> = []

  async run(now: Date, log?: LogSink): Promise<AlertJobResult> {
    this.runs.push({ now, hasLogger: log !== undefined })
    return RESULT
  }
}

describe("GET /api/internal/daily-alerts", () => {
  let close: (() => Promise<void>) | undefined

  afterEach(async () => {
    await close?.()
    close = undefined
  })

  async function setup() {
    const alertJob = new FakeAlertJob()
    const harness = await buildTestApp({ alertJob })
    close = () => harness.app.close()
    return { ...harness, alertJob }
  }

  it.each([
    { name: "no header", headers: {} },
    { name: "wrong secret", headers: { authorization: `Bearer ${"x".repeat(32)}` } },
    { name: "missing Bearer prefix", headers: { authorization: testConfig.cronSecret } },
  ])("rejects $name with 401 and does not run the job", async ({ headers }) => {
    const { app, alertJob } = await setup()
    const response = await app.inject({ method: "GET", url: "/api/internal/daily-alerts", headers })
    expect(response.statusCode).toBe(401)
    expect(response.json()).toEqual({ error: { code: "UNAUTHORIZED", message: "Missing or invalid cron secret" } })
    expect(alertJob.runs).toEqual([])
  })

  it("runs the job at the container clock's now with the request logger, and returns its stats", async () => {
    const { app, alertJob, container } = await setup()
    const response = await app.inject({
      method: "GET",
      url: "/api/internal/daily-alerts",
      headers: { authorization: `Bearer ${testConfig.cronSecret}` },
    })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual(RESULT)
    expect(alertJob.runs).toEqual([{ now: container.clock.now(), hasLogger: true }])
  })

  it("is wired with the real mock-container job by default", async () => {
    const harness = await buildTestApp()
    close = () => harness.app.close()
    const response = await harness.app.inject({
      method: "GET",
      url: "/api/internal/daily-alerts",
      headers: { authorization: `Bearer ${testConfig.cronSecret}` },
    })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toMatchObject({ tradingDate: "2026-11-20", status: "holiday" })
  })
})
```
The mock container's clock is plan 04's fixed Friday 2026-11-20 15:00 UTC, and its default close resolver reports a holiday (Step 5), so the last test expects `holiday`.

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/routes/dailyAlerts.test.ts`
Expected: FAIL. `tsc` reports that `alertJob` isn't a `Container` member, and the route answers 404.

- [x] **Step 3: Write the schema**

Create `server/src/schemas/alerts.ts`:
```ts
import { Type } from "@sinclair/typebox"

const Count = Type.Integer({ minimum: 0 })

export const DailyAlertsResponseSchema = Type.Object(
  {
    tradingDate: Type.String({ pattern: "^\\d{4}-\\d{2}-\\d{2}$" }),
    status: Type.Union([Type.Literal("completed"), Type.Literal("holiday"), Type.Literal("skipped"), Type.Literal("resent")]),
    evaluated: Count,
    transitions: Count,
    alertsCreated: Count,
    alertsSent: Count,
    pruned: Count,
  },
  { additionalProperties: false },
)
```

- [x] **Step 4: Write the route**

Create `server/src/routes/api/internal/dailyAlerts.ts`:
```ts
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../../container.js"
import { sendError } from "../../../lib/errors.js"
import { safeEqual } from "../../../lib/safeEqual.js"
import { DailyAlertsResponseSchema } from "../../../schemas/alerts.js"
import { ErrorResponseSchema } from "../../../schemas/common.js"

export type DailyAlertsRouteOptions = RouteOptions & { cronSecret: string }

/** Vercel Cron sends `Authorization: Bearer $CRON_SECRET` (overview §8.6). */
const dailyAlertsRoutes: FastifyPluginAsync<DailyAlertsRouteOptions> = async (server, { container, cronSecret }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()

  app.get(
    "/daily-alerts",
    { schema: { response: { 200: DailyAlertsResponseSchema, 401: ErrorResponseSchema, 500: ErrorResponseSchema } } },
    async (request, reply) => {
      if (!safeEqual(request.headers.authorization ?? "", `Bearer ${cronSecret}`)) {
        return sendError(reply, 401, "UNAUTHORIZED", "Missing or invalid cron secret")
      }
      const result = await container.alertJob.run(container.clock.now(), request.log)
      request.log.info(result, "alerts.daily")
      return result
    },
  )
}

export default dailyAlertsRoutes
```

- [x] **Step 5: Wire the job into the container**

In `server/src/container.ts`:

1. Add the imports:
```ts
import { ApnsSender } from "./apns/ApnsSender.js"
import { ApnsTokenProvider } from "./apns/ApnsTokenProvider.js"
import { Http2ApnsTransport } from "./apns/Http2ApnsTransport.js"
import { MockApnsTransport } from "./apns/MockApnsTransport.js"
import type { AlertRepository } from "./db/AlertRepository.js"
import { MockAlertRepository } from "./db/MockAlertRepository.js"
import { NeonAlertRepository } from "./db/NeonAlertRepository.js"
import { createMassiveProvider } from "./providers/massive.js"
import { AlertJobService, type AlertJob } from "./services/AlertJobService.js"
import { DailyCloseResolver } from "./services/DailyCloseResolver.js"
```
2. Add two members to the `Container` interface:
```ts
  alerts: AlertRepository
  alertJob: AlertJob
```
3. In `createContainer(config)`, replace Task 14's inline `deviceTokens: new NeonDeviceTokenRepository(sql),` with a shared local, and build the job from the existing `sql`, `clock`, `rateLimiter` and `finnhub` locals:
```ts
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
  // …in the returned object literal:
    deviceTokens,
    alerts,
    alertJob,
```
None of this does I/O or parses the APNs key, so cold start is unaffected (Task 9).

4. In `createMockContainer(overrides)`, use the per-field override pattern. Replace Task 14's `deviceTokens: overrides.deviceTokens ?? …` line with a local:
```ts
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
  // …in the returned object literal:
    deviceTokens,
    alerts,
    alertJob,
```

In `server/src/app.ts`, add `import dailyAlertsRoutes from "./routes/api/internal/dailyAlerts.js"` and register it after the devices route:
```ts
  await app.register(dailyAlertsRoutes, { prefix: "/api/internal", container, cronSecret: config.cronSecret })
```

- [x] **Step 6: Run everything**

Run: `npx vitest run test/routes && npm test && npm run typecheck`
Expected: PASS. `dailyAlerts.test.ts` reports `Tests  5 passed (5)`, and the whole suite stays green, including `server.test.ts`, which builds the real container from `process.env`.

- [x] **Step 7: Commit**

```bash
git add server/src/schemas/alerts.ts server/src/routes/api/internal/dailyAlerts.ts server/src/container.ts server/src/app.ts \
  server/test/routes/dailyAlerts.test.ts
git commit -m "feat(server): expose the daily alert job behind CRON_SECRET

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: Vercel cron entry

**Files:**
- Modify: `server/vercel.json`
- Test: `server/test/vercelConfig.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/vercelConfig.test.ts`:
```ts
import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"

type VercelConfig = { crons?: Array<{ path: string; schedule: string }>; routes?: Array<{ src?: string; dest?: string }> }

const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8")) as VercelConfig

describe("vercel.json", () => {
  it("schedules the daily alert job after the US close on weekdays", () => {
    expect(config.crons).toEqual([{ path: "/api/internal/daily-alerts", schedule: "0 22 * * 1-5" }])
  })

  it("routes the cron path to the Fastify function", () => {
    const route = config.routes?.find((candidate) => candidate.src !== undefined && new RegExp(`^${candidate.src}$`).test("/api/internal/daily-alerts"))
    expect(route?.dest).toBe("src/server.ts")
  })
})
```

- [x] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/vercelConfig.test.ts`
Expected: FAIL. The first test sees `crons` as `undefined`. The second should already pass, because plan 04 routes `/api/(.*)` to `src/server.ts`.

- [x] **Step 3: Add the cron**

Run (from `server/`):
```bash
node -e 'const fs=require("fs");const p="vercel.json";const c=JSON.parse(fs.readFileSync(p,"utf8"));c.crons=[{path:"/api/internal/daily-alerts",schedule:"0 22 * * 1-5"}];fs.writeFileSync(p,JSON.stringify(c,null,2)+"\n")'
git diff vercel.json
```
Expected diff: only a top-level `"crons"` array was added. `builds` and `routes` are unchanged.

- [x] **Step 4: Run the test to verify it passes**

Run: `npx vitest run test/vercelConfig.test.ts`
Expected: PASS (`Tests  2 passed (2)`).

- [x] **Step 5: Commit**

```bash
git add server/vercel.json server/test/vercelConfig.test.ts
git commit -m "chore(server): schedule daily alerts with Vercel Cron (22:00 UTC weekdays)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: `scripts/send-test-push.ts`

**Files:**
- Create: `server/scripts/send-test-push.ts`
- Modify: `server/package.json` (add a script entry)

This is a thin CLI over modules that already have tests (`normalizeApnsKey`, `ApnsTokenProvider`, `buildPayload`, `Http2ApnsTransport`). It is verified by `npm run typecheck` now and by a real push in Task 24.

- [x] **Step 1: Write the script**

Create `server/scripts/send-test-push.ts`:
```ts
import { parseArgs } from "node:util"
import { config as loadEnv } from "dotenv"
import { ApnsTokenProvider } from "../src/apns/ApnsTokenProvider.js"
import { Http2ApnsTransport } from "../src/apns/Http2ApnsTransport.js"
import { buildPayload } from "../src/apns/payload.js"
import { parseLadderStatus } from "../src/domain/ladder.js"
import { systemClock } from "../src/lib/clock.js"

loadEnv({ path: ".env.development.local", quiet: true })
loadEnv({ path: ".env.local", override: true, quiet: true })

const { values } = parseArgs({
  options: {
    token: { type: "string" },
    env: { type: "string", default: "sandbox" },
    symbol: { type: "string", default: "AAPL" },
    status: { type: "string", default: "BUY_ZONE" },
    price: { type: "string", default: "172.10" },
  },
})

function requireEnv(name: string): string {
  const value = process.env[name]
  if (value === undefined || value === "") throw new Error(`${name} is not set (put it in server/.env.local)`)
  return value
}

const token = values.token
if (token === undefined || !/^[0-9a-f]{64,200}$/.test(token)) throw new Error("--token <lowercase hex APNs device token> is required")
const environment = (values.env ?? "sandbox") === "production" ? "production" : "sandbox"
const status = parseLadderStatus(values.status ?? "BUY_ZONE")
if (status === null) throw new Error(`Unknown --status ${String(values.status)}`)
const symbol = values.symbol ?? "AAPL"
const price = values.price ?? "172.10"

const tokens = new ApnsTokenProvider(
  { key: requireEnv("APNS_KEY"), keyId: requireEnv("APNS_KEY_ID"), teamId: requireEnv("APNS_TEAM_ID") },
  systemClock,
)
const payload = buildPayload({
  symbol,
  status,
  price,
  ladder: { buyLow: "150.00", buyHigh: "175.00", fair: "210.00", trim: "240.00", sell: "260.00" },
  temperature: null,
  tradingDate: new Date().toISOString().slice(0, 10),
})

const transport = new Http2ApnsTransport()
const response = await transport.send({
  environment,
  deviceToken: token,
  body: payload.body,
  headers: {
    authorization: `bearer ${tokens.token()}`,
    "apns-topic": process.env.APNS_TOPIC ?? "com.chenkai.wait",
    "apns-push-type": "alert",
    "apns-priority": "10",
    "apns-collapse-id": payload.collapseId,
  },
})
await transport.close()
console.log(JSON.stringify({ environment, ...response }))
process.exit(response.status === 200 ? 0 : 1)
```
Add to `server/package.json`'s `"scripts"`:
```json
"send-test-push": "tsx scripts/send-test-push.ts"
```

- [x] **Step 2: Typecheck and smoke-test the argument handling**

Run:
```bash
cd /Users/ckai/code/Wait/server && npm run typecheck
npm run send-test-push -- --token NOT-HEX; echo "exit=$?"
```
Expected: `tsc` exits 0. The second command fails before any network call with `Error: --token <lowercase hex APNs device token> is required`, followed by `exit=1`.

- [x] **Step 3: Commit**

```bash
git add server/scripts/send-test-push.ts server/package.json
git commit -m "chore(server): add send-test-push script for manual APNs checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 7: iOS: NotificationClient and device endpoints

Run every iOS command from the repo root, `/Users/ckai/code/Wait`, using plan 02's scripts:
- `scripts/test-waitkit.sh <TestTarget[/Suite]> …` runs package tests and prints only errors, failures and the summary.
- `scripts/build-app.sh [Wait|WaitWatch]` builds an app.

Source paths below are relative to `Wait/Packages/WaitKit/` unless they start with `Wait/` or `server/`.

### Task 19: `NotificationClient` target

**Files:**
- Modify: `Packages/WaitKit/Package.swift`
- Create: `Packages/WaitKit/Sources/NotificationClient/NotificationClient.swift`
- Create: `Packages/WaitKit/Sources/NotificationClient/NotificationPayload.swift`
- Create: `Packages/WaitKit/Sources/NotificationClient/NotificationClient+Live.swift`
- Test: `Packages/WaitKit/Tests/NotificationClientTests/NotificationPayloadTests.swift`

- [x] **Step 1: Declare the targets**

In `Package.swift`, add the following to `targets:`, next to the other client targets:
```swift
    .target(name: "NotificationClient", dependencies: ["Logging", .dependencies, .dependenciesMacros]),
```
and the following next to the other test targets:
```swift
    .testTarget(name: "NotificationClientTests", dependencies: ["NotificationClient"]),
```
`Logging` is used by the live delegate (plan 02's `Log.push` channel).

- [x] **Step 2: Write the failing test**

Create `Tests/NotificationClientTests/NotificationPayloadTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Testing
@testable import NotificationClient
#if os(iOS)
import UserNotifications
#endif

// MARK: - NotificationPayloadTests

@Suite
struct NotificationPayloadTests {
  @Test
  func readsTheSymbolKey() {
    #expect(NotificationPayload.symbol(from: ["symbol": "AAPL"]) == "AAPL")
  }

  @Test
  func uppercasesTheSymbol() {
    #expect(NotificationPayload.symbol(from: ["symbol": "brk.b"]) == "BRK.B")
  }

  @Test
  func acceptsEverySymbolTheAppCanOpen() {
    #expect(NotificationPayload.symbol(from: ["symbol": "0700.HK"]) == "0700.HK")
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://stock/600887.SS"]) == "600887.SS")
  }

  @Test
  func fallsBackToTheDeepLink() {
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://stock/MSFT"]) == "MSFT")
  }

  @Test
  func prefersTheSymbolKeyOverTheDeepLink() {
    #expect(NotificationPayload.symbol(from: ["symbol": "AAPL", "deepLink": "wait://stock/MSFT"]) == "AAPL")
  }

  @Test
  func rejectsForeignDeepLinks() {
    #expect(NotificationPayload.symbol(from: ["deepLink": "https://example.com/stock/MSFT"]) == nil)
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://settings/MSFT"]) == nil)
  }

  @Test
  func rejectsInvalidSymbols() {
    #expect(NotificationPayload.symbol(from: ["symbol": "NOT A SYMBOL"]) == nil)
    #expect(NotificationPayload.symbol(from: ["symbol": 42]) == nil)
    #expect(NotificationPayload.symbol(from: [:]) == nil)
  }

  #if os(iOS)
  @Test
  func mapsSystemAuthorizationStatuses() {
    #expect(NotificationAuthorization(UNAuthorizationStatus.notDetermined) == .notDetermined)
    #expect(NotificationAuthorization(UNAuthorizationStatus.denied) == .denied)
    #expect(NotificationAuthorization(UNAuthorizationStatus.authorized) == .authorized)
    #expect(NotificationAuthorization(UNAuthorizationStatus.provisional) == .provisional)
    #expect(NotificationAuthorization(UNAuthorizationStatus.ephemeral) == .ephemeral)
  }
  #endif
}
```

- [ ] **Step 3: Run the test to verify it fails** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh NotificationClientTests`
Expected: the build fails with `cannot find 'NotificationPayload' in scope` (or "no such module 'NotificationClient'").

- [x] **Step 4: Write the interface**

Create `Sources/NotificationClient/NotificationClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation

// MARK: - NotificationAuthorization

public enum NotificationAuthorization: String, Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral
}

// MARK: - NotificationClient

/// Local-notification permission, APNs registration and push taps.
@DependencyClient
public struct NotificationClient: Sendable {
  public var authorizationStatus: @Sendable () async -> NotificationAuthorization = { .notDetermined }
  public var requestAuthorization: @Sendable () async throws -> Bool
  public var registerForRemoteNotifications: @Sendable () async -> Void
  public var unregisterForRemoteNotifications: @Sendable () async -> Void
  /// Symbols of pushes the user tapped. Single consumer: subscribe once, at launch.
  public var tappedSymbols: @Sendable () -> AsyncStream<String> = { .finished }
}

// MARK: TestDependencyKey

extension NotificationClient: TestDependencyKey {
  public static let testValue = NotificationClient()
}

public extension DependencyValues {
  var notifications: NotificationClient {
    get { self[NotificationClient.self] }
    set { self[NotificationClient.self] = newValue }
  }
}
```

- [x] **Step 5: Write the payload parser**

Create `Sources/NotificationClient/NotificationPayload.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - NotificationPayload

/// Reads the stock symbol out of an alert push (`{"symbol": "AAPL", "deepLink": "wait://stock/AAPL", …}`, overview §8.7).
public enum NotificationPayload {
  // MARK: Public

  public static func symbol(from userInfo: [AnyHashable: Any]) -> String? {
    if let raw = userInfo["symbol"] as? String, let symbol = normalized(raw) {
      return symbol
    }
    guard
      let link = userInfo["deepLink"] as? String,
      let url = URL(string: link),
      url.scheme == "wait",
      url.host() == "stock",
      let raw = url.pathComponents.dropFirst().first
    else {
      return nil
    }
    return normalized(raw)
  }

  // MARK: Private

  /// Same rule as plan 02's `DeepLink` (`^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$`), so every symbol the app can open is accepted.
  private static func normalized(_ raw: String) -> String? {
    let symbol = raw.uppercased()
    return symbol.range(of: #"^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$"#, options: .regularExpression) == nil ? nil : symbol
  }
}
```

- [x] **Step 6: Write the live implementation**

Create `Sources/NotificationClient/NotificationClient+Live.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

#if os(iOS)
import Dependencies
import Logging
import UIKit
import UserNotifications

// MARK: - NotificationCenterDelegate

/// Receives taps and foreground presentations. Installed in `application(_:didFinishLaunchingWithOptions:)`
/// so cold-start taps are not lost; taps are buffered until `AppFeature` subscribes.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
  // MARK: Lifecycle

  override init() {
    let (stream, streamContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(8))
    taps = stream
    continuation = streamContinuation
    super.init()
  }

  // MARK: Internal

  static let shared = NotificationCenterDelegate()

  let taps: AsyncStream<String>

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard let symbol = NotificationPayload.symbol(from: response.notification.request.content.userInfo) else {
      Log.push.info("Ignoring a tapped push without a valid symbol")
      return
    }
    continuation.yield(symbol)
  }

  // MARK: Private

  private let continuation: AsyncStream<String>.Continuation
}

// MARK: - NotificationClient + DependencyKey

extension NotificationClient: DependencyKey {
  public static let liveValue = NotificationClient(
    authorizationStatus: {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      return NotificationAuthorization(settings.authorizationStatus)
    },
    requestAuthorization: {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    },
    registerForRemoteNotifications: {
      await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    },
    unregisterForRemoteNotifications: {
      await MainActor.run { UIApplication.shared.unregisterForRemoteNotifications() }
    },
    tappedSymbols: { NotificationCenterDelegate.shared.taps }
  )

  /// Call synchronously from `application(_:didFinishLaunchingWithOptions:)`.
  @MainActor
  public static func installDelegate() {
    UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
  }
}

// MARK: - NotificationAuthorization + UNAuthorizationStatus

extension NotificationAuthorization {
  init(_ status: UNAuthorizationStatus) {
    switch status {
      case .notDetermined:
        self = .notDetermined
      case .denied:
        self = .denied
      case .authorized:
        self = .authorized
      case .provisional:
        self = .provisional
      case .ephemeral:
        self = .ephemeral
      @unknown default:
        self = .notDetermined
    }
  }
}
#endif
```

- [ ] **Step 7: Run the test to verify it passes** — NOT RUN (code-only)

> Result (2026-11-23): `/tmp` harness on macOS (the real `NotificationPayload.swift` and test file, hand-written `NotificationClient` stand-in): 7 of 7 payload tests passed; the iOS-only `mapsSystemAuthorizationStatuses` was typechecked, not run. The live delegate file typechecks clean under `-swift-version 6` for `arm64-apple-ios17.0-simulator` (no `@preconcurrency` needed); `swiftlint`: 0 violations.

Run: `scripts/test-waitkit.sh NotificationClientTests`
Expected: `** TEST SUCCEEDED **` with 8 tests.
If Swift 6 reports that the delegate methods have a non-`Sendable` parameter crossing an isolation boundary, keep them `nonisolated` (the default for this class). Annotate the protocol conformance as `@preconcurrency UNUserNotificationCenterDelegate`. Don't make the class `@MainActor`, because `liveValue` must stay usable from any context.

- [x] **Step 8: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/NotificationClient Wait/Packages/WaitKit/Tests/NotificationClientTests
git commit -m "feat(waitkit): add NotificationClient for permission, APNs registration and taps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 20: Device registration endpoints in `APIClient`

**Files:**
- Create: `Packages/WaitKit/Sources/APIClient/DTOs/DeviceRegistrationDTO.swift`
- Modify: `Packages/WaitKit/Sources/APIClient/APIClient.swift`
- Test: `Packages/WaitKit/Tests/APIClientTests/DeviceEndpointTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/APIClientTests/DeviceEndpointTests.swift`. It uses its own `URLProtocol` stub, so it doesn't depend on plan 04's test helpers:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Foundation
import Testing
@testable import APIClient

// MARK: - DeviceStubProtocol

final class DeviceStubProtocol: URLProtocol, @unchecked Sendable {
  // MARK: Internal

  static let requests = LockIsolated<[(request: URLRequest, body: Data)]>([])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body = request.httpBodyStream.map(Self.readAll) ?? request.httpBody ?? Data()
    Self.requests.withValue { $0.append((request, body)) }
    let path = request.url?.path() ?? ""
    let (status, payload): (Int, Data) =
      if path == "/api/auth/register" {
        (200, Data(#"{"token":"jwt-1","user":{"id":"user-1"}}"#.utf8))
      } else if path.hasPrefix("/api/devices") {
        (204, Data())
      } else {
        (404, Data(#"{"error":{"code":"NOT_FOUND","message":"Route not found"}}"#.utf8))
      }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: payload)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  // MARK: Private

  private static func readAll(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

// MARK: - DeviceEndpointTests

@Suite(.serialized)
struct DeviceEndpointTests {
  // MARK: Internal

  @Test
  func hexEncodesTheDeviceToken() {
    #expect(APNsToken.hexString(Data([0x00, 0x0F, 0xDE, 0xAD])) == "000fdead")
  }

  @Test
  func usesTheSandboxInDebugBuilds() {
    #expect(DeviceRegistrationDTO.Environment.current == .sandbox)
  }

  @Test
  func encodesTheWireShape() throws {
    let dto = DeviceRegistrationDTO(token: "ab12", environment: .production)
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: String])
    #expect(json == ["token": "ab12", "environment": "production", "bundleId": "com.chenkai.wait"])
  }

  @Test
  func registerDevicePostsTheRegistration() async throws {
    DeviceStubProtocol.requests.setValue([])
    try await makeClient().registerDevice(DeviceRegistrationDTO(token: "ab12", environment: .sandbox))

    let (request, body) = try #require(DeviceStubProtocol.requests.value.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path() == "/api/devices")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-1")
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json == ["token": "ab12", "environment": "sandbox", "bundleId": "com.chenkai.wait"])
  }

  @Test
  func unregisterDeviceSendsADelete() async throws {
    DeviceStubProtocol.requests.setValue([])
    try await makeClient().unregisterDevice("ab12")

    let (request, _) = try #require(DeviceStubProtocol.requests.value.last)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path() == "/api/devices/ab12")
  }

  // MARK: Private

  private func makeClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeviceStubProtocol.self]
    let session = HTTPSession(
      baseURL: URL(string: "https://wait.test")!,
      session: URLSession(configuration: configuration),
      anonymousID: { UUID(uuidString: "00000000-0000-4000-8000-000000000001")! }
    )
    return APIClient.live(session: session)
  }
}
```
The two endpoint tests go through plan 04's real `HTTPSession`: register, then a JWT, then a 204 with an empty body. That covers the empty-response `post` overload and `delete` against 204s.

- [ ] **Step 2: Run the test to verify it fails**

Run: `scripts/test-waitkit.sh APIClientTests/DeviceEndpointTests`
Expected: the build fails with `cannot find 'APNsToken' in scope` and `value of type 'APIClient' has no member 'registerDevice'`.

- [ ] **Step 3: Write the DTO**

Create `Sources/APIClient/DTOs/DeviceRegistrationDTO.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DeviceRegistrationDTO

/// Body of `POST /api/devices` (overview §8.4).
public struct DeviceRegistrationDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(token: String, environment: Environment = .current, bundleId: String = "com.chenkai.wait") {
    self.token = token
    self.environment = environment
    self.bundleId = bundleId
  }

  // MARK: Public

  public enum Environment: String, Codable, Sendable {
    case sandbox
    case production

    /// Debug builds get sandbox APNs tokens; TestFlight and App Store builds get production tokens.
    public static var current: Environment {
      #if DEBUG
      return .sandbox
      #else
      return .production
      #endif
    }
  }

  public let token: String
  public let environment: Environment
  public let bundleId: String
}

// MARK: - APNsToken

public enum APNsToken {
  /// Lowercase hex, the format the server validates (`^[0-9a-f]{64,200}$`).
  public static func hexString(_ deviceToken: Data) -> String {
    deviceToken.map { String(format: "%02x", $0) }.joined()
  }
}
```

- [ ] **Step 4: Add the endpoints**

Plan 04's `HTTPSession` already has the two primitives this needs, so it isn't changed:
- `post<Body>(_ path:, body:) async throws`, the no-response overload documented "For endpoints that answer 204". It sends the body and ignores the empty response.
- `delete(_ path:) async throws`.

Both run the register-and-retry-on-401 flow and throw `APIError` for any non-2xx response.

In `Sources/APIClient/APIClient.swift`, make three changes.

1. Add the two properties to `public struct APIClient`, after the existing endpoints:
```swift
  public var registerDevice: @Sendable (_ registration: DeviceRegistrationDTO) async throws -> Void
  public var unregisterDevice: @Sendable (_ token: String) async throws -> Void
```
2. In `public static func live(session: HTTPSession) -> APIClient`, add these arguments after the existing ones (plan 04's `deleteAccount`, plus plan 05's sync endpoint if present):
```swift
      registerDevice: { registration in
        try await session.post("/api/devices", body: registration)
      },
      unregisterDevice: { token in
        try await session.delete("/api/devices/\(token)")
      }
```
The closure's `Void` return type selects the no-response `post` overload.
3. In `static let misconfigured = APIClient(...)`, add:
```swift
    registerDevice: { _ in throw APIError.misconfigured },
    unregisterDevice: { _ in throw APIError.misconfigured }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `scripts/test-waitkit.sh APIClientTests`
Expected: `** TEST SUCCEEDED **`, with the 5 new tests and the existing plan 04/05 `APIClientTests` all passing.

- [ ] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/APIClient Wait/Packages/WaitKit/Tests/APIClientTests/DeviceEndpointTests.swift
git commit -m "feat(waitkit): add device registration endpoints to APIClient

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 8: iOS: PushFeature and the Settings toggle

Run iOS commands from `/Users/ckai/code/Wait` with `scripts/test-waitkit.sh` and `scripts/build-app.sh` (see the Chunk 7 intro).

### Task 21: `PushFeature`, wired into `AppFeature` and `AppDelegate`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (dependencies of `AppFeature` and `AppFeatureTests`)
- Modify: `Wait/Packages/WaitKit/Sources/Persistence/SharedKeys.swift`
- Create: `Wait/Packages/WaitKit/Sources/AppFeature/PushFeature.swift`
- Modify: `Wait/Packages/WaitKit/Sources/AppFeature/AppDelegateAction.swift`
- Modify: `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`
- Modify: `Wait/Packages/WaitKit/Sources/AppFeature/AppDelegate.swift`
- Test: `Wait/Packages/WaitKit/Tests/AppFeatureTests/PushFeatureTests.swift`
- Test: `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeaturePushRoutingTests.swift`

- [ ] **Step 1: Add the dependencies and the shared keys**

In `Package.swift`:
- Add `"NotificationClient"` and `"APIClient"` to the `AppFeature` target's `dependencies`, skipping any it already has.
- Make the `AppFeatureTests` target's `dependencies` include all of `"AppFeature"`, `.tca`, `.dependenciesTestSupport`, `"NotificationClient"`, `"APIClient"`, `"Persistence"`, `"Connectivity"` and `"SyncClient"`. Keep what plans 02–05 listed and add the missing ones.

Append to `Sources/Persistence/SharedKeys.swift`:
```swift
// MARK: - Alerts (plan 06)
// Declared once, on `SharedReaderKey`, like `.watchlist` and `.syncState`, so `@Shared(.alertsEnabled)` isn't ambiguous.

/// `@Shared(.alertsEnabled)`: the user turned on "Daily alerts" in Settings.
public extension SharedReaderKey where Self == AppStorageKey<Bool>.Default {
  static var alertsEnabled: Self {
    Self[.appStorage("alerts.enabled"), default: false]
  }
}

/// `@Shared(.apnsDeviceToken)`: the APNs token (lowercase hex) last sent to `POST /api/devices`. Cleared only after the server confirms the DELETE.
public extension SharedReaderKey where Self == AppStorageKey<String?> {
  static var apnsDeviceToken: Self {
    .appStorage("apns.deviceToken")
  }
}
```

- [ ] **Step 2: Write the failing `PushFeature` test**

Create `Tests/AppFeatureTests/PushFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import NotificationClient
import Testing
@testable import AppFeature

// MARK: - PushFeatureTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "PushFeatureTests.\(UUID().uuidString)")! })
struct PushFeatureTests {
  // MARK: Internal

  @Test
  func launchRegistersWhenAlertsAreEnabledAndAuthorized() async {
    let registrations = LockIsolated(0)
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.notifications.registerForRemoteNotifications = { registrations.withValue { $0 += 1 } }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
    #expect(registrations.value == 1)
  }

  @Test
  func launchDoesNotRegisterWhenAlertsAreOff() async {
    let store = TestStore(initialState: state(alertsEnabled: false)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
  }

  @Test
  func launchDoesNotRegisterWhenPermissionWasDenied() async {
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .denied }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .denied)
    await store.finish()
  }

  @Test
  func launchRetriesAPendingUnregistration() async {
    let deletions = LockIsolated<[String]>([])
    let store = TestStore(initialState: state(alertsEnabled: false, deviceToken: "abc123")) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.apiClient.unregisterDevice = { token in deletions.withValue { $0.append(token) } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.launched)
    await store.receive(\.staleTokenRemoved) { $0.$deviceToken.withLock { $0 = nil } }
    await store.finish()
    #expect(deletions.value == ["abc123"])
  }

  @Test
  func pendingUnregistrationFailureKeepsTheToken() async {
    struct Offline: Error {}
    let store = TestStore(initialState: state(alertsEnabled: false, deviceToken: "abc123")) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.apiClient.unregisterDevice = { _ in throw Offline() }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
    #expect(store.state.deviceToken == "abc123")
  }

  @Test
  func tapAsksTheParentToOpenTheStock() async {
    let store = TestStore(initialState: state(alertsEnabled: false)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = {
        AsyncStream { continuation in
          continuation.yield("AAPL")
          continuation.finish()
        }
      }
      $0.notifications.authorizationStatus = { .notDetermined }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.launched)
    await store.receive(\.delegate.openStock, "AAPL")
    await store.finish()
  }

  @Test
  func registeredTokenIsStoredAndUploaded() async {
    let uploads = LockIsolated<[DeviceRegistrationDTO]>([])
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.apiClient.registerDevice = { registration in uploads.withValue { $0.append(registration) } }
    }

    await store.send(.registered(Data([0xDE, 0xAD, 0xBE, 0xEF]))) {
      $0.$deviceToken.withLock { $0 = "deadbeef" }
    }
    await store.finish()
    #expect(uploads.value == [DeviceRegistrationDTO(token: "deadbeef", environment: .sandbox, bundleId: "com.chenkai.wait")])
  }

  @Test
  func uploadFailureKeepsTheTokenForTheNextLaunch() async {
    struct Offline: Error {}
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.apiClient.registerDevice = { _ in throw Offline() }
    }

    await store.send(.registered(Data([0x01]))) {
      $0.$deviceToken.withLock { $0 = "01" }
    }
    await store.finish()
  }

  @Test
  func registrationFailureChangesNothing() async {
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() }
    await store.send(.registrationFailed("no valid aps-environment entitlement"))
  }

  // MARK: Private

  private func state(alertsEnabled: Bool, deviceToken: String? = nil) -> PushFeature.State {
    let state = PushFeature.State()
    state.$alertsEnabled.withLock { $0 = alertsEnabled }
    state.$deviceToken.withLock { $0 = deviceToken }
    return state
  }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `scripts/test-waitkit.sh AppFeatureTests/PushFeatureTests`
Expected: the build fails with `cannot find 'PushFeature' in scope`.

- [ ] **Step 4: Implement `PushFeature`**

Create `Sources/AppFeature/PushFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Foundation
import Logging
import NotificationClient
import Persistence

// MARK: - PushFeature

/// Remote-notification plumbing:
/// - At launch, registers with APNs when alerts are on and allowed, and finishes a pending device unregistration when they're off.
/// - Uploads the device token APNs hands back.
/// - Turns push taps into `delegate(.openStock)`.
@Reducer
public struct PushFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    @Shared(.alertsEnabled) public var alertsEnabled
    @Shared(.apnsDeviceToken) public var deviceToken
  }

  public enum Action: Equatable, Sendable {
    case launched
    case authorizationLoaded(NotificationAuthorization)
    case registered(Data)
    case registrationFailed(String)
    case staleTokenRemoved
    case tapped(String)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case openStock(String)
    }
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .launched:
          let pendingUnregistration = state.alertsEnabled ? nil : state.deviceToken
          return .merge(
            .run { [notifications] send in
              for await symbol in notifications.tappedSymbols() {
                await send(.tapped(symbol))
              }
            }
            .cancellable(id: CancelID.taps, cancelInFlight: true),
            .run { [notifications] send in
              await send(.authorizationLoaded(notifications.authorizationStatus()))
            },
            .run { [apiClient] send in
              guard let token = pendingUnregistration else { return }
              do {
                try await apiClient.unregisterDevice(token)
                await send(.staleTokenRemoved)
              } catch {
                Log.push.error("Pending device unregistration failed, will retry next launch: \(error)")
              }
            }
          )

        case let .authorizationLoaded(status):
          guard state.alertsEnabled, status == .authorized else {
            return .none
          }
          return .run { [notifications] _ in
            await notifications.registerForRemoteNotifications()
          }

        case let .registered(deviceToken):
          let token = APNsToken.hexString(deviceToken)
          state.$deviceToken.withLock { $0 = token }
          return .run { [apiClient] _ in
            try await apiClient.registerDevice(DeviceRegistrationDTO(token: token))
          } catch: { error, _ in
            Log.push.error("Device registration upload failed: \(error)")
          }

        case let .registrationFailed(message):
          Log.push.error("APNs registration failed: \(message)")
          return .none

        case .staleTokenRemoved:
          state.$deviceToken.withLock { $0 = nil }
          return .none

        case let .tapped(symbol):
          return .send(.delegate(.openStock(symbol)))

        case .delegate:
          return .none
      }
    }
  }

  // MARK: Internal

  enum CancelID {
    case taps
  }

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.notifications) var notifications
}
```

- [ ] **Step 5: Run the `PushFeature` test to verify it passes**

Run: `scripts/test-waitkit.sh AppFeatureTests/PushFeatureTests`
Expected: `** TEST SUCCEEDED **` (9 tests).

- [ ] **Step 6: Write the failing routing test**

Create `Tests/AppFeatureTests/AppFeaturePushRoutingTests.swift`. It stubs the plan 03 and 05 clients that `AppFeature` effects touch:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Foundation
import SyncClient
import Testing
@testable import AppFeature

// MARK: - AppFeaturePushRoutingTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "AppFeaturePushRoutingTests.\(UUID().uuidString)")! })
struct AppFeaturePushRoutingTests {
  @Test
  func forwardsTheDeviceTokenToPushFeature() async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.apiClient.registerDevice = { _ in }
      $0.connectivity = .noop
      $0.syncClient.sync = { SyncReport() }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.appDelegate(.didRegisterForRemoteNotifications(Data([0x01, 0x02]))))
    await store.finish()
    #expect(store.state.push.deviceToken == "0102")
  }

  @Test
  func openStockDelegateOpensTheDeepLink() async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.connectivity = .noop
      $0.syncClient.sync = { SyncReport() }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.push(.delegate(.openStock("AAPL"))))
    await store.receive(\.openURL, URL(string: "wait://stock/AAPL")!)
    await store.skipInFlightEffects()
  }
}
```

- [ ] **Step 7: Run the routing test to verify it fails**

Run: `scripts/test-waitkit.sh AppFeatureTests/AppFeaturePushRoutingTests`
Expected: the build fails with `type 'AppDelegateAction' has no member 'didRegisterForRemoteNotifications'` and `value of type 'AppFeature.State' has no member 'push'`.

- [ ] **Step 8: Wire `PushFeature` into `AppFeature` and `AppDelegate`**

In `Sources/AppFeature/AppDelegateAction.swift`, add two cases (overview §12.3). Add `import Foundation` if it's missing.
```swift
  case didRegisterForRemoteNotifications(Data)
  case didFailToRegisterForRemoteNotifications(String)
```

In `Sources/AppFeature/AppFeature.swift`, make these changes:
1. In `State`, add `public var push = PushFeature.State()`.
2. In `Action`, add `case push(PushFeature.Action)`.
3. In `body`, add `Scope(state: \.push, action: \.push) { PushFeature() }` next to the other `Scope`s. Keep it inside any `CombineReducers` that plans 02/05 added for `onChange` (overview §12.3).
4. In `case .appDelegate(.didFinishLaunching):`, wrap the current return value `X`, so the case returns:
   ```swift
   .merge(X, PushFeature().reduce(into: &state.push, action: .launched).map(Action.push))
   ```
   Plan 03 made `X` the connectivity-activation effect.
5. Add these cases to the reducer's `switch`, before any catch-all:
```swift
        case let .appDelegate(.didRegisterForRemoteNotifications(deviceToken)):
          return PushFeature().reduce(into: &state.push, action: .registered(deviceToken)).map(Action.push)

        case let .appDelegate(.didFailToRegisterForRemoteNotifications(message)):
          return PushFeature().reduce(into: &state.push, action: .registrationFailed(message)).map(Action.push)

        case let .push(.delegate(.openStock(symbol))):
          guard let url = URL(string: "wait://stock/\(symbol)") else {
            return .none
          }
          return .send(.openURL(url))

        case .push:
          return .none
```

In `Sources/AppFeature/AppDelegate.swift` (inside its `#if os(iOS)` block):
- Add `import NotificationClient` next to the other imports.
- Make `application(_:didFinishLaunchingWithOptions:)` install the delegate before it sends `.didFinishLaunching`, keeping everything else plans 02–05 put there.
- Add the two APNs callbacks.
```swift
    public func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      NotificationClient.installDelegate()
      store.send(.appDelegate(.didFinishLaunching))
      return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
      store.send(.appDelegate(.didRegisterForRemoteNotifications(deviceToken)))
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
      store.send(.appDelegate(.didFailToRegisterForRemoteNotifications(error.localizedDescription)))
    }
```

- [ ] **Step 9: Run the AppFeature tests to verify they pass**

Run: `scripts/test-waitkit.sh AppFeatureTests`
Expected: `** TEST SUCCEEDED **`, with every existing `AppFeatureTests` test and the 11 new ones passing.
If an existing exhaustive test that sends `.appDelegate(.didFinishLaunching)` now reports an unhandled `.push(.authorizationLoaded(.notDetermined))`, do two things in that test only:
- add `$0.notifications.tappedSymbols = { .finished }` to its `withDependencies`
- add `await store.receive(\.push.authorizationLoaded, .notDetermined)` after the send

The default `authorizationStatus` returns `.notDetermined`.

- [ ] **Step 10: Build the app**

Run: `cd /Users/ckai/code/Wait/Wait && xcodegen generate && cd .. && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Persistence/SharedKeys.swift Wait/Packages/WaitKit/Sources/AppFeature \
  Wait/Packages/WaitKit/Tests/AppFeatureTests Wait/Wait.xcodeproj
git commit -m "feat(app): register for pushes at launch and open the stock on tap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 22: Settings "Daily alerts" section

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (dependencies of `SettingsFeature` and `SettingsFeatureTests`)
- Modify: `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`
- Create: `Wait/Packages/WaitKit/Sources/SettingsFeature/AlertsSection.swift`
- Modify: `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`
- Test: `Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsAlertsTests.swift`

Load `swiftui-expert:swiftui-expert-skill` before Step 5.

- [ ] **Step 1: Add the dependencies**

In `Package.swift`:
- Add `"NotificationClient"`, `"Persistence"` and `"Logging"` to the `SettingsFeature` target's `dependencies`, skipping any it already has. `"APIClient"` and `"SyncClient"` came with plans 04 and 05.
- Make `SettingsFeatureTests` include `.tca`, `.dependenciesTestSupport`, `"NotificationClient"` and `"APIClient"` (which also provides `\.identity`).

- [ ] **Step 2: Write the failing test**

Create `Tests/SettingsFeatureTests/SettingsAlertsTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import NotificationClient
import Testing
@testable import SettingsFeature

// MARK: - SettingsAlertsTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "SettingsAlertsTests.\(UUID().uuidString)")! })
struct SettingsAlertsTests {
  // MARK: Internal

  @Test
  func enablingAlertsRequestsPermissionThenRegisters() async {
    let registrations = LockIsolated(0)
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { true }
      $0.notifications.authorizationStatus = { .authorized }
      $0.notifications.registerForRemoteNotifications = { registrations.withValue { $0 += 1 } }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .authorized) { $0.authorizationStatus = .authorized }
    await store.receive(\.alertsEnablementFinished, true) { $0.$alertsEnabled.withLock { $0 = true } }
    await store.finish()
    #expect(registrations.value == 1)
  }

  @Test
  func deniedPermissionLeavesAlertsOffAndOffersSystemSettings() async {
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { false }
      $0.notifications.authorizationStatus = { .denied }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .denied) { $0.authorizationStatus = .denied }
    await store.receive(\.alertsEnablementFinished, false)
    await store.finish()
    #expect(store.state.showsOpenSystemSettings)
  }

  @Test
  func permissionErrorCountsAsDenied() async {
    struct Failure: Error {}
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { throw Failure() }
      $0.notifications.authorizationStatus = { .notDetermined }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .notDetermined)
    await store.receive(\.alertsEnablementFinished, false)
    await store.finish()
  }

  @Test
  func disablingAlertsUnregistersAndClearsTheTokenOnlyAfterTheServerConfirms() async {
    let systemUnregistrations = LockIsolated(0)
    let serverUnregistrations = LockIsolated<[String]>([])
    let store = TestStore(initialState: enabledState(token: "abc123")) { SettingsFeature() } withDependencies: {
      $0.notifications.unregisterForRemoteNotifications = { systemUnregistrations.withValue { $0 += 1 } }
      $0.apiClient.unregisterDevice = { token in serverUnregistrations.withValue { $0.append(token) } }
    }

    await store.send(.alertsToggled(false)) { $0.$alertsEnabled.withLock { $0 = false } }
    await store.receive(\.deviceUnregistered) { $0.$apnsDeviceToken.withLock { $0 = nil } }
    await store.finish()
    #expect(systemUnregistrations.value == 1)
    #expect(serverUnregistrations.value == ["abc123"])
  }

  @Test
  func failedServerUnregistrationKeepsTheTokenForTheLaunchRetry() async {
    struct Offline: Error {}
    let store = TestStore(initialState: enabledState(token: "abc123")) { SettingsFeature() } withDependencies: {
      $0.notifications.unregisterForRemoteNotifications = {}
      $0.apiClient.unregisterDevice = { _ in throw Offline() }
    }

    await store.send(.alertsToggled(false)) { $0.$alertsEnabled.withLock { $0 = false } }
    await store.finish()
    #expect(store.state.apnsDeviceToken == "abc123")
  }

  @Test
  func openSystemSettingsUsesTheAppSettingsURL() async {
    let opened = LockIsolated<URL?>(nil)
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.openURL = OpenURLEffect { url in
        opened.setValue(url)
        return true
      }
    }

    await store.send(.openSystemSettingsTapped)
    await store.finish()
    #expect(opened.value == URL(string: "app-settings:"))
  }

  @Test
  func taskLoadsTheAuthorizationStatus() async {
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.authorizationStatus = { .authorized }
      $0.identity.anonymousID = { UUID() } // plan 04's `.task` loads the account id
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.task)
    await store.receive(\.authorizationStatusLoaded, .authorized) { $0.authorizationStatus = .authorized }
    await store.skipInFlightEffects()
  }

  // MARK: Private

  private func enabledState(token: String) -> SettingsFeature.State {
    let state = SettingsFeature.State()
    state.$alertsEnabled.withLock { $0 = true }
    state.$apnsDeviceToken.withLock { $0 = token }
    return state
  }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `scripts/test-waitkit.sh SettingsFeatureTests/SettingsAlertsTests`
Expected: the build fails with `type 'SettingsFeature.Action' has no member 'alertsToggled'`.

- [ ] **Step 4: Extend `SettingsFeature`**

In `Sources/SettingsFeature/SettingsFeature.swift`, make the following changes.

1. Add the imports `Logging`, `NotificationClient` and `Persistence`.
2. Add to `State`:
```swift
    @Shared(.alertsEnabled) public var alertsEnabled
    @Shared(.apnsDeviceToken) public var apnsDeviceToken
    public var authorizationStatus: NotificationAuthorization = .notDetermined

    public var showsOpenSystemSettings: Bool {
      authorizationStatus == .denied
    }
```
3. Add to `Action`:
```swift
    case alertsToggled(Bool)
    case authorizationStatusLoaded(NotificationAuthorization)
    case alertsEnablementFinished(granted: Bool)
    case deviceUnregistered
    case openSystemSettingsTapped
```
4. Add dependencies next to the existing ones, keeping plan 04's `apiClient`:
```swift
  @Dependency(\.notifications) var notifications
  @Dependency(\.openURL) var openURL
```
5. Add the constant inside `SettingsFeature`:
```swift
  /// The value of `UIApplication.openSettingsURLString`, written out so the reducer doesn't touch main-actor UIKit API.
  static let systemSettingsURL = URL(string: "app-settings:")!
```
6. In the existing `case .task:`, wrap the current return value `X` as `.merge(X, loadAuthorizationStatus())`. Add this method to the reducer:
```swift
  private func loadAuthorizationStatus() -> Effect<Action> {
    .run { [notifications] send in
      await send(.authorizationStatusLoaded(notifications.authorizationStatus()))
    }
  }
```
7. Add these cases to the reducer's `switch`, before any catch-all:
```swift
        case .alertsToggled(true):
          return .run { [notifications] send in
            let granted = (try? await notifications.requestAuthorization()) ?? false
            await send(.authorizationStatusLoaded(notifications.authorizationStatus()))
            await send(.alertsEnablementFinished(granted: granted))
            if granted {
              await notifications.registerForRemoteNotifications()
            }
          }

        case .alertsToggled(false):
          // Keep the token until the server confirms the DELETE; PushFeature retries a pending unregistration at launch.
          let token = state.apnsDeviceToken
          state.$alertsEnabled.withLock { $0 = false }
          return .run { [notifications, apiClient] send in
            await notifications.unregisterForRemoteNotifications()
            guard let token else { return }
            do {
              try await apiClient.unregisterDevice(token)
              await send(.deviceUnregistered)
            } catch {
              Log.push.error("Device unregistration failed, will retry next launch: \(error)")
            }
          }

        case let .alertsEnablementFinished(granted):
          state.$alertsEnabled.withLock { $0 = granted }
          return .none

        case .deviceUnregistered:
          state.$apnsDeviceToken.withLock { $0 = nil }
          return .none

        case let .authorizationStatusLoaded(status):
          state.authorizationStatus = status
          return .none

        case .openSystemSettingsTapped:
          return .run { [openURL] _ in
            await openURL(SettingsFeature.systemSettingsURL)
          }
```
The device token itself is uploaded by `PushFeature` when APNs calls back (Task 21).

- [ ] **Step 5: Write the view**

Create `Sources/SettingsFeature/AlertsSection.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - AlertsSection

struct AlertsSection: View {
  // MARK: Internal

  let store: StoreOf<SettingsFeature>

  var body: some View {
    Section {
      Toggle("Daily alerts", isOn: alertsBinding)
      if store.showsOpenSystemSettings {
        VStack(alignment: .leading, spacing: 4) {
          Text("Notifications are turned off for Wait.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Open Settings") {
            store.send(.openSystemSettingsTapped)
          }
        }
      }
    } header: {
      Text("Alerts")
    } footer: {
      Text("After the US close on trading days, Wait checks each stock's ladder and notifies you when the price drops into a buy zone or rises to trim or sell.")
    }
  }

  // MARK: Private

  private var alertsBinding: Binding<Bool> {
    Binding(
      get: { store.alertsEnabled },
      set: { store.send(.alertsToggled($0)) }
    )
  }
}
```
In `Sources/SettingsFeature/SettingsView.swift`, add `AlertsSection(store: store)` inside the settings `Form`/`List`, after plan 05's sync section and before the attribution footer.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `scripts/test-waitkit.sh SettingsFeatureTests`
Expected: `** TEST SUCCEEDED **`, with every existing `SettingsFeatureTests` test and the 7 new ones passing.
If an existing exhaustive test that sends `.task` now reports an unhandled `.authorizationStatusLoaded(.notDetermined)`, add `await store.receive(\.authorizationStatusLoaded, .notDetermined)` to it. The default `authorizationStatus` returns `.notDetermined`. Those tests already stub `\.identity` for plan 04's account load, so no other change is needed.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/SettingsFeature Wait/Packages/WaitKit/Tests/SettingsFeatureTests
git commit -m "feat(settings): add Daily alerts toggle with permission handling

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 9: Entitlements, end-to-end, docs

### Task 23: Push entitlement and full verification

**Files:**
- Verify (modify only if needed): `Wait/project.yml`, `Wait/Wait/Wait.entitlements`, `Wait/Wait/WaitRelease.entitlements`

- [ ] **Step 1: Check the entitlement**

Run:
```bash
cd /Users/ckai/code/Wait/Wait
grep -n "aps-environment" project.yml
/usr/libexec/PlistBuddy -c "Print :aps-environment" Wait/Wait.entitlements
/usr/libexec/PlistBuddy -c "Print :aps-environment" Wait/WaitRelease.entitlements
```
Expected: each `PlistBuddy` call prints `development`. Keep `development` for Release too: when you export for TestFlight or the App Store, Xcode re-signs with `production` from the distribution profile.

If `project.yml` declares the app's entitlements with `properties:`, XcodeGen rewrites the files from those properties on every `xcodegen generate`. So if the key is missing there, add `aps-environment: development` under the app target's `entitlements.properties` in `project.yml`, not in the plist. Otherwise add it to the file:
```bash
/usr/libexec/PlistBuddy -c "Add :aps-environment string development" Wait/Wait.entitlements
```

- [ ] **Step 2: (manual: user) Confirm the App ID has the Push Notifications capability**

1. Go to https://developer.apple.com/account/resources/identifiers/list and open `com.chenkai.wait`.
2. Check that **Push Notifications** is ticked. If it isn't, tick it and click **Save**.

Xcode's automatic signing usually enables it once `aps-environment` is in the entitlements. Without it, a device build fails `registerForRemoteNotifications` with "no valid aps-environment entitlement string found", which reaches `PushFeature.registrationFailed`.

- [ ] **Step 3: Regenerate and build both apps**

Run:
```bash
cd /Users/ckai/code/Wait/Wait && xcodegen generate
cd /Users/ckai/code/Wait && scripts/build-app.sh && scripts/build-app.sh WaitWatch
```
Expected: both print `** BUILD SUCCEEDED **`, and `git status` shows `Package.resolved` unchanged.

- [ ] **Step 4: Run every suite**

Run:
```bash
cd /Users/ckai/code/Wait && scripts/test-waitkit.sh
cd /Users/ckai/code/Wait/server && npm run typecheck && npm test
```
Expected: `** TEST SUCCEEDED **`, `tsc` exits 0, and vitest reports every file passed.

- [ ] **Step 5: Commit (only if Step 1 changed anything)**

```bash
cd /Users/ckai/code/Wait
git add Wait/project.yml Wait/Wait/Wait.entitlements Wait/Wait/WaitRelease.entitlements Wait/Wait.xcodeproj
git commit -m "chore(app): keep aps-environment entitlement for push alerts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 24: Deploy and end-to-end check (manual: user)

**Files:** none

The executor prints each instruction and waits for the user to confirm it.

- [ ] **Step 1: (manual: user) Set the production env vars**

Run from `server/`, pasting each value when `vercel` prompts:
```bash
for target in production preview; do
  vercel env add MASSIVE_API_KEY "$target"
  vercel env add CRON_SECRET "$target"
  vercel env add APNS_KEY "$target"        # base64 of AuthKey_<KEYID>.p8
  vercel env add APNS_KEY_ID "$target"
  vercel env add APNS_TEAM_ID "$target"    # 5WDN96EM72
done
```
Set them for **Preview** as well as Production. `loadConfig` fails fast at cold start, so a preview deploy without them returns 500 on every route. `MASSIVE_BASE_URL` and `APNS_TOPIC` have defaults, so add them only to override them.

- [ ] **Step 2: Apply migration 004 to production**

Follow plan 04's convention: `scripts/migrate.ts` reads `.env.development.local`, then `.env.local` with override, so the production URL must be in `.env.local`. Don't pass `DATABASE_URL` on the command line; `.env.local` would override it.
```bash
cd /Users/ckai/code/Wait/server
vercel env pull .env.local --environment=production   # gitignored; never print its values
npm run migrate
```
Expected: `migrations applied: [4] skipped: [1, 2, 3]`. A second `npm run migrate` prints `migrations applied: [] skipped: [1, 2, 3, 4]`.

- [ ] **Step 3: (manual: user) Deploy**

Deploy the way plan 04 does it (`vercel --prod` from `server/`, or merging to the deploy branch). Then:
```bash
export WAIT_API_BASE_URL=https://<your-vercel-host>
curl -sS "$WAIT_API_BASE_URL/health"
curl -sS -o /dev/null -w "%{http_code}\n" "$WAIT_API_BASE_URL/api/internal/daily-alerts"
```
Expected: `{"status":"ok",…}`, then `401` (no secret).

- [ ] **Step 4: Check tap handling on the simulator (no APNs involved)**

Write the payload file:
```bash
cat > /tmp/wait-push.apns <<'JSON'
{"Simulator Target Bundle":"com.chenkai.wait","aps":{"alert":{"title":"AAPL · BUY ZONE","body":"Closed $172.10, at or below buy-high $175.00 · 28°"},"sound":"default","thread-id":"AAPL"},"symbol":"AAPL","status":"BUY_ZONE","deepLink":"wait://stock/AAPL"}
JSON
```
Run the app on the iPhone 17 simulator from Xcode, background it, then:
```bash
xcrun simctl push booted com.chenkai.wait /tmp/wait-push.apns
```
Expected: a banner appears. Tapping it opens Wait on AAPL's details. The watchlist must contain AAPL; otherwise the deep link is ignored, as plan 02 designed.

- [ ] **Step 5: (manual: user) Register a real device**

1. Run the Debug build on a physical iPhone (Debug uses sandbox APNs).
2. In Settings, turn on **Daily alerts**, then tap **Allow**.
3. In the Neon SQL console, run:
   ```sql
   SELECT token, environment, user_id FROM device_tokens ORDER BY updated_at DESC LIMIT 5;
   ```
   Expected: one row, with environment `sandbox`.

- [ ] **Step 6: (manual: user) Send a test push**

Run from `server/`, using the token from Step 5:
```bash
npm run send-test-push -- --token <hex token> --env sandbox --symbol AAPL
```
Expected: `{"environment":"sandbox","status":200,…}`, and the push arrives on the phone. Tapping it opens AAPL.

- [ ] **Step 7: (manual: user) Run the job and force one transition**

Seed today's statuses:
```bash
curl -sS -H "Authorization: Bearer $CRON_SECRET" "$WAIT_API_BASE_URL/api/internal/daily-alerts"
```
Expected on a weekday after 22:00 UTC: `"status":"completed"`. On a weekend you get `"skipped"`, and on a market holiday `"holiday"`.

To force a push, pick a stock in the app whose last close is at or below its buy-high, and make it look as if it was in WATCH yesterday. In the Neon SQL console:
```sql
UPDATE watchlist_items SET last_status = 'WATCH' WHERE symbol = 'AAPL' AND user_id = '<your user id>';
DELETE FROM alert_job_runs WHERE trading_date = '<today, YYYY-MM-DD in New York>';
```
Run the `curl` again.
Expected: `"transitions":1,"alertsCreated":1,"alertsSent":1`, and a "BUY ZONE" push arrives.

- [ ] **Step 8: Confirm the same-day rerun is silent**

Run the same `curl` once more.
Expected: `"status":"resent","alertsSent":0`, and no new push.

- [ ] **Step 9: (manual: user) Confirm the cron schedule**

In the Vercel dashboard, open the project → **Settings → Cron Jobs**.
Expected: `/api/internal/daily-alerts` is listed with schedule `0 22 * * 1-5`.

No commit for this task.

---

### Task 25: Documentation

**Files:**
- Modify: `/Users/ckai/code/Wait/CLAUDE.md`
- Modify: `/Users/ckai/code/Wait/server/README.md`
- Modify: `/Users/ckai/code/Wait/Wait/Packages/WaitKit/README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Append this section after the data-flow sections that plan 05 left:
```markdown
### Daily ladder alerts (plan 06)

- **Trigger:** Vercel Cron `0 22 * * 1-5` (UTC) calls `GET /api/internal/daily-alerts` with `Authorization: Bearer $CRON_SECRET`.
- **Job:** `server/src/services/AlertJobService.ts` follows overview §8.6:
  1. Gets closes from `DailyCloseResolver`: one Massive grouped-daily call; an SPY date check marks holidays; Finnhub fills in at most 25 missing symbols.
  2. Classifies each live item with `domain/ladder.ts`.
  3. Inserts `alert_events` (ON CONFLICT DO NOTHING).
  4. Updates the server-owned `watchlist_items.last_status`, which never bumps the sync version.
  5. Sends pending events through `apns/ApnsSender.ts`.
  Reruns on the same trading day only resend events that are still pending.
- **Alert rule:** push only when moving *down* into BUY_ZONE/DEEP_BUY or *up* into TRIM/SELL (`shouldAlert`). A stock's first evaluation is stored without a push. Changing a stock's anchors resets `last_status` to NULL, so the next evaluation is again stored without a push. A close that moved more than 50% (likely a split) never pushes.
- **iOS:**
  - `NotificationClient` handles permission, APNs registration and taps.
  - `AppFeature`'s child `PushFeature` registers at launch when `@Shared(.alertsEnabled)` is on and permission was granted. It uploads the hex token to `POST /api/devices`.
  - When alerts are off but a token is still stored, launch retries the `DELETE /api/devices/:token` that Settings started.
  - Taps become `wait://stock/<SYMBOL>`.
  - Settings → Alerts holds the toggle.
- **Manual checks:**
  - `xcrun simctl push booted com.chenkai.wait /tmp/wait-push.apns` tests tap handling without APNs.
  - `cd server && npm run send-test-push -- --token <hex> --env sandbox` sends a real push.
```

- [ ] **Step 2: Update `server/README.md`**

First, replace plan 04's stale `## Environment` line, `See .env.example. Required: DATABASE_URL, … Optional: LOG_LEVEL (default info). …`, with:
```markdown
See `.env.example`. Required: `DATABASE_URL`, `JWT_SECRET` (32 characters or more), `FINNHUB_API_KEY`, `TIINGO_API_KEY`, `ALPACA_KEY_ID`, `ALPACA_SECRET_KEY`, `MASSIVE_API_KEY`, `CRON_SECRET` (16 or more), `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`. Optional: `LOG_LEVEL` (default `info`), `MASSIVE_BASE_URL` (default `https://api.massive.com`), `APNS_TOPIC` (default `com.chenkai.wait`). Set them for Production and Preview. The app fails at cold start, naming any missing variable.
```
Then append:
~~~markdown
## Daily alerts (plan 06)

| Env var | Required | Notes |
|---|---|---|
| `MASSIVE_API_KEY` | yes | Massive (ex-Polygon) grouped daily, sent as `Authorization: Bearer` |
| `MASSIVE_BASE_URL` | no | default `https://api.massive.com` |
| `CRON_SECRET` | yes | ≥ 16 chars; Vercel Cron sends it as a bearer token |
| `APNS_KEY` | yes | `.p8` key: PEM, PEM with literal `\n`, or base64 of the PEM |
| `APNS_KEY_ID`, `APNS_TEAM_ID` | yes | 10-char ids from the Apple Developer portal (team `5WDN96EM72`) |
| `APNS_TOPIC` | no | default `com.chenkai.wait` |

- **Routes:** `POST /api/devices`, `DELETE /api/devices/:token` and `GET /api/internal/daily-alerts`.
- **Run the job by hand:**
  ```bash
  curl -H "Authorization: Bearer $CRON_SECRET" $WAIT_API_BASE_URL/api/internal/daily-alerts
  ```
- **Send one push:**
  ```bash
  npm run send-test-push -- --token <hex> --env sandbox --symbol AAPL
  ```
- **Re-run a day from scratch** (debugging only): delete that day's row from `alert_job_runs`.
~~~

- [ ] **Step 3: Update `Packages/WaitKit/README.md`**

Plan 03 already wrote the 4-column module table (`Target | Depends on | watchOS | Linked by`), including a `NotificationClient (plan 06)` row. Don't add a row. Edit the existing cells:
- `NotificationClient (plan 06)`: set "Depends on" to `Logging, Dependencies, DependenciesMacros` and "Linked by" to `AppFeature, SettingsFeature`. Change nothing if they already read that way.
- `AppFeature`: append `APIClient, NotificationClient` to "Depends on", skipping any already listed.
- `SettingsFeature`: append `Persistence, Logging, NotificationClient` to "Depends on", skipping any already listed.

Below the table, after the sentence "The last three rows exist only after their plan has run.", add:
```markdown
Plan 06: `NotificationClient` handles permission, APNs registration and the push-tap stream; its live delegate is installed by `AppDelegate`. `AppFeature` scopes `PushFeature` (launch registration, pending unregistration, device-token upload, tap → `openURL`). `SettingsFeature` has the Alerts section (`@Shared(.alertsEnabled)`, permission, Open Settings).
```

- [ ] **Step 4: Commit**

```bash
cd /Users/ckai/code/Wait
git add CLAUDE.md server/README.md Wait/Packages/WaitKit/README.md
git commit -m "docs: document daily ladder alerts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Done when

- `cd server && npm run typecheck && npm test` passes. That includes the vector-driven `shouldAlert`, the repositories on PGlite, the Massive adapter, the resolver, APNs, the job (crash/rerun/holiday/split/pruning), the routes, the config and `vercel.json`.
- `scripts/test-waitkit.sh` passes, including `NotificationClientTests`, `APIClientTests/DeviceEndpointTests`, `AppFeatureTests/PushFeatureTests`, `AppFeatureTests/AppFeaturePushRoutingTests` and `SettingsFeatureTests/SettingsAlertsTests`.
- `Wait` and `WaitWatch` build.
- Task 24 is confirmed by the user:
  - a sandbox push arrives and opens the stock
  - the cron `curl` returns stats
  - a same-day rerun sends nothing
  - the cron is listed in the Vercel dashboard
