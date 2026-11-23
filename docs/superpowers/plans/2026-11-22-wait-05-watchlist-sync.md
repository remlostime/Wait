# Watchlist Sync Implementation Plan (Plan 05)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync each user's watchlist (ladder, memo, favorite, order, per-stock checklist, ladder history) between the iOS app and the backend. Sync is offline-first, last-write-wins per item, and keeps tombstones for deletes.

**Architecture:**
- **Server.**
  - `server/src/domain/ladder.ts` mirrors the Swift ladder and is driven by the shared vectors file.
  - `watchlist_items` is keyed by `(user_id, symbol)`.
  - `NeonWatchlistRepository` runs one push statement (a CTE) and one pull statement.
  - `WatchlistSyncService` validates, clamps and dedupes the changes, then pushes, then pulls. It also adds the current row for every rejected symbol.
  - Fastify routes are `POST /api/watchlist/sync` and `GET /api/watchlist`.
- **iOS.**
  - A `SyncState` file lives in the app group.
  - Two pure functions do the logic: `SyncPlanner` (what is pending) and `SyncMerger` (how to apply remote rows).
  - A single-flight `SyncEngine` actor talks to the server through `APIClient.syncWatchlist`.
  - The `SyncClient` dependency exposes the engine. `AppFeature` and `SettingsFeature` trigger syncs.

**Tech Stack:**
- Server: TypeScript (ESM, NodeNext), Fastify 5 + TypeBox, Neon serverless Postgres through the `Sql` adapter, PGlite, vitest.
- iOS: Swift 6, TCA 1.26, swift-sharing `@Shared`, swift-dependencies `@DependencyClient`, Swift Testing.

**Spec:** `docs/superpowers/plans/2026-11-22-wait-00-overview.md`. The relevant sections:
- §7: ladder contracts and vectors
- §8.3: schema
- §8.4: endpoints and shapes
- §8.5: the sync protocol
- §9: wire conventions
- §12: iOS paths, dependency keys and extension points

---

> **Deviations from the overview.** Each one is deliberate. Keep them, or ask the user before changing them.
> 1. **The sync symbol pattern is wider.** `POST /api/watchlist/sync` accepts `^[A-Z0-9][A-Z0-9.-]{0,14}$`, not the market-route pattern `^[A-Z]{1,5}([.-][A-Z]{1,2})?$`.
>    - Reason: legacy watchlists can hold HKEX or OTC symbols (risk 24). The server rejects the whole batch if one item fails validation, so a single such symbol would block sync forever.
> 2. **Ties apply the remote row.** When a remote row's `clientUpdatedAt` equals the local stamp, the client applies the remote content and acknowledges it. The overview only says "acknowledge".
>    - Reason: the server already resolves ties in its own favor (`<` in the push `WHERE`), so this keeps every device convergent.
>    - In the common case the row is the echo of our own push, the content is identical, and applying it changes nothing.
> 3. **Tombstones carry placeholder fields.** A tombstone change is sent with `name = symbol`, an empty ladder, an empty memo and empty arrays.
>    - Reason: `SyncState.tombstones` keeps only the date, so the last-known fields aren't available. The server stores whatever arrives on a deleted row, and nothing reads the fields of a deleted row.
> 4. **Timestamps are compared and encoded as whole milliseconds** (this hardens D21).
>    - `SyncStamp` compares `Date`s as rounded Unix milliseconds.
>    - Sync DTOs carry `clientUpdatedAt` and history `date` as strings, written by a deterministic formatter (`SyncStamp.string(from:)`). They don't go through `JSONEncoder`'s date strategy.
>    - Reason: a ±1-ulp `Double` difference, or a formatter that truncates rather than rounds, would otherwise re-push the same item on every sync.
> 5. **The client batch is 50 changes**, below the server maximum of 200. Vercel limits request bodies to 4.5 MB, and a worst-case item (10k memo, 100 checklist items, 200 history entries) is about 100 KB.
> 6. **Unsyncable symbols stay local-only.** `SyncPlanner` skips any symbol outside the sync pattern, and `SyncEngine` logs it. Otherwise the server would return 400 for the whole batch on every sync.
> 7. **Clock skew is handled on both sides.**
>    - The client clamps outgoing stamps to device now + 5 min, matching the server.
>    - When the server echoes our own content with an earlier (clamped) stamp, `SyncMerger` adopts that stamp, so this device's later last-write-wins comparisons agree with the server.
> 8. **`SyncEngine.reset()` bumps a generation counter**, and a run that is in flight discards its merge. This stops a sync that started before Delete Account from writing the old account's cursor back.

## Prerequisites

- [ ] **Worktree.** Use superpowers:using-git-worktrees. Branch off the branch where plans 02 and 04 landed, never `master`:
  ```bash
  cd /Users/ckai/code/Wait && git worktree add ../Wait-plan05 -b ck/plan05-watchlist-sync
  ```
  Every path below is relative to the worktree root (`/Users/ckai/code/Wait-plan05`). Commands written with `/Users/ckai/code/Wait/...` mean the same paths inside the worktree.
- [ ] **Plan 02 is done.** These exist:
  - `shared/ladder-test-vectors.json`
  - `Wait/Packages/WaitKit/Sources/Persistence/{AppGroup,SharedKeys,Shared+Watchlist}.swift`
  - `Sources/AppFeature/AppFeature.swift`
  - `Sources/SettingsFeature/SettingsFeature.swift`
  - `Sources/WatchlistFeature/WatchlistFeature.swift`, which declares `Action.delegate(.refreshRequested)`
- [ ] **Plan 04 is done.** These exist:
  - `server/` with `npm test` passing
  - `server/migrations/001_*.sql` and `002_*.sql`
  - `Wait/Packages/WaitKit/Sources/APIClient/{APIClient,HTTPSession}.swift`
- [ ] **Load these skills:**
  - superpowers:test-driven-development for every task
  - swiftui-expert:swiftui-expert-skill for Task 13 (the SwiftUI section)
  - ios-code-best-practice:ios-code-best-practice, only its Swift concurrency guidance (actor and `Sendable` rules)
- [ ] **Check the cross-plan names this plan relies on.** Run:
  ```bash
  cd /Users/ckai/code/Wait-plan05/server
  grep -n "export" src/db/sql.ts src/lib/errors.ts src/lib/clock.ts src/container.ts src/middleware/auth.ts src/schemas/common.ts test/support/pglite.ts test/support/app.ts
  grep -n "public var\|public func\|func post\|func get" ../Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift ../Wait/Packages/WaitKit/Sources/APIClient/HTTPSession.swift
  grep -n "func add\|func remove\|func update\|func reorder" ../Wait/Packages/WaitKit/Sources/Persistence/Shared+Watchlist.swift
  ```
  Expected: each name in the table below appears. If plan 04 used a different name, keep plan 04's name and change only the import or call in this plan's code. Don't rename plan 04's code.

  | Used here | Expected definition (plan 04 / plan 02) |
  |---|---|
  | `Sql`, `Row` | `src/db/sql.ts`: `export type Sql = (strings: TemplateStringsArray, ...values: unknown[]) => Promise<Row[]>`, `export type Row = Record<string, unknown>` |
  | `AppError` | `src/lib/errors.ts`: `new AppError(code: string, message: string, statusCode: number)` |
  | `Clock` | `src/lib/clock.ts`: `export interface Clock { now(): Date }`, `export function fixedClock(start: Date)` |
  | `Container`, `RouteOptions`, `createContainer`, `createMockContainer` | `src/container.ts`: `Container` has `clock`, `logger` (`FastifyBaseLogger`), `sql`, `users`, `rateLimiter` and `auth`. `RouteOptions = { container }`. `createMockContainer(overrides: Partial<Container> = {})` reads each member as `overrides.x ?? default`. |
  | `buildAuthMiddleware` | `src/middleware/auth.ts`: `buildAuthMiddleware(users)` returns `{ authenticate }` and sets the non-optional `request.authenticatedUser` (`User`, with `id`) |
  | `ErrorResponseSchema` | `src/schemas/common.ts` |
  | `createTestDb` | `test/support/pglite.ts`: `createTestDb(): Promise<TestDb>`, where `TestDb = { db, sql, close() }`. Returns a fresh, fully migrated database (PGlite by default). |
  | `buildTestApp` | `test/support/app.ts`: `buildTestApp(overrides: Partial<Container> = {})` returns `{ app, container, user, authHeaders }`. `user` is created in the mock `users` repository. `authHeaders(userId = user.id)` is **synchronous** and returns `Record<string, string>`. |
  | `HTTPSession.post` | `Sources/APIClient/HTTPSession.swift`: `func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response`. Authenticated; re-registers once on a 401. |
  | Persistence helpers | `Shared<IdentifiedArrayOf<WatchlistItem>>`: `add(_ item: WatchlistItem, now: Date)` and `remove(_ symbol: String, now: Date)` |
| Ajv options | `buildApp` creates Fastify with `ajv: { customOptions: { coerceTypes: false, removeAdditional: false } }` (overview §8.1), so unknown body fields return 400 |

## File Structure

**Server** (`server/`):

| File | Responsibility |
|---|---|
| `src/domain/ladder.ts` (create) | Ladder validation, derived fair, knots, temperature and band, status. Pure functions over decimal-string anchors. |
| `test/domain/ladder.test.ts` (create) | Runs the `validation`, `knots` and `evaluations` vectors from `../shared/ladder-test-vectors.json` |
| `migrations/003_watchlist.sql` (create) | The `watchlist_items` table and its indexes (overview §8.3) |
| `src/db/watchlistTypes.ts` (create) | `LadderValues`, `ChecklistEntry`, `LadderHistoryEntry`, `WatchlistChange`, `WatchlistRow`, `SyncCursor` plus cursor encode/decode |
| `src/db/WatchlistRepository.ts` (create) | Repository interface |
| `src/db/NeonWatchlistRepository.ts` (create) | SQL implementation (push CTE, pull, fetch by symbols), used with Neon in production and PGlite in tests |
| `src/db/MockWatchlistRepository.ts` (create) | In-memory implementation with the same last-write-wins semantics, for service and route tests |
| `test/db/NeonWatchlistRepository.test.ts` (create) | PGlite tests of the SQL |
| `src/services/WatchlistSyncService.ts` (create) | Validation, limits, clamping, dedupe, push then pull, rejected rows, cursor and `hasMore` |
| `test/services/WatchlistSyncService.test.ts` (create) | Service tests against `MockWatchlistRepository` |
| `src/schemas/watchlist.ts` (create) | TypeBox schemas for both routes |
| `src/routes/api/watchlist.ts` (create) | Fastify plugin `POST /sync` and `GET /` |
| `test/routes/watchlist.test.ts` (create) | `app.inject` tests |
| `src/container.ts` (modify) | Add `watchlist` and `watchlistSync` |
| `src/app.ts` (modify) | Register the watchlist routes |

**iOS** (`Wait/Packages/WaitKit/`):

| File | Responsibility |
|---|---|
| `Sources/Persistence/SyncState.swift` (create) | `SyncState` value plus the `.syncState` shared key |
| `Sources/Persistence/Shared+Watchlist.swift` (modify) | `remove` records a tombstone; `add` clears it |
| `Tests/PersistenceTests/SyncStateTests.swift` (create) | Tombstone bookkeeping tests |
| `Sources/APIClient/DTOs/WatchlistSyncDTOs.swift` (create) | `SyncRequestDTO`, `SyncResponseDTO`, `WatchlistChangeDTO`, `WatchlistItemDTO`, `LadderDTO`, `ChecklistItemDTO`, `LadderRevisionDTO` |
| `Sources/APIClient/APIClient.swift` (modify) | Add the `syncWatchlist` endpoint |
| `Tests/APIClientTests/WatchlistSyncDTOTests.swift` (create) | JSON shape tests |
| `Sources/SyncClient/SyncStamp.swift` (create) | Millisecond comparison plus the deterministic ISO formatter and parser |
| `Sources/SyncClient/SyncChange.swift` (create) | `SyncChange`, `RemoteWatchlistItem`, `SyncReport` |
| `Sources/SyncClient/SyncPlanner.swift` (create) | Computes pending changes (pure) |
| `Sources/SyncClient/SyncMerger.swift` (create) | Acknowledges sent changes and applies remote rows (pure) |
| `Sources/SyncClient/SyncMapping.swift` (create) | DTO ↔ Domain mapping with client-side clamps |
| `Sources/SyncClient/SyncEngine.swift` (create) | Single-flight actor that runs the rounds |
| `Sources/SyncClient/SyncClient.swift` (create) | `@DependencyClient` and `\.syncClient` |
| `Tests/SyncClientTests/*.swift` (create) | Planner, merger, mapping and engine tests |
| `Package.swift` (modify) | `SyncClient` and `SyncClientTests` targets; feature dependencies |
| `Sources/AppFeature/AppFeature.swift` (modify) | Sync triggers |
| `Tests/AppFeatureTests/AppFeatureSyncTests.swift` (create) | Trigger tests with `TestClock` |
| `Sources/SettingsFeature/{SettingsFeature,SettingsView,SyncSection}.swift` (modify/create) | "Last synced", "Sync now", and resetting sync state on account deletion |
| `Tests/SettingsFeatureTests/SettingsSyncTests.swift` (create) | Settings sync tests |

**Docs:** `CLAUDE.md`, `Wait/Packages/WaitKit/README.md`, `server/README.md`.

## Chunk 1: Server ladder domain

### Task 1: `domain/ladder.ts`, driven by the shared vectors

**Files:**
- Create: `server/src/domain/ladder.ts`
- Test: `server/test/domain/ladder.test.ts`
- Read only: `shared/ladder-test-vectors.json` (plan 02 created it; don't edit it here, see overview risk 32)

- [x] **Step 1: Write the failing test**

Create `server/test/domain/ladder.test.ts`:
```ts
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { describe, expect, it } from "vitest"
import {
  buildKnots,
  classifyStatus,
  derivedFair,
  temperature,
  temperatureBand,
  validateLadder,
  type LadderInput,
} from "../../src/domain/ladder.js"

type LadderRef = string | LadderInput
type Vectors = {
  version: number
  ladders: Record<string, LadderInput>
  validation: Array<{
    ladder: LadderRef
    valid: boolean
    error?: { kind: string; rung?: string; lower?: string; upper?: string }
  }>
  knots: Array<{ ladder: LadderRef; derivedFair?: number; knots: Array<[number, number]> }>
  evaluations: Array<{ ladder: LadderRef; price: string; temperature: number | null; band: string | null; status: string }>
}

// server/test/domain → repo root is three levels up.
const vectorsPath = fileURLToPath(new URL("../../../shared/ladder-test-vectors.json", import.meta.url))
const vectors = JSON.parse(readFileSync(vectorsPath, "utf8")) as Vectors

const TEMPERATURE_TOLERANCE = 0.05
const KNOT_TOLERANCE = 0.001

function resolveLadder(ref: LadderRef): LadderInput {
  if (typeof ref !== "string") return ref
  const ladder = vectors.ladders[ref]
  if (!ladder) throw new Error(`Unknown ladder "${ref}" in vectors`)
  return ladder
}

function label(ref: LadderRef): string {
  return typeof ref === "string" ? ref : JSON.stringify(ref)
}

function expectNear(actual: number, expected: number, tolerance: number) {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance)
}

describe("ladder vectors", () => {
  it("reads version 1 of the shared vectors", () => {
    expect(vectors.version).toBe(1)
  })

  describe("validateLadder", () => {
    for (const [index, vector] of vectors.validation.entries()) {
      it(`validation #${index} ${label(vector.ladder)}`, () => {
        const result = validateLadder(resolveLadder(vector.ladder))
        if (vector.valid) {
          expect(result).toEqual({ ok: true })
        } else {
          expect(result).toEqual({ ok: false, ...vector.error })
        }
      })
    }
  })

  describe("buildKnots and derivedFair", () => {
    for (const [index, vector] of vectors.knots.entries()) {
      it(`knots #${index} ${label(vector.ladder)}`, () => {
        const ladder = resolveLadder(vector.ladder)
        const knots = buildKnots(ladder)
        expect(knots).toHaveLength(vector.knots.length)
        vector.knots.forEach(([price, score], k) => {
          expectNear(knots[k]![0], price, KNOT_TOLERANCE)
          expectNear(knots[k]![1], score, KNOT_TOLERANCE)
        })
        if (vector.derivedFair !== undefined) {
          expectNear(derivedFair(ladder)!, vector.derivedFair, KNOT_TOLERANCE)
        }
      })
    }
  })

  describe("temperature, band and status", () => {
    for (const [index, vector] of vectors.evaluations.entries()) {
      it(`evaluation #${index} ${label(vector.ladder)} @ ${vector.price}`, () => {
        const ladder = resolveLadder(vector.ladder)
        const price = Number(vector.price)
        const actual = temperature(ladder, price)
        if (vector.temperature === null) {
          expect(actual).toBeNull()
        } else {
          expectNear(actual!, vector.temperature, TEMPERATURE_TOLERANCE)
          if (vector.band !== null) expect(temperatureBand(actual!)).toBe(vector.band)
        }
        expect(classifyStatus(ladder, price)).toBe(vector.status)
      })
    }
  })
})

describe("ladder edge cases", () => {
  it("rejects a non-numeric anchor as nonPositive", () => {
    expect(validateLadder({ buyHigh: "abc" })).toEqual({ ok: false, kind: "nonPositive", rung: "buyHigh" })
  })

  it("derives fair from buyLow when buyHigh is absent", () => {
    expectNear(derivedFair({ buyLow: "70" })!, 100, KNOT_TOLERANCE)
  })

  it("does not derive fair when any upper anchor is present", () => {
    expect(derivedFair({ buyHigh: "90", sell: "200" })).toBeNull()
  })

  it("treats null and missing anchors the same", () => {
    expect(buildKnots({ buyLow: null, buyHigh: "16", fair: null })).toEqual(buildKnots({ buyHigh: "16" }))
  })
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/domain/ladder.test.ts`
Expected: FAIL. vitest reports `Failed to load url ../../src/domain/ladder.js` (or `Cannot find module`), and 0 tests run.

- [x] **Step 3: Write the implementation**

Create `server/src/domain/ladder.ts`:
```ts
// Ladder math mirrored from the Swift `Domain` target (PriceLadder).
// Spec: docs/superpowers/plans/2026-11-22-wait-00-overview.md §7.1–§7.2.
// Anchors arrive as decimal strings and are compared as numbers. Server prices have ≤ 6 decimals,
// so double precision is exact enough for ordering, and temperatures carry a ±0.05 tolerance.

export const RUNGS = ["buyLow", "buyHigh", "fair", "trim", "sell"] as const
export type Rung = (typeof RUNGS)[number]

/** A ladder as it travels on the wire: each rung is a decimal string, null, or absent. */
export type LadderInput = Partial<Record<Rung, string | null>>

/** A knot is [price, score]. */
export type Knot = [price: number, score: number]

export const RUNG_SCORES: Readonly<Record<Rung, number>> = {
  buyLow: 10,
  buyHigh: 30,
  fair: 50,
  trim: 80,
  sell: 95,
}

export const LADDER_STATUSES = [
  "DEEP_BUY",
  "BUY_ZONE",
  "WATCH",
  "AT_OR_ABOVE_FAIR",
  "TRIM",
  "SELL",
  "NO_ANCHORS",
] as const
export type LadderStatus = (typeof LADDER_STATUSES)[number]

export type TemperatureBand = "freezing" | "cold" | "neutral" | "warm" | "hot"

export type LadderValidation =
  | { ok: true }
  | { ok: false; kind: "nonPositive"; rung: Rung }
  | { ok: false; kind: "outOfOrder"; lower: Rung; upper: Rung }

type Anchor = { rung: Rung; value: number }

const BOTTOM_TAIL_FACTOR = 0.5
const TOP_TAIL_FACTOR = 1.5

function anchorValue(ladder: LadderInput, rung: Rung): number | null {
  const raw = ladder[rung]
  return raw === undefined || raw === null ? null : Number(raw)
}

function presentAnchors(ladder: LadderInput): Anchor[] {
  const anchors: Anchor[] = []
  for (const rung of RUNGS) {
    const value = anchorValue(ladder, rung)
    if (value !== null) anchors.push({ rung, value })
  }
  return anchors
}

export function isEmptyLadder(ladder: LadderInput): boolean {
  return presentAnchors(ladder).length === 0
}

/** Every present anchor must be > 0. Present anchors must be non-decreasing in rung order; the first failing adjacent pair is reported. */
export function validateLadder(ladder: LadderInput): LadderValidation {
  const anchors = presentAnchors(ladder)
  for (const anchor of anchors) {
    if (!Number.isFinite(anchor.value) || anchor.value <= 0) {
      return { ok: false, kind: "nonPositive", rung: anchor.rung }
    }
  }
  for (let index = 1; index < anchors.length; index++) {
    const lower = anchors[index - 1]!
    const upper = anchors[index]!
    if (lower.value > upper.value) {
      return { ok: false, kind: "outOfOrder", lower: lower.rung, upper: upper.rung }
    }
  }
  return { ok: true }
}

/** (buyHigh ?? buyLow) × 10 / 7. Applies only when a buy band exists and fair, trim and sell are all absent. */
export function derivedFair(ladder: LadderInput): number | null {
  const buyLow = anchorValue(ladder, "buyLow")
  const buyHigh = anchorValue(ladder, "buyHigh")
  const hasBand = buyLow !== null || buyHigh !== null
  const hasUpper =
    anchorValue(ladder, "fair") !== null || anchorValue(ladder, "trim") !== null || anchorValue(ladder, "sell") !== null
  if (!hasBand || hasUpper) return null
  const top = buyHigh ?? buyLow!
  return (top * 10) / 7
}

export function effectiveFair(ladder: LadderInput): number | null {
  return anchorValue(ladder, "fair") ?? derivedFair(ladder)
}

/** The anchor knots (plus the derived fair), the 0.5× and 1.5× tails, stable-sorted by price. */
export function buildKnots(ladder: LadderInput): Knot[] {
  const knots: Knot[] = presentAnchors(ladder).map((anchor) => [anchor.value, RUNG_SCORES[anchor.rung]])
  const fair = derivedFair(ladder)
  if (fair !== null) knots.push([fair, RUNG_SCORES.fair])
  if (knots.length === 0) return []
  const prices = knots.map(([price]) => price)
  knots.push([Math.min(...prices) * BOTTOM_TAIL_FACTOR, 0], [Math.max(...prices) * TOP_TAIL_FACTOR, 100])
  return knots.sort((a, b) => a[0] - b[0])
}

/** Piecewise-linear and clamped. Uses the first segment that contains the price. Returns null for an empty ladder. */
export function temperature(ladder: LadderInput, price: number): number | null {
  const knots = buildKnots(ladder)
  if (knots.length === 0) return null
  const first = knots[0]!
  const last = knots[knots.length - 1]!
  if (price <= first[0]) return first[1]
  if (price >= last[0]) return last[1]
  for (let index = 0; index < knots.length - 1; index++) {
    const [x0, y0] = knots[index]!
    const [x1, y1] = knots[index + 1]!
    if (x0 <= price && price <= x1) {
      return x1 === x0 ? y0 : y0 + ((price - x0) / (x1 - x0)) * (y1 - y0)
    }
  }
  return last[1]
}

export function temperatureBand(value: number): TemperatureBand {
  if (value < 20) return "freezing"
  if (value < 40) return "cold"
  if (value < 60) return "neutral"
  if (value < 80) return "warm"
  return "hot"
}

/** Status from price vs anchors (overview §7.2 step 5). Independent of the temperature. */
export function classifyStatus(ladder: LadderInput, price: number): LadderStatus {
  if (isEmptyLadder(ladder)) return "NO_ANCHORS"
  const sell = anchorValue(ladder, "sell")
  const trim = anchorValue(ladder, "trim")
  const fair = effectiveFair(ladder)
  const buyLow = anchorValue(ladder, "buyLow")
  const buyHigh = anchorValue(ladder, "buyHigh")
  if (sell !== null && price >= sell) return "SELL"
  if (trim !== null && price >= trim) return "TRIM"
  if (fair !== null && price >= fair) return "AT_OR_ABOVE_FAIR"
  if (buyLow !== null && price <= buyLow) return "DEEP_BUY"
  if (buyHigh !== null && price <= buyHigh) return "BUY_ZONE"
  return "WATCH"
}
```

- [x] **Step 4: Run the test and confirm it passes**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/domain/ladder.test.ts`
Expected: PASS. `Test Files  1 passed (1)` and `Tests  38 passed (38)` (1 version check, 5 validation, 5 knots, 23 evaluations, 4 edge cases).

- [x] **Step 5: Typecheck**

Run: `cd /Users/ckai/code/Wait-plan05/server && npm run typecheck`
Expected: exits 0 with no output from `tsc`.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/domain/ladder.ts server/test/domain/ladder.test.ts
git commit -m "$(cat <<'MSG'
feat(server): ladder domain mirrored from Swift, driven by shared vectors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

## Chunk 2: Server sync

### Task 2: Migration `003_watchlist.sql`

**Files:**
- Create: `server/migrations/003_watchlist.sql`
- Test: `server/test/db/migration003.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/db/migration003.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { createTestDb } from "../support/pglite.js"

const EXPECTED_COLUMNS = [
  "user_id", "symbol", "name", "buy_low", "buy_high", "fair", "trim", "sell", "memo", "is_favorite", "sort_index",
  "checklist", "ladder_history", "client_updated_at", "version", "deleted_at", "last_status", "last_status_at",
  "last_evaluated_price", "created_at", "server_updated_at",
]

describe("003_watchlist.sql", () => {
  it("creates watchlist_items with the overview §8.3 columns", async () => {
    const { sql, close } = await createTestDb()
    const rows = await sql`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'watchlist_items' ORDER BY ordinal_position`
    expect(rows.map((row) => row.column_name)).toEqual(EXPECTED_COLUMNS)
    await close()
  })

  it("cascades a user delete to their watchlist items", async () => {
    const { sql, close } = await createTestDb()
    await sql`INSERT INTO users (id, anonymous_id) VALUES ('u1', 'anon-u1')`
    await sql`
      INSERT INTO watchlist_items (user_id, symbol, name, client_updated_at, version)
      VALUES ('u1', 'AAPL', 'Apple', '2026-11-20T15:00:00.000Z', 1)`
    await sql`DELETE FROM users WHERE id = 'u1'`
    const rows = await sql`SELECT count(*)::int AS n FROM watchlist_items`
    expect(Number(rows[0]!.n)).toBe(0)
    await close()
  })
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/migration003.test.ts`
Expected: FAIL.
- The first test reports `expected [] to deeply equal [ 'user_id', … ]`.
- The second reports `relation "watchlist_items" does not exist`.

- [x] **Step 3: Write the migration**

Create `server/migrations/003_watchlist.sql`. The SQL is copied verbatim from overview §8.3:
```sql
-- 003_watchlist.sql (plan 05): per-user watchlist, offline-first sync (overview §8.5).
CREATE TABLE IF NOT EXISTS watchlist_items (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, symbol TEXT NOT NULL, name TEXT NOT NULL,
  buy_low NUMERIC(18,6), buy_high NUMERIC(18,6), fair NUMERIC(18,6), trim NUMERIC(18,6), sell NUMERIC(18,6),
  memo TEXT NOT NULL DEFAULT '', is_favorite BOOLEAN NOT NULL DEFAULT FALSE, sort_index INT NOT NULL DEFAULT 0,
  checklist JSONB NOT NULL DEFAULT '[]', ladder_history JSONB NOT NULL DEFAULT '[]',
  client_updated_at TIMESTAMPTZ NOT NULL, version BIGINT NOT NULL, deleted_at TIMESTAMPTZ,
  last_status TEXT, last_status_at TIMESTAMPTZ, last_evaluated_price NUMERIC(18,6),   -- server-owned; never bumps version
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, symbol));
CREATE INDEX IF NOT EXISTS idx_watchlist_user_version ON watchlist_items(user_id, version, symbol);
CREATE INDEX IF NOT EXISTS idx_watchlist_live_symbol ON watchlist_items(symbol) WHERE deleted_at IS NULL;
```
`trim` is a Postgres column-name keyword. It's legal as a column name. Every query in this plan quotes it as `"trim"` to be safe in every position.

- [x] **Step 4: Run the test and confirm it passes**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/migration003.test.ts`
Expected: PASS, `Tests  2 passed (2)`.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/migrations/003_watchlist.sql server/test/db/migration003.test.ts
git commit -m "$(cat <<'MSG'
feat(server): add watchlist_items migration

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 3: Watchlist types, cursor and decimal normalization

**Files:**
- Create: `server/src/db/watchlistTypes.ts`
- Test: `server/test/db/watchlistTypes.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/db/watchlistTypes.test.ts`:
```ts
import { describe, expect, it } from "vitest"
import { START_CURSOR, decodeCursor, encodeCursor, normalizeDecimal } from "../../src/db/watchlistTypes.js"

describe("sync cursor", () => {
  it("treats null, undefined and the empty string as the start cursor", () => {
    expect(decodeCursor(null)).toEqual(START_CURSOR)
    expect(decodeCursor(undefined)).toEqual(START_CURSOR)
    expect(decodeCursor("")).toEqual(START_CURSOR)
    expect(START_CURSOR).toEqual({ version: 0, symbol: "" })
  })

  it("round-trips version and symbol, including dotted symbols", () => {
    expect(decodeCursor(encodeCursor({ version: 12, symbol: "BRK.B" }))).toEqual({ version: 12, symbol: "BRK.B" })
    expect(encodeCursor({ version: 3, symbol: "AAPL" })).toBe("3:AAPL")
    expect(decodeCursor("0:")).toEqual({ version: 0, symbol: "" })
  })

  it("rejects malformed cursors", () => {
    for (const raw of ["AAPL", "-1:AAPL", "1.5:AAPL", "x:AAPL", "99999999999999999999:A", ":AAPL"]) {
      expect(decodeCursor(raw), raw).toBeNull()
    }
  })
})

describe("normalizeDecimal", () => {
  it("strips trailing zeros that NUMERIC(18,6) adds", () => {
    expect(normalizeDecimal("16.000000")).toBe("16")
    expect(normalizeDecimal("14.200000")).toBe("14.2")
    expect(normalizeDecimal("0.007500")).toBe("0.0075")
    expect(normalizeDecimal("120")).toBe("120")
    expect(normalizeDecimal(16.5)).toBe("16.5")
  })

  it("passes null and undefined through as null", () => {
    expect(normalizeDecimal(null)).toBeNull()
    expect(normalizeDecimal(undefined)).toBeNull()
  })
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/watchlistTypes.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/watchlistTypes.js`.

- [x] **Step 3: Write the implementation**

Create `server/src/db/watchlistTypes.ts`:
```ts
import type { LadderInput } from "../domain/ladder.js"

/** Every rung is always present: a decimal string, or null when unset. */
export type LadderValues = {
  buyLow: string | null
  buyHigh: string | null
  fair: string | null
  trim: string | null
  sell: string | null
}

export type ChecklistEntry = { id: string; name: string; isChecked: boolean }

/** A history entry's ladder is stored exactly as the client sent it. */
export type LadderHistoryEntry = { date: string; ladder: LadderInput }

/** One item as the client pushes it. `deleted: true` is a tombstone. */
export type WatchlistChange = {
  symbol: string
  name: string
  ladder: LadderValues
  memo: string
  isFavorite: boolean
  sortIndex: number
  checklist: ChecklistEntry[]
  ladderHistory: LadderHistoryEntry[]
  clientUpdatedAt: Date
  deleted: boolean
}

/** A stored item. `lastStatus` and `lastEvaluatedPrice` are server-owned (written by the plan 06 alert job). */
export type WatchlistRow = WatchlistChange & {
  version: number
  lastStatus: string | null
  lastEvaluatedPrice: string | null
}

export type SyncCursor = { version: number; symbol: string }

export const START_CURSOR: SyncCursor = { version: 0, symbol: "" }

export function encodeCursor(cursor: SyncCursor): string {
  return `${cursor.version}:${cursor.symbol}`
}

/** `null`, `undefined` and `""` → start (the empty string is accepted defensively). Returns `null` for a malformed cursor. */
export function decodeCursor(raw: string | null | undefined): SyncCursor | null {
  if (raw === null || raw === undefined || raw === "") return START_CURSOR
  const separator = raw.indexOf(":")
  if (separator <= 0) return null
  const versionText = raw.slice(0, separator)
  if (!/^[0-9]{1,15}$/.test(versionText)) return null
  return { version: Number(versionText), symbol: raw.slice(separator + 1) }
}

/** NUMERIC(18,6) comes back as "16.000000". Normalize to the shortest decimal string ("16", "14.2"). */
export function normalizeDecimal(value: unknown): string | null {
  if (value === null || value === undefined) return null
  const text = String(value)
  if (!text.includes(".")) return text
  return text.replace(/0+$/, "").replace(/\.$/, "")
}

export function normalizeLadder(ladder: Partial<LadderValues>): LadderValues {
  return {
    buyLow: normalizeDecimal(ladder.buyLow),
    buyHigh: normalizeDecimal(ladder.buyHigh),
    fair: normalizeDecimal(ladder.fair),
    trim: normalizeDecimal(ladder.trim),
    sell: normalizeDecimal(ladder.sell),
  }
}
```

- [x] **Step 4: Run the test and confirm it passes**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/watchlistTypes.test.ts`
Expected: PASS, `Tests  5 passed (5)`.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/db/watchlistTypes.ts server/test/db/watchlistTypes.test.ts
git commit -m "$(cat <<'MSG'
feat(server): watchlist sync types, cursor codec and decimal normalization

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 4: `WatchlistRepository` and its SQL implementation (PGlite contract tests)

**Files:**
- Create: `server/src/db/WatchlistRepository.ts`
- Create: `server/src/db/NeonWatchlistRepository.ts`
- Create: `server/test/support/watchlist.ts` (test builders, reused by Tasks 5–7)
- Create: `server/test/db/watchlistRepositoryContract.ts` (a shared suite, run against both implementations)
- Test: `server/test/db/NeonWatchlistRepository.test.ts`

- [x] **Step 1: Write the test builders**

Create `server/test/support/watchlist.ts`:
```ts
import type { WatchlistChange } from "../../src/db/watchlistTypes.js"

export const T0 = new Date("2026-11-20T15:00:00.000Z")

/** Returns T0 shifted by `ms` milliseconds. */
export function at(ms: number): Date {
  return new Date(T0.getTime() + ms)
}

export function makeChange(overrides: Partial<WatchlistChange> & { symbol: string }): WatchlistChange {
  return {
    name: `${overrides.symbol} Inc.`,
    ladder: { buyLow: null, buyHigh: "100", fair: null, trim: null, sell: null },
    memo: "",
    isFavorite: false,
    sortIndex: 0,
    checklist: [],
    ladderHistory: [],
    clientUpdatedAt: T0,
    deleted: false,
    ...overrides,
  }
}
```

- [x] **Step 2: Write the shared contract suite**

Create `server/test/db/watchlistRepositoryContract.ts`. It has no `.test.ts` suffix, so vitest only runs it through the files that import it.
```ts
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { WatchlistRepository } from "../../src/db/WatchlistRepository.js"
import { START_CURSOR } from "../../src/db/watchlistTypes.js"
import { at, makeChange } from "../support/watchlist.js"

export type WatchlistRepositoryHarness = {
  repository: WatchlistRepository
  close(): Promise<void>
  seedUser(userId: string): Promise<void>
  /** Simulates the plan 06 alert job writing a server-owned status. */
  setLastStatus(userId: string, symbol: string, status: string): Promise<void>
}

export function describeWatchlistRepositoryContract(name: string, makeHarness: () => Promise<WatchlistRepositoryHarness>) {
  describe(`${name} satisfies the WatchlistRepository contract`, () => {
    let harness: WatchlistRepositoryHarness
    const now = at(60_000)

    beforeEach(async () => {
      harness = await makeHarness()
      await harness.seedUser("u1")
      await harness.seedUser("u2")
    })

    afterEach(async () => {
      await harness.close()
    })

    it("inserts new items, reports them as applied and returns them from pull", async () => {
      const applied = await harness.repository.push(
        "u1",
        [makeChange({ symbol: "MSFT" }), makeChange({ symbol: "AAPL", ladder: { buyLow: "12", buyHigh: "14.2", fair: null, trim: null, sell: null } })],
        now,
      )
      expect(applied).toEqual(["AAPL", "MSFT"])
      const rows = await harness.repository.pull("u1", START_CURSOR, 100)
      expect(rows.map((row) => [row.symbol, row.version, row.deleted])).toEqual([
        ["AAPL", 1, false],
        ["MSFT", 1, false],
      ])
      expect(rows[0]!.ladder).toEqual({ buyLow: "12", buyHigh: "14.2", fair: null, trim: null, sell: null })
      expect(rows[0]!.clientUpdatedAt.toISOString()).toBe("2026-11-20T15:00:00.000Z")
    })

    it("rejects an older edit and keeps the stored row", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "newer", clientUpdatedAt: at(2_000) })], now)
      const applied = await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "older", clientUpdatedAt: at(1_000) })], now)
      expect(applied).toEqual([])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.memo).toBe("newer")
    })

    it("keeps the stored row when timestamps tie (server wins)", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "first", clientUpdatedAt: at(1_000) })], now)
      const applied = await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "second", clientUpdatedAt: at(1_000) })], now)
      expect(applied).toEqual([])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.memo).toBe("first")
    })

    it("stores a tombstone and resurrects the item on a newer re-add", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      expect(await harness.repository.push("u1", [makeChange({ symbol: "AAPL", deleted: true, clientUpdatedAt: at(2_000) })], now)).toEqual(["AAPL"])
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.deleted).toBe(true)
      expect(await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "back", clientUpdatedAt: at(3_000) })], now)).toEqual(["AAPL"])
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect([row!.deleted, row!.memo]).toEqual([false, "back"])
    })

    it("assigns a new, increasing version to every push", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "MSFT", clientUpdatedAt: at(1_000) })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(2_000) })], now)
      const rows = await harness.repository.pull("u1", START_CURSOR, 100)
      expect(rows.map((row) => [row.symbol, row.version])).toEqual([
        ["MSFT", 2],
        ["AAPL", 3],
      ])
    })

    it("pages through rows with the (version, symbol) cursor", async () => {
      await harness.repository.push(
        "u1",
        ["NVDA", "AAPL", "MSFT"].map((symbol) => makeChange({ symbol })),
        now,
      )
      const page1 = await harness.repository.pull("u1", START_CURSOR, 2)
      expect(page1.map((row) => row.symbol)).toEqual(["AAPL", "MSFT"])
      const page2 = await harness.repository.pull("u1", { version: page1[1]!.version, symbol: page1[1]!.symbol }, 2)
      expect(page2.map((row) => row.symbol)).toEqual(["NVDA"])
      const page3 = await harness.repository.pull("u1", { version: page2[0]!.version, symbol: page2[0]!.symbol }, 2)
      expect(page3).toEqual([])
    })

    it("resets last_status only when an anchor value changes", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", clientUpdatedAt: at(1_000) })], now)
      await harness.setLastStatus("u1", "AAPL", "BUY_ZONE")
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", memo: "note only", clientUpdatedAt: at(2_000) })], now)
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBe("BUY_ZONE")
      await harness.repository.push(
        "u1",
        [makeChange({ symbol: "AAPL", ladder: { buyLow: null, buyHigh: "100.000", fair: null, trim: null, sell: null }, clientUpdatedAt: at(3_000) })],
        now,
      )
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBe("BUY_ZONE")
      await harness.repository.push(
        "u1",
        [makeChange({ symbol: "AAPL", ladder: { buyLow: null, buyHigh: "90", fair: null, trim: null, sell: null }, clientUpdatedAt: at(4_000) })],
        now,
      )
      expect((await harness.repository.findBySymbols("u1", ["AAPL"]))[0]!.lastStatus).toBeNull()
    })

    it("isolates users from each other", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL" })], now)
      expect(await harness.repository.pull("u2", START_CURSOR, 100)).toEqual([])
      expect(await harness.repository.findBySymbols("u2", ["AAPL"])).toEqual([])
    })

    it("findBySymbols returns current rows, tombstones included, and ignores unknown symbols", async () => {
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL" }), makeChange({ symbol: "MSFT" })], now)
      await harness.repository.push("u1", [makeChange({ symbol: "MSFT", deleted: true, clientUpdatedAt: at(5_000) })], now)
      const rows = await harness.repository.findBySymbols("u1", ["MSFT", "TSLA"])
      expect(rows.map((row) => [row.symbol, row.deleted])).toEqual([["MSFT", true]])
      expect(await harness.repository.findBySymbols("u1", [])).toEqual([])
    })

    it("stores checklist and ladder history verbatim", async () => {
      const checklist = [{ id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true }]
      const ladderHistory = [{ date: "2026-01-02T00:00:00.000Z", ladder: { buyHigh: "120" } }]
      await harness.repository.push("u1", [makeChange({ symbol: "AAPL", checklist, ladderHistory })], now)
      const [row] = await harness.repository.findBySymbols("u1", ["AAPL"])
      expect(row!.checklist).toEqual(checklist)
      expect(row!.ladderHistory).toEqual(ladderHistory)
    })

    it("applies nothing for an unknown user", async () => {
      expect(await harness.repository.push("ghost", [makeChange({ symbol: "AAPL" })], now)).toEqual([])
    })
  })
}
```

- [x] **Step 3: Write the failing SQL-backed test**

Create `server/test/db/NeonWatchlistRepository.test.ts`:
```ts
import { NeonWatchlistRepository } from "../../src/db/NeonWatchlistRepository.js"
import { createTestDb } from "../support/pglite.js"
import { describeWatchlistRepositoryContract } from "./watchlistRepositoryContract.js"

describeWatchlistRepositoryContract("NeonWatchlistRepository (PGlite)", async () => {
  const { sql, close } = await createTestDb()
  return {
    repository: new NeonWatchlistRepository(sql),
    close,
    async seedUser(userId) {
      await sql`INSERT INTO users (id, anonymous_id) VALUES (${userId}, ${`anon-${userId}`})`
    },
    async setLastStatus(userId, symbol, status) {
      await sql`
        UPDATE watchlist_items SET last_status = ${status}, last_status_at = now()
        WHERE user_id = ${userId} AND symbol = ${symbol}`
    },
  }
})
```

- [x] **Step 4: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/NeonWatchlistRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/NeonWatchlistRepository.js`.

- [x] **Step 5: Write the interface**

Create `server/src/db/WatchlistRepository.ts`:
```ts
import type { SyncCursor, WatchlistChange, WatchlistRow } from "./watchlistTypes.js"

export interface WatchlistRepository {
  /**
   * Upserts the changes in one statement under one new per-user version.
   * Last write wins on `clientUpdatedAt`. On a tie, the stored row wins.
   * Callers must dedupe symbols first (Postgres can't update the same row twice in one statement).
   * @returns the applied symbols, sorted.
   */
  push(userId: string, changes: WatchlistChange[], now: Date): Promise<string[]>
  /** Rows (tombstones included) with (version, symbol) > `after`, ordered by (version, symbol). */
  pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]>
  /** The current rows (tombstones included) for `symbols`, sorted by symbol. */
  findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]>
}
```

- [x] **Step 6: Write the SQL implementation**

Create `server/src/db/NeonWatchlistRepository.ts`. Per overview §8.1 it uses only plain value interpolation: no `sql.unsafe`, and the columns are written out in every query.
```ts
import type { Row, Sql } from "./sql.js"
import type { WatchlistRepository } from "./WatchlistRepository.js"
import {
  normalizeDecimal,
  normalizeLadder,
  type ChecklistEntry,
  type LadderHistoryEntry,
  type SyncCursor,
  type WatchlistChange,
  type WatchlistRow,
} from "./watchlistTypes.js"

type IncomingRecord = {
  symbol: string
  name: string
  buy_low: string | null
  buy_high: string | null
  fair: string | null
  trim: string | null
  sell: string | null
  memo: string
  is_favorite: boolean
  sort_index: number
  checklist: ChecklistEntry[]
  ladder_history: LadderHistoryEntry[]
  client_updated_at: string
  deleted: boolean
}

function toIncomingRecord(change: WatchlistChange): IncomingRecord {
  return {
    symbol: change.symbol,
    name: change.name,
    buy_low: change.ladder.buyLow,
    buy_high: change.ladder.buyHigh,
    fair: change.ladder.fair,
    trim: change.ladder.trim,
    sell: change.ladder.sell,
    memo: change.memo,
    is_favorite: change.isFavorite,
    sort_index: change.sortIndex,
    checklist: change.checklist,
    ladder_history: change.ladderHistory,
    client_updated_at: change.clientUpdatedAt.toISOString(),
    deleted: change.deleted,
  }
}

function jsonValue<T>(value: unknown): T {
  return (typeof value === "string" ? JSON.parse(value) : value) as T
}

function dateValue(value: unknown): Date {
  return value instanceof Date ? value : new Date(String(value))
}

function mapRow(row: Row): WatchlistRow {
  return {
    symbol: String(row.symbol),
    name: String(row.name),
    ladder: normalizeLadder({
      buyLow: row.buy_low as string | null,
      buyHigh: row.buy_high as string | null,
      fair: row.fair as string | null,
      trim: row.trim as string | null,
      sell: row.sell as string | null,
    }),
    memo: String(row.memo),
    isFavorite: Boolean(row.is_favorite),
    sortIndex: Number(row.sort_index),
    checklist: jsonValue<ChecklistEntry[]>(row.checklist),
    ladderHistory: jsonValue<LadderHistoryEntry[]>(row.ladder_history),
    clientUpdatedAt: dateValue(row.client_updated_at),
    deleted: row.deleted_at !== null && row.deleted_at !== undefined,
    version: Number(row.version),
    lastStatus: row.last_status === null || row.last_status === undefined ? null : String(row.last_status),
    lastEvaluatedPrice: normalizeDecimal(row.last_evaluated_price),
  }
}

export class NeonWatchlistRepository implements WatchlistRepository {
  constructor(private readonly sql: Sql) {}

  async push(userId: string, changes: WatchlistChange[], now: Date): Promise<string[]> {
    if (changes.length === 0) return []
    const incoming = JSON.stringify(changes.map(toIncomingRecord))
    const nowIso = now.toISOString()
    // One statement: bumping users.watchlist_version takes the user's row lock, so pushes from one user
    // serialize, and their versions become visible in commit order (overview §8.5).
    const rows = await this.sql`
      WITH bump AS (
        UPDATE users SET watchlist_version = watchlist_version + 1, updated_at = ${nowIso}::timestamptz
        WHERE id = ${userId}
        RETURNING watchlist_version AS v
      ),
      incoming AS (
        SELECT * FROM jsonb_to_recordset(${incoming}::jsonb) AS x(
          symbol text, name text, buy_low numeric, buy_high numeric, fair numeric, "trim" numeric, sell numeric,
          memo text, is_favorite boolean, sort_index int, checklist jsonb, ladder_history jsonb,
          client_updated_at timestamptz, deleted boolean)
      )
      INSERT INTO watchlist_items AS w (
        user_id, symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index,
        checklist, ladder_history, client_updated_at, version, deleted_at, server_updated_at)
      SELECT ${userId}::text, i.symbol, i.name, i.buy_low, i.buy_high, i.fair, i."trim", i.sell, i.memo, i.is_favorite,
        i.sort_index, i.checklist, i.ladder_history, i.client_updated_at, bump.v,
        CASE WHEN i.deleted THEN ${nowIso}::timestamptz END, ${nowIso}::timestamptz
      FROM incoming i CROSS JOIN bump
      ON CONFLICT (user_id, symbol) DO UPDATE SET
        name = EXCLUDED.name,
        buy_low = EXCLUDED.buy_low, buy_high = EXCLUDED.buy_high, fair = EXCLUDED.fair,
        "trim" = EXCLUDED."trim", sell = EXCLUDED.sell,
        memo = EXCLUDED.memo, is_favorite = EXCLUDED.is_favorite, sort_index = EXCLUDED.sort_index,
        checklist = EXCLUDED.checklist, ladder_history = EXCLUDED.ladder_history,
        client_updated_at = EXCLUDED.client_updated_at, version = EXCLUDED.version,
        deleted_at = EXCLUDED.deleted_at, server_updated_at = EXCLUDED.server_updated_at,
        last_status = CASE
          WHEN (w.buy_low, w.buy_high, w.fair, w."trim", w.sell)
               IS DISTINCT FROM (EXCLUDED.buy_low, EXCLUDED.buy_high, EXCLUDED.fair, EXCLUDED."trim", EXCLUDED.sell)
          THEN NULL ELSE w.last_status END,
        last_status_at = CASE
          WHEN (w.buy_low, w.buy_high, w.fair, w."trim", w.sell)
               IS DISTINCT FROM (EXCLUDED.buy_low, EXCLUDED.buy_high, EXCLUDED.fair, EXCLUDED."trim", EXCLUDED.sell)
          THEN NULL ELSE w.last_status_at END
      WHERE w.client_updated_at < EXCLUDED.client_updated_at
      RETURNING w.symbol`
    return rows.map((row) => String(row.symbol)).sort()
  }

  async pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]> {
    const rows = await this.sql`
      SELECT symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index, checklist,
        ladder_history, client_updated_at, version, deleted_at, last_status, last_evaluated_price
      FROM watchlist_items
      WHERE user_id = ${userId} AND (version, symbol) > (${after.version}::bigint, ${after.symbol}::text)
      ORDER BY version, symbol
      LIMIT ${limit}`
    return rows.map(mapRow)
  }

  async findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]> {
    if (symbols.length === 0) return []
    const rows = await this.sql`
      SELECT symbol, name, buy_low, buy_high, fair, "trim", sell, memo, is_favorite, sort_index, checklist,
        ladder_history, client_updated_at, version, deleted_at, last_status, last_evaluated_price
      FROM watchlist_items
      WHERE user_id = ${userId} AND symbol IN (SELECT jsonb_array_elements_text(${JSON.stringify(symbols)}::jsonb))
      ORDER BY symbol`
    return rows.map(mapRow)
  }
}
```
Notes:
- Parameters in a `SELECT` list carry explicit casts (`::text`, `::timestamptz`), so Postgres never has to guess their type (`could not determine data type of parameter`).
- The anchor-change test pushes `"100.000"` against a stored `100`. NUMERIC compares by value, so `IS DISTINCT FROM` is false and `last_status` survives. That's intended.
- Symbol lists travel as one JSON parameter, not a Postgres array parameter, so the Neon HTTP driver and PGlite serialize them the same way.

- [x] **Step 7: Run the test and confirm it passes**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/NeonWatchlistRepository.test.ts`
Expected: PASS, `Tests  11 passed (11)`.

- [x] **Step 8: Typecheck and commit**

Run: `cd /Users/ckai/code/Wait-plan05/server && npm run typecheck`
Expected: exits 0.

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/db/WatchlistRepository.ts server/src/db/NeonWatchlistRepository.ts \
  server/test/support/watchlist.ts server/test/db/watchlistRepositoryContract.ts server/test/db/NeonWatchlistRepository.test.ts
git commit -m "$(cat <<'MSG'
feat(server): watchlist repository with LWW push CTE and cursor pull

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 5: `MockWatchlistRepository` passes the same contract

**Files:**
- Create: `server/src/db/MockWatchlistRepository.ts`
- Test: `server/test/db/MockWatchlistRepository.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/db/MockWatchlistRepository.test.ts`:
```ts
import { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { describeWatchlistRepositoryContract } from "./watchlistRepositoryContract.js"

describeWatchlistRepositoryContract("MockWatchlistRepository", async () => {
  const repository = new MockWatchlistRepository()
  return {
    repository,
    async close() {},
    async seedUser(userId) {
      repository.seedUser(userId)
    },
    async setLastStatus(userId, symbol, status) {
      repository.setLastStatus(userId, symbol, status)
    },
  }
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/MockWatchlistRepository.test.ts`
Expected: FAIL with `Failed to load url ../../src/db/MockWatchlistRepository.js`.

- [x] **Step 3: Write the implementation**

Create `server/src/db/MockWatchlistRepository.ts`:
```ts
import type { WatchlistRepository } from "./WatchlistRepository.js"
import { normalizeLadder, type LadderValues, type SyncCursor, type WatchlistChange, type WatchlistRow } from "./watchlistTypes.js"

const RUNG_KEYS: Array<keyof LadderValues> = ["buyLow", "buyHigh", "fair", "trim", "sell"]

function sameAnchors(a: LadderValues, b: LadderValues): boolean {
  return RUNG_KEYS.every((key) => {
    const left = a[key]
    const right = b[key]
    if (left === null || right === null) return left === right
    return Number(left) === Number(right)
  })
}

function isAfter(row: WatchlistRow, cursor: SyncCursor): boolean {
  return row.version > cursor.version || (row.version === cursor.version && row.symbol > cursor.symbol)
}

function byVersionThenSymbol(a: WatchlistRow, b: WatchlistRow): number {
  return a.version - b.version || (a.symbol < b.symbol ? -1 : a.symbol > b.symbol ? 1 : 0)
}

/** In-memory twin of NeonWatchlistRepository, for service and route tests. It must pass the same contract suite. */
export class MockWatchlistRepository implements WatchlistRepository {
  private readonly versions = new Map<string, number>()
  private readonly rows = new Map<string, WatchlistRow>()

  seedUser(userId: string): void {
    if (!this.versions.has(userId)) this.versions.set(userId, 0)
  }

  setLastStatus(userId: string, symbol: string, status: string | null): void {
    const row = this.rows.get(this.key(userId, symbol))
    if (row) this.rows.set(this.key(userId, symbol), { ...row, lastStatus: status })
  }

  clear(): void {
    this.versions.clear()
    this.rows.clear()
  }

  async push(userId: string, changes: WatchlistChange[], _now: Date): Promise<string[]> {
    if (changes.length === 0) return []
    const current = this.versions.get(userId)
    if (current === undefined) return []
    const version = current + 1
    this.versions.set(userId, version)
    const applied: string[] = []
    for (const change of changes) {
      const key = this.key(userId, change.symbol)
      const existing = this.rows.get(key)
      if (existing && existing.clientUpdatedAt.getTime() >= change.clientUpdatedAt.getTime()) continue
      const ladder = normalizeLadder(change.ladder)
      const keepStatus = existing !== undefined && sameAnchors(existing.ladder, ladder)
      this.rows.set(key, {
        ...change,
        ladder,
        checklist: structuredClone(change.checklist),
        ladderHistory: structuredClone(change.ladderHistory),
        version,
        lastStatus: keepStatus ? existing.lastStatus : null,
        lastEvaluatedPrice: existing?.lastEvaluatedPrice ?? null,
      })
      applied.push(change.symbol)
    }
    return applied.sort()
  }

  async pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]> {
    return this.rowsFor(userId)
      .filter((row) => isAfter(row, after))
      .sort(byVersionThenSymbol)
      .slice(0, limit)
  }

  async findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]> {
    const wanted = new Set(symbols)
    return this.rowsFor(userId)
      .filter((row) => wanted.has(row.symbol))
      .sort((a, b) => (a.symbol < b.symbol ? -1 : 1))
  }

  private key(userId: string, symbol: string): string {
    return `${userId}\u0000${symbol}`
  }

  private rowsFor(userId: string): WatchlistRow[] {
    const prefix = `${userId}\u0000`
    return [...this.rows.entries()].filter(([key]) => key.startsWith(prefix)).map(([, row]) => row)
  }
}
```

- [x] **Step 4: Run both contract suites and confirm they pass**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/db/MockWatchlistRepository.test.ts test/db/NeonWatchlistRepository.test.ts`
Expected: PASS, `Test Files  2 passed (2)`, `Tests  22 passed (22)`.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/db/MockWatchlistRepository.ts server/test/db/MockWatchlistRepository.test.ts
git commit -m "$(cat <<'MSG'
test(server): in-memory watchlist repository sharing the SQL contract suite

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

## Chunk 3: Server sync service and routes

### Task 6: `WatchlistSyncService`

**Files:**
- Create: `server/src/services/WatchlistSyncService.ts`
- Test: `server/test/services/WatchlistSyncService.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/services/WatchlistSyncService.test.ts`:
```ts
import { beforeEach, describe, expect, it } from "vitest"
import { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { WatchlistSyncService } from "../../src/services/WatchlistSyncService.js"
import { at, makeChange } from "../support/watchlist.js"

const now = at(60_000)

describe("WatchlistSyncService.sync", () => {
  let repository: MockWatchlistRepository
  let service: WatchlistSyncService

  beforeEach(() => {
    repository = new MockWatchlistRepository()
    repository.seedUser("u1")
    service = new WatchlistSyncService(repository)
  })

  it("pushes changes, then pulls them back with a cursor", async () => {
    const result = await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" })] }, now)
    expect(result.changes.map((row) => [row.symbol, row.version])).toEqual([["AAPL", 1]])
    expect(result.cursor).toBe("1:AAPL")
    expect(result.hasMore).toBe(false)
  })

  it("pulls nothing new from an up-to-date cursor", async () => {
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" })] }, now)
    const result = await service.sync("u1", { cursor: "1:AAPL", changes: [] }, now)
    expect(result).toEqual({ changes: [], cursor: "1:AAPL", hasMore: false })
  })

  it("returns the current row for a rejected (older) change, even when it is behind the cursor", async () => {
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL", memo: "server", clientUpdatedAt: at(2_000) })] }, now)
    const result = await service.sync(
      "u1",
      { cursor: "1:AAPL", changes: [makeChange({ symbol: "AAPL", memo: "stale", clientUpdatedAt: at(1_000) })] },
      now,
    )
    expect(result.changes.map((row) => [row.symbol, row.memo])).toEqual([["AAPL", "server"]])
    expect(result.cursor).toBe("1:AAPL")
  })

  it("clamps client timestamps to now + 5 minutes", async () => {
    const future = new Date(now.getTime() + 60 * 60 * 1000)
    const result = await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL", clientUpdatedAt: future })] }, now)
    expect(result.changes[0]!.clientUpdatedAt.toISOString()).toBe(new Date(now.getTime() + 5 * 60 * 1000).toISOString())
  })

  it("dedupes repeated symbols, keeping the latest change", async () => {
    const result = await service.sync(
      "u1",
      {
        cursor: null,
        changes: [
          makeChange({ symbol: "AAPL", memo: "late", clientUpdatedAt: at(3_000) }),
          makeChange({ symbol: "AAPL", memo: "early", clientUpdatedAt: at(1_000) }),
        ],
      },
      now,
    )
    expect(result.changes.map((row) => row.memo)).toEqual(["late"])
  })

  it("reports hasMore when a pull fills the 500-row page", async () => {
    const changes = Array.from({ length: 501 }, (_, index) => makeChange({ symbol: `S${String(index).padStart(3, "0")}` }))
    await repository.push("u1", changes, now)
    const first = await service.sync("u1", { cursor: null, changes: [] }, now)
    expect([first.changes.length, first.hasMore, first.cursor]).toEqual([500, true, "1:S499"])
    const second = await service.sync("u1", { cursor: first.cursor, changes: [] }, now)
    expect([second.changes.map((row) => row.symbol), second.hasMore]).toEqual([["S500"], false])
  })

  it("rejects an invalid ladder with INVALID_LADDER naming the symbol", async () => {
    const change = makeChange({ symbol: "NVDA", ladder: { buyLow: "12", buyHigh: "16", fair: "10", trim: null, sell: null } })
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_LADDER",
      statusCode: 400,
      message: "NVDA: buyHigh is above fair",
    })
  })

  it("rejects a non-positive anchor with INVALID_LADDER", async () => {
    const change = makeChange({ symbol: "NVDA", ladder: { buyLow: "0", buyHigh: null, fair: null, trim: null, sell: null } })
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_LADDER",
      message: "NVDA: buyLow must be greater than 0",
    })
  })

  it.each([
    ["memo", makeChange({ symbol: "AAPL", memo: "x".repeat(10_001) }), "AAPL: memo is longer than 10000 characters"],
    ["name", makeChange({ symbol: "AAPL", name: "x".repeat(501) }), "AAPL: name is longer than 500 characters"],
    [
      "checklist size",
      makeChange({ symbol: "AAPL", checklist: Array.from({ length: 101 }, (_, i) => ({ id: `c${i}`, name: "q", isChecked: false })) }),
      "AAPL: checklist has more than 100 items",
    ],
    [
      "checklist name",
      makeChange({ symbol: "AAPL", checklist: [{ id: "c1", name: "q".repeat(501), isChecked: false }] }),
      "AAPL: checklist item name is longer than 500 characters",
    ],
    [
      "history",
      makeChange({
        symbol: "AAPL",
        ladderHistory: Array.from({ length: 201 }, () => ({ date: "2026-01-01T00:00:00.000Z", ladder: { buyHigh: "1" } })),
      }),
      "AAPL: ladderHistory has more than 200 entries",
    ],
  ])("rejects an oversized %s with INVALID_INPUT", async (_label, change, message) => {
    await expect(service.sync("u1", { cursor: null, changes: [change] }, now)).rejects.toMatchObject({
      code: "INVALID_INPUT",
      statusCode: 400,
      message,
    })
  })

  it("rejects more than 200 changes", async () => {
    const changes = Array.from({ length: 201 }, (_, index) => makeChange({ symbol: `S${index}` }))
    await expect(service.sync("u1", { cursor: null, changes }, now)).rejects.toMatchObject({ code: "INVALID_INPUT" })
  })

  it("rejects a malformed cursor", async () => {
    await expect(service.sync("u1", { cursor: "nope", changes: [] }, now)).rejects.toMatchObject({
      code: "INVALID_INPUT",
      message: "Invalid sync cursor",
    })
  })
})

describe("WatchlistSyncService.list", () => {
  it("returns live items only, with the cursor of the newest row", async () => {
    const repository = new MockWatchlistRepository()
    repository.seedUser("u1")
    const service = new WatchlistSyncService(repository)
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "AAPL" }), makeChange({ symbol: "MSFT" })] }, now)
    await service.sync("u1", { cursor: null, changes: [makeChange({ symbol: "MSFT", deleted: true, clientUpdatedAt: at(5_000) })] }, now)
    const result = await service.list("u1")
    expect(result.items.map((row) => row.symbol)).toEqual(["AAPL"])
    expect(result.cursor).toBe("2:MSFT")
  })
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/services/WatchlistSyncService.test.ts`
Expected: FAIL with `Failed to load url ../../src/services/WatchlistSyncService.js`.

- [x] **Step 3: Write the implementation**

Create `server/src/services/WatchlistSyncService.ts`:
```ts
import type { WatchlistRepository } from "../db/WatchlistRepository.js"
import {
  START_CURSOR,
  decodeCursor,
  encodeCursor,
  type SyncCursor,
  type WatchlistChange,
  type WatchlistRow,
} from "../db/watchlistTypes.js"
import { validateLadder } from "../domain/ladder.js"
import { AppError } from "../lib/errors.js"

export const SYNC_PUSH_LIMIT = 200
export const SYNC_PULL_LIMIT = 500
export const LIST_LIMIT = 5_000
export const MAX_MEMO_LENGTH = 10_000
export const MAX_NAME_LENGTH = 500
export const MAX_CHECKLIST_ITEMS = 100
export const MAX_LADDER_HISTORY = 200
export const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000

export type SyncRequest = { cursor: string | null; changes: WatchlistChange[] }
export type SyncResult = { changes: WatchlistRow[]; cursor: string; hasMore: boolean }
export type ListResult = { items: WatchlistRow[]; cursor: string }

function invalidInput(message: string): AppError {
  return new AppError("INVALID_INPUT", message, 400)
}

function validateChange(change: WatchlistChange): void {
  const { symbol } = change
  const ladder = validateLadder(change.ladder)
  if (!ladder.ok) {
    const detail = ladder.kind === "nonPositive" ? `${ladder.rung} must be greater than 0` : `${ladder.lower} is above ${ladder.upper}`
    throw new AppError("INVALID_LADDER", `${symbol}: ${detail}`, 400)
  }
  if (change.name.length > MAX_NAME_LENGTH) throw invalidInput(`${symbol}: name is longer than ${MAX_NAME_LENGTH} characters`)
  if (change.memo.length > MAX_MEMO_LENGTH) throw invalidInput(`${symbol}: memo is longer than ${MAX_MEMO_LENGTH} characters`)
  if (change.checklist.length > MAX_CHECKLIST_ITEMS) {
    throw invalidInput(`${symbol}: checklist has more than ${MAX_CHECKLIST_ITEMS} items`)
  }
  if (change.checklist.some((entry) => entry.name.length > MAX_NAME_LENGTH)) {
    throw invalidInput(`${symbol}: checklist item name is longer than ${MAX_NAME_LENGTH} characters`)
  }
  if (change.ladderHistory.length > MAX_LADDER_HISTORY) {
    throw invalidInput(`${symbol}: ladderHistory has more than ${MAX_LADDER_HISTORY} entries`)
  }
}

function clamp(change: WatchlistChange, now: Date): WatchlistChange {
  const limit = now.getTime() + MAX_CLOCK_SKEW_MS
  return change.clientUpdatedAt.getTime() > limit ? { ...change, clientUpdatedAt: new Date(limit) } : change
}

/** One row per symbol; the latest clientUpdatedAt wins, and later entries win ties. */
function dedupeLatest(changes: WatchlistChange[]): WatchlistChange[] {
  const latest = new Map<string, WatchlistChange>()
  for (const change of changes) {
    const existing = latest.get(change.symbol)
    if (!existing || existing.clientUpdatedAt.getTime() <= change.clientUpdatedAt.getTime()) latest.set(change.symbol, change)
  }
  return [...latest.values()]
}

function cursorOf(row: WatchlistRow | undefined, fallback: SyncCursor): string {
  return encodeCursor(row ? { version: row.version, symbol: row.symbol } : fallback)
}

export class WatchlistSyncService {
  constructor(private readonly repository: WatchlistRepository) {}

  /** Overview §8.5, server steps 1–6. */
  async sync(userId: string, request: SyncRequest, now: Date): Promise<SyncResult> {
    const cursor = decodeCursor(request.cursor)
    if (!cursor) throw invalidInput("Invalid sync cursor")
    if (request.changes.length > SYNC_PUSH_LIMIT) throw invalidInput(`At most ${SYNC_PUSH_LIMIT} changes per request`)
    request.changes.forEach(validateChange)

    const changes = dedupeLatest(request.changes.map((change) => clamp(change, now)))
    const applied = new Set(await this.repository.push(userId, changes, now))
    const rejected = changes.map((change) => change.symbol).filter((symbol) => !applied.has(symbol))

    const pulled = await this.repository.pull(userId, cursor, SYNC_PULL_LIMIT)
    const pulledSymbols = new Set(pulled.map((row) => row.symbol))
    const current = rejected.length > 0 ? await this.repository.findBySymbols(userId, rejected) : []
    const extra = current.filter((row) => !pulledSymbols.has(row.symbol))

    return {
      changes: [...pulled, ...extra],
      cursor: cursorOf(pulled.at(-1), cursor),
      hasMore: pulled.length === SYNC_PULL_LIMIT,
    }
  }

  async list(userId: string): Promise<ListResult> {
    const rows = await this.repository.pull(userId, START_CURSOR, LIST_LIMIT)
    return { items: rows.filter((row) => !row.deleted), cursor: cursorOf(rows.at(-1), START_CURSOR) }
  }
}
```

- [x] **Step 4: Run the test and confirm it passes**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/services/WatchlistSyncService.test.ts`
Expected: PASS, `Tests  16 passed (16)`.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/services/WatchlistSyncService.ts server/test/services/WatchlistSyncService.test.ts
git commit -m "$(cat <<'MSG'
feat(server): watchlist sync service (validate, clamp, dedupe, push, pull)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 7: Schemas, routes and wiring (`POST /api/watchlist/sync`, `GET /api/watchlist`)

**Files:**
- Create: `server/src/schemas/watchlist.ts`
- Create: `server/src/routes/api/watchlist.ts`
- Modify: `server/src/container.ts` (the `Container` interface, `createContainer`, `createMockContainer`)
- Modify: `server/src/app.ts` (route registration inside `buildApp`)
- Test: `server/test/routes/watchlist.test.ts`

- [x] **Step 1: Write the failing test**

Create `server/test/routes/watchlist.test.ts`:
```ts
import type { FastifyInstance } from "fastify"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { MockWatchlistRepository } from "../../src/db/MockWatchlistRepository.js"
import { fixedClock } from "../../src/lib/clock.js"
import { buildTestApp } from "../support/app.js"

const LADDER = { buyLow: null, buyHigh: "175", fair: null, trim: null, sell: null }

function change(overrides: Record<string, unknown> = {}) {
  return {
    symbol: "AAPL",
    name: "Apple Inc.",
    ladder: LADDER,
    memo: "Wait for 175\nthen re-check margins",
    isFavorite: true,
    sortIndex: 0,
    checklist: [{ id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true }],
    ladderHistory: [{ date: "2026-11-01T00:00:00.000Z", ladder: { buyHigh: "180" } }],
    clientUpdatedAt: "2026-11-20T15:00:00.000Z",
    deleted: false,
    ...overrides,
  }
}

describe("watchlist routes", () => {
  let app: FastifyInstance
  let headers: Record<string, string>

  beforeEach(async () => {
    // Every clientUpdatedAt below is earlier than this, so the +5 min clamp never rewrites one.
    const built = await buildTestApp({ clock: fixedClock(new Date("2026-11-22T12:00:00.000Z")) })
    app = built.app
    headers = built.authHeaders()
    ;(built.container.watchlist as MockWatchlistRepository).seedUser(built.user.id)
  })

  afterEach(async () => {
    await app.close()
  })

  async function sync(payload: unknown) {
    return app.inject({ method: "POST", url: "/api/watchlist/sync", headers, payload: payload as Record<string, unknown> })
  }

  it("requires a bearer token", async () => {
    const response = await app.inject({ method: "POST", url: "/api/watchlist/sync", payload: { cursor: null, changes: [] } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("rejects an invalid body without a token with 401, not 400 (auth runs onRequest, before validation)", async () => {
    const response = await app.inject({ method: "POST", url: "/api/watchlist/sync", payload: { changes: "not-an-array", extra: 1 } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("round-trips a change with its version and cursor", async () => {
    const response = await sync({ cursor: null, changes: [change()] })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ changes: [{ ...change(), version: 1 }], cursor: "1:AAPL", hasMore: false })
  })

  it("accepts an omitted cursor and a legacy non-US symbol", async () => {
    const response = await sync({ changes: [change({ symbol: "0700.HK" })] })
    expect(response.statusCode).toBe(200)
    expect(response.json().changes[0].symbol).toBe("0700.HK")
  })

  it("returns 400 INVALID_LADDER naming the symbol", async () => {
    const response = await sync({ cursor: null, changes: [change({ ladder: { ...LADDER, buyLow: "200" } })] })
    expect(response.statusCode).toBe(400)
    expect(response.json()).toEqual({ error: { code: "INVALID_LADDER", message: "AAPL: buyLow is above buyHigh" } })
  })

  // The unknown-field case depends on plan 04's buildApp Ajv options (removeAdditional: false, overview §8.1).
  // With Fastify's defaults, the extra field would be stripped silently and the request would return 200.
  it("returns 400 VALIDATION_ERROR for a lowercase symbol, an unknown field or a malformed timestamp", async () => {
    expect((await sync({ cursor: null, changes: [change({ symbol: "aapl" })] })).json().error.code).toBe("VALIDATION_ERROR")
    expect((await sync({ cursor: null, changes: [change({ extra: true })] })).json().error.code).toBe("VALIDATION_ERROR")
    expect((await sync({ cursor: null, changes: [change({ clientUpdatedAt: "yesterday" })] })).json().error.code).toBe("VALIDATION_ERROR")
  })

  it("returns the stored row when an older change loses", async () => {
    await sync({ cursor: null, changes: [change({ memo: "server copy", clientUpdatedAt: "2026-11-20T16:00:00.000Z" })] })
    const response = await sync({ cursor: "1:AAPL", changes: [change({ memo: "stale", clientUpdatedAt: "2026-11-20T15:00:00.000Z" })] })
    expect(response.json().changes.map((row: { memo: string }) => row.memo)).toEqual(["server copy"])
  })

  it("GET /api/watchlist lists live items only", async () => {
    await sync({ cursor: null, changes: [change(), change({ symbol: "MSFT" })] })
    await sync({ cursor: null, changes: [change({ symbol: "MSFT", deleted: true, clientUpdatedAt: "2026-11-21T15:00:00.000Z" })] })
    const response = await app.inject({ method: "GET", url: "/api/watchlist", headers })
    expect(response.statusCode).toBe(200)
    expect(response.json().items.map((row: { symbol: string }) => row.symbol)).toEqual(["AAPL"])
    expect(response.json().cursor).toBe("2:MSFT")
  })
})
```

- [x] **Step 2: Run the test and confirm it fails**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/routes/watchlist.test.ts`
Expected: FAIL. `container.watchlist` is `undefined`, so `seedUser` throws `TypeError: Cannot read properties of undefined (reading 'seedUser')`, and none of the routes exist yet.

- [x] **Step 3: Write the schemas and DTO mapping**

Create `server/src/schemas/watchlist.ts`:
```ts
import { Type, type Static } from "@sinclair/typebox"
import type { WatchlistChange, WatchlistRow } from "../db/watchlistTypes.js"

/** Wider than the market-route symbol pattern on purpose (plan 05, deviation 1): legacy non-US symbols must never block sync. */
export const SYNC_SYMBOL_PATTERN = "^[A-Z0-9][A-Z0-9.-]{0,14}$"
const DECIMAL_PATTERN = "^(0|[1-9][0-9]{0,11})(\\.[0-9]{1,6})?$"
const ISO_TIMESTAMP_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?Z$"

// Null-first unions (overview §8.1): with plan 04's Ajv options null is never coerced, and listing Null first is a second safeguard.
const NullableDecimal = Type.Union([Type.Null(), Type.String({ pattern: DECIMAL_PATTERN })])
const IsoTimestamp = Type.String({ pattern: ISO_TIMESTAMP_PATTERN })

export const LadderSchema = Type.Object(
  {
    buyLow: Type.Optional(NullableDecimal),
    buyHigh: Type.Optional(NullableDecimal),
    fair: Type.Optional(NullableDecimal),
    trim: Type.Optional(NullableDecimal),
    sell: Type.Optional(NullableDecimal),
  },
  { additionalProperties: false },
)

export const ChecklistEntrySchema = Type.Object(
  { id: Type.String({ minLength: 1, maxLength: 64 }), name: Type.String(), isChecked: Type.Boolean() },
  { additionalProperties: false },
)

export const LadderHistoryEntrySchema = Type.Object({ date: IsoTimestamp, ladder: LadderSchema }, { additionalProperties: false })

// Size limits (memo, names, counts) are enforced by WatchlistSyncService, so the error names the symbol.
const itemFields = {
  symbol: Type.String({ pattern: SYNC_SYMBOL_PATTERN }),
  name: Type.String(),
  ladder: LadderSchema,
  memo: Type.String(),
  isFavorite: Type.Boolean(),
  sortIndex: Type.Integer({ minimum: -1_000_000, maximum: 1_000_000 }),
  checklist: Type.Array(ChecklistEntrySchema),
  ladderHistory: Type.Array(LadderHistoryEntrySchema),
  clientUpdatedAt: IsoTimestamp,
  deleted: Type.Boolean(),
}

export const WatchlistChangeSchema = Type.Object(itemFields, { additionalProperties: false })
export const WatchlistItemSchema = Type.Object({ ...itemFields, version: Type.Integer({ minimum: 0 }) })

export const SyncBodySchema = Type.Object(
  {
    cursor: Type.Optional(Type.Union([Type.Null(), Type.String({ maxLength: 64 })])),
    changes: Type.Array(WatchlistChangeSchema, { maxItems: 200 }),
  },
  { additionalProperties: false },
)
export const SyncResponseSchema = Type.Object({
  changes: Type.Array(WatchlistItemSchema),
  cursor: Type.String(),
  hasMore: Type.Boolean(),
})
export const WatchlistListResponseSchema = Type.Object({ items: Type.Array(WatchlistItemSchema), cursor: Type.String() })

export type WatchlistChangeDto = Static<typeof WatchlistChangeSchema>
export type WatchlistItemDto = Static<typeof WatchlistItemSchema>

export function toWatchlistChange(dto: WatchlistChangeDto): WatchlistChange {
  return {
    symbol: dto.symbol,
    name: dto.name,
    ladder: {
      buyLow: dto.ladder.buyLow ?? null,
      buyHigh: dto.ladder.buyHigh ?? null,
      fair: dto.ladder.fair ?? null,
      trim: dto.ladder.trim ?? null,
      sell: dto.ladder.sell ?? null,
    },
    memo: dto.memo,
    isFavorite: dto.isFavorite,
    sortIndex: dto.sortIndex,
    checklist: dto.checklist,
    ladderHistory: dto.ladderHistory,
    clientUpdatedAt: new Date(dto.clientUpdatedAt),
    deleted: dto.deleted,
  }
}

export function toWatchlistItemDto(row: WatchlistRow): WatchlistItemDto {
  return {
    symbol: row.symbol,
    name: row.name,
    ladder: row.ladder,
    memo: row.memo,
    isFavorite: row.isFavorite,
    sortIndex: row.sortIndex,
    checklist: row.checklist,
    ladderHistory: row.ladderHistory,
    clientUpdatedAt: row.clientUpdatedAt.toISOString(),
    deleted: row.deleted,
    version: row.version,
  }
}
```

- [x] **Step 4: Write the route plugin**

Create `server/src/routes/api/watchlist.ts`:
```ts
import type { TypeBoxTypeProvider } from "@fastify/type-provider-typebox"
import type { FastifyPluginAsync } from "fastify"
import type { RouteOptions } from "../../container.js"
import { buildAuthMiddleware } from "../../middleware/auth.js"
import { ErrorResponseSchema } from "../../schemas/common.js"
import {
  SyncBodySchema,
  SyncResponseSchema,
  WatchlistListResponseSchema,
  toWatchlistChange,
  toWatchlistItemDto,
} from "../../schemas/watchlist.js"

/** Vercel caps request bodies at 4.5 MB. The iOS client sends at most 50 changes per request. */
const SYNC_BODY_LIMIT = 4 * 1024 * 1024

const watchlistRoutes: FastifyPluginAsync<RouteOptions> = async (server, { container }) => {
  const app = server.withTypeProvider<TypeBoxTypeProvider>()
  const { authenticate } = buildAuthMiddleware(container.users)

  app.post(
    "/sync",
    {
      // onRequest, as in plan 04: an unauthenticated request gets 401 before the body is validated.
      onRequest: [authenticate],
      bodyLimit: SYNC_BODY_LIMIT,
      schema: {
        body: SyncBodySchema,
        response: { 200: SyncResponseSchema, 400: ErrorResponseSchema, 401: ErrorResponseSchema },
      },
    },
    async (request) => {
      const result = await container.watchlistSync.sync(
        request.authenticatedUser.id,
        { cursor: request.body.cursor ?? null, changes: request.body.changes.map(toWatchlistChange) },
        container.clock.now(),
      )
      return { changes: result.changes.map(toWatchlistItemDto), cursor: result.cursor, hasMore: result.hasMore }
    },
  )

  app.get(
    "/",
    { onRequest: [authenticate], schema: { response: { 200: WatchlistListResponseSchema, 401: ErrorResponseSchema } } },
    async (request) => {
      const result = await container.watchlistSync.list(request.authenticatedUser.id)
      return { items: result.items.map(toWatchlistItemDto), cursor: result.cursor }
    },
  )
}

export default watchlistRoutes
```

- [x] **Step 5: Wire the container**

In `server/src/container.ts`, add these imports next to the other repository and service imports:
```ts
import { MockWatchlistRepository } from "./db/MockWatchlistRepository.js"
import { NeonWatchlistRepository } from "./db/NeonWatchlistRepository.js"
import type { WatchlistRepository } from "./db/WatchlistRepository.js"
import { WatchlistSyncService } from "./services/WatchlistSyncService.js"
```
Add two members to the `Container` interface:
```ts
  watchlist: WatchlistRepository
  watchlistSync: WatchlistSyncService
```
In `createContainer(config)`, plan 04 builds `const sql = neonSql(config.databaseUrl)` and then each repository from it. Add the watchlist repository after `const users = …`, and add both members to the returned object literal:
```ts
  const watchlist = new NeonWatchlistRepository(sql)
  // returned object literal, after `auth: …`:
    watchlist,
    watchlistSync: new WatchlistSyncService(watchlist),
```
In `createMockContainer(overrides)`, follow plan 04's `overrides.x ?? default` pattern. Add this after `const rateLimiter = …`:
```ts
  const watchlist = overrides.watchlist ?? new MockWatchlistRepository()
  // returned object literal, after `auth: …`:
    watchlist,
    watchlistSync: overrides.watchlistSync ?? new WatchlistSyncService(watchlist),
```

- [x] **Step 6: Register the routes**

In `server/src/app.ts`, add the import next to the other route imports:
```ts
import watchlistRoutes from "./routes/api/watchlist.js"
```
Then, inside `buildApp`, register the plugin directly after the `/api/market` registration:
```ts
  await app.register(watchlistRoutes, { prefix: "/api/watchlist", container })
```

- [x] **Step 7: Run the route tests and confirm they pass**

Run: `cd /Users/ckai/code/Wait-plan05/server && npx vitest run test/routes/watchlist.test.ts`
Expected: PASS, `Tests  8 passed (8)`.

- [x] **Step 8: Run the whole server suite and the typecheck**

Run: `cd /Users/ckai/code/Wait-plan05/server && npm run typecheck && npm test`
Expected: `tsc` exits 0. vitest shows every file passing, including plan 04's suites and this plan's 7 new files: `ladder`, `migration003`, `watchlistTypes`, `NeonWatchlistRepository`, `MockWatchlistRepository`, `WatchlistSyncService`, `watchlist` routes.

- [x] **Step 9: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add server/src/schemas/watchlist.ts server/src/routes/api/watchlist.ts server/src/container.ts server/src/app.ts \
  server/test/routes/watchlist.test.ts
git commit -m "$(cat <<'MSG'
feat(server): POST /api/watchlist/sync and GET /api/watchlist

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 10: Apply the migration in production (manual: user)** — SKIPPED (manual)

After this branch is deployed to the Vercel production project:
```bash
cd /Users/ckai/code/Wait-plan05/server
vercel env pull .env.local --environment=production   # without the flag, Vercel pulls the development env
npm run migrate                                       # applies migrations/003_watchlist.sql
```
Expected: plan 04's runner prints `migrations applied: [3] skipped: [1, 2]`. A second `npm run migrate` prints `migrations applied: [] skipped: [1, 2, 3]`.

## Chunk 4: iOS sync core (state, stamps, planner)

Shared iOS facts for Chunks 4–7:
- **Package commands** (overview §5.1), run from `Wait/Packages/WaitKit`:
  ```bash
  cd /Users/ckai/code/Wait-plan05/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
    -only-testing:<Target>Tests/<Suite>
  ```
  With an `-only-testing` filter, a passing run ends in `** TEST SUCCEEDED **`, and a failing one ends in `** TEST FAILED **` (or `** TEST BUILD FAILED **` when the code doesn't compile yet).
- **`WatchlistItem` and `ChecklistItem`** are built with plan 02's public memberwise initializers:
  - `WatchlistItem(symbol:name:ladder:memo:isFavorite:sortIndex:checklist:ladderHistory:createdAt:updatedAt:)`
  - `ChecklistItem(id:name:isChecked:)`

  If plan 02 declared different labels, keep plan 02's and adjust the test fixtures.
- **File headers** use the overview §5.1 template with the execution date. MARK layout follows CLAUDE.md.

### Task 8: `SyncState` and tombstone bookkeeping in Persistence

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Persistence/SyncState.swift`
- Modify: `Wait/Packages/WaitKit/Sources/Persistence/Shared+Watchlist.swift`, in the `add(_:now:)` and `remove(_:now:)` helpers
- Modify: `Wait/Packages/WaitKit/Package.swift` (the `PersistenceTests` dependencies)
- Test: `Wait/Packages/WaitKit/Tests/PersistenceTests/SyncStateTests.swift`

- [ ] **Step 0: Declare the test target's imports**

The new test imports `Dependencies`, `DependenciesTestSupport`, `Domain`, `IdentifiedCollections`, `Persistence` and `Sharing`. Plan 02's `.testTarget(name: "PersistenceTests", …)` lists `"Persistence", .sharing, .identifiedCollections, .dependenciesTestSupport`. Add `"Domain"` and `.dependencies` to that array, so it reads:
```swift
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain", .dependencies, .sharing, .identifiedCollections, .dependenciesTestSupport]),
```

- [ ] **Step 1: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/PersistenceTests/SyncStateTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesTestSupport
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
import Testing

// MARK: - SyncStateTests

@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SyncStateTests {
  // MARK: Internal

  @Test
  func removeRecordsTombstoneTruncatedToMilliseconds() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState
    $items.add(item("AAPL"), now: now)

    $items.remove("AAPL", now: now)

    #expect(syncState.tombstones["AAPL"] == now.truncatedToMilliseconds)
    #expect(items[id: "AAPL"] == nil)
  }

  @Test
  func removeOfUnknownSymbolRecordsNothing() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState

    $items.remove("TSLA", now: now)

    #expect(syncState.tombstones.isEmpty)
  }

  @Test
  func addClearsTombstone() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState
    $items.add(item("AAPL"), now: now)
    $items.remove("AAPL", now: now)

    $items.add(item("AAPL"), now: now.addingTimeInterval(60))

    #expect(syncState.tombstones["AAPL"] == nil)
    #expect(items[id: "AAPL"] != nil)
  }

  @Test
  func decodesEmptyObjectAsInitial() throws {
    let state = try JSONDecoder().decode(SyncState.self, from: Data("{}".utf8))
    #expect(state == .initial)
  }

  @Test
  func roundTripsThroughJSON() throws {
    let state = SyncState(
      cursor: "3:AAPL",
      acknowledged: ["AAPL": now.truncatedToMilliseconds],
      tombstones: ["MSFT": now.truncatedToMilliseconds],
      lastSyncedAt: now.truncatedToMilliseconds
    )
    let decoded = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
  }

  // MARK: Private

  private let now = Date(timeIntervalSince1970: 1_795_186_800.123_456)

  private func item(_ symbol: String) -> WatchlistItem {
    WatchlistItem(
      symbol: symbol,
      name: "\(symbol) Inc.",
      ladder: .empty,
      memo: "",
      isFavorite: false,
      sortIndex: 0,
      checklist: [],
      ladderHistory: [],
      createdAt: now,
      updatedAt: now
    )
  }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run, with `-only-testing:PersistenceTests/SyncStateTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **`. The errors include `cannot find 'SyncState' in scope`, and the `@Shared(.syncState)` lines fail because no member `syncState` exists yet.

- [ ] **Step 3: Write `SyncState`**

Create `Wait/Packages/WaitKit/Sources/Persistence/SyncState.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Sharing

// MARK: - SyncState

/// Client sync bookkeeping (overview §8.5), stored in the app group as `sync-state.json`.
public struct SyncState: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    cursor: String? = nil,
    acknowledged: [String: Date] = [:],
    tombstones: [String: Date] = [:],
    lastSyncedAt: Date? = nil
  ) {
    self.cursor = cursor
    self.acknowledged = acknowledged
    self.tombstones = tombstones
    self.lastSyncedAt = lastSyncedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
    acknowledged = try container.decodeIfPresent([String: Date].self, forKey: .acknowledged) ?? [:]
    tombstones = try container.decodeIfPresent([String: Date].self, forKey: .tombstones) ?? [:]
    lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
  }

  // MARK: Public

  public static let initial = SyncState()

  /// The server cursor `"<version>:<symbol>"`. `nil` before the first sync.
  public var cursor: String?
  /// For each symbol, the stamp (item `updatedAt` or tombstone date) that the server last acknowledged.
  public var acknowledged: [String: Date]
  /// Local deletions, by symbol. Kept until a newer remote or local version of the symbol replaces them.
  public var tombstones: [String: Date]
  public var lastSyncedAt: Date?

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case cursor
    case acknowledged
    case tombstones
    case lastSyncedAt
  }
}

// MARK: - AppGroup + syncStateFileName

public extension AppGroup {
  static let syncStateFileName = "sync-state.json"
}

// MARK: - SharedReaderKey + syncState

/// Declared once on `SharedReaderKey`, like plan 02's `.watchlist` and `.checklistTemplate` keys. One declaration
/// resolves for both `@Shared(.syncState)` and `@SharedReader(.syncState)`. Don't add a twin on `SharedKey`, because
/// that makes `@Shared(.syncState)` ambiguous.
public extension SharedReaderKey where Self == FileStorageKey<SyncState>.Default {
  static var syncState: Self {
    Self[.fileStorage(AppGroup.fileURL(AppGroup.syncStateFileName)), default: .initial]
  }
}
```

- [ ] **Step 4: Record and clear tombstones in the mutation helpers**

In `Wait/Packages/WaitKit/Sources/Persistence/Shared+Watchlist.swift`, keep both signatures exactly as plan 02 wrote them.

Insert these lines as the **first statements** of `public func add(_ item: WatchlistItem, now: Date)`:
```swift
    @Shared(.syncState) var syncState
    $syncState.withLock { $0.tombstones[item.symbol] = nil }
```
Plan 02 wrote the body of `add` as a single implicit-return expression, `withLock { … }`. Once these statements come before it, the implicit return no longer applies, so that line must become `return withLock { … }`. Keep the closure's contents unchanged. If the helper returns `Void`, the explicit `return` is still valid and harmless. Apply the same rule to `remove` if its body is also a single `withLock { … }` expression.

In `func remove(_ symbol: String, now: Date)`, delete plan 02's placeholder line `_ = now // Plan 05 records a tombstone at `now`.`, and insert these lines as the **first statements** in its place:
```swift
    if wrappedValue[id: symbol] != nil {
      @Shared(.syncState) var syncState
      $syncState.withLock { $0.tombstones[symbol] = now.truncatedToMilliseconds }
    }
```
The helper's existing body then removes the item exactly as before. Local property wrappers (`@Shared` inside a function) are supported in Swift 5.4 and later.

- [ ] **Step 5: Run the test and confirm it passes**

Run, with `-only-testing:PersistenceTests/SyncStateTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 5 tests passing.

- [ ] **Step 6: Run all Persistence tests (plan 02's helper tests must still pass)**

Run, with `-only-testing:PersistenceTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Persistence/SyncState.swift \
  Wait/Packages/WaitKit/Sources/Persistence/Shared+Watchlist.swift \
  Wait/Packages/WaitKit/Tests/PersistenceTests/SyncStateTests.swift
git commit -m "$(cat <<'MSG'
feat(persistence): sync state file and tombstone bookkeeping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 9: `SyncClient` target, `SyncStamp` and the sync value types

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift`
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncStamp.swift`
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncChange.swift`
- Test: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncStampTests.swift`

- [ ] **Step 1: Add the targets**

In `Wait/Packages/WaitKit/Package.swift`, add these to `targets:`, next to the `APIClient` target. The test target lists every module its files import: `Domain`, `Persistence`, `APIClient`, `Dependencies` (for `LockIsolated`), `Sharing` (`Shared(value:)`) and `IdentifiedCollections`. They use plan 02's `Target.Dependency` statics (`.dependencies`, `.dependenciesMacros`, `.dependenciesTestSupport`, `.sharing`, `.identifiedCollections`):
```swift
    .target(
      name: "SyncClient",
      dependencies: ["Domain", "Persistence", "APIClient", "Logging", .dependencies, .dependenciesMacros, .sharing, .identifiedCollections]
    ),
    .testTarget(
      name: "SyncClientTests",
      dependencies: ["SyncClient", "Domain", "Persistence", "APIClient", .dependencies, .dependenciesTestSupport, .sharing, .identifiedCollections]
    ),
```

- [ ] **Step 2: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncStampTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
@testable import SyncClient
import Testing

struct SyncStampTests {
  @Test
  func formatsWithExactlyThreeFractionDigits() {
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_795_186_800_123)) == "2026-11-20T15:00:00.123Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_795_186_800_000)) == "2026-11-20T15:00:00.000Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 0)) == "1970-01-01T00:00:00.000Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_798_761_599_999)) == "2026-12-31T23:59:59.999Z")
  }

  @Test
  func parsesWithAndWithoutFraction() {
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.123Z").map(SyncStamp.milliseconds) == 1_795_186_800_123)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00Z").map(SyncStamp.milliseconds) == 1_795_186_800_000)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.1234567Z").map(SyncStamp.milliseconds) == 1_795_186_800_123)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.5Z").map(SyncStamp.milliseconds) == 1_795_186_800_500)
  }

  @Test
  func rejectsMalformedStrings() {
    for text in ["", "garbage", "2026-11-20 15:00:00Z", "2026-11-20T15:00:00", "2026-13-20T15:00:00Z", "2026-11-20T15:00:00.Z"] {
      #expect(SyncStamp.date(from: text) == nil, "\(text)")
    }
  }

  @Test
  func comparesByWholeMillisecondsIgnoringDoubleNoise() {
    let base = Date(timeIntervalSince1970: 1_795_186_800.123)
    let noisy = Date(timeIntervalSince1970: (1_795_186_800.123).nextUp)
    let parsed = SyncStamp.date(from: SyncStamp.string(from: base))!
    #expect(SyncStamp.same(base, noisy))
    #expect(SyncStamp.same(base, parsed))
    #expect(!SyncStamp.same(base, base.addingTimeInterval(0.001)))
    #expect(!SyncStamp.same(base, nil))
    #expect(SyncStamp.same(nil, nil))
  }

  @Test
  func reportsAddUp() {
    let sum = SyncReport(pushed: 1, pulled: 2, applied: 3, rounds: 1) + SyncReport(pushed: 4, pulled: 5, applied: 6, rounds: 2)
    #expect(sum == SyncReport(pushed: 5, pulled: 7, applied: 9, rounds: 3))
  }
}
```

- [ ] **Step 3: Run the test and confirm it fails**

Run, with `-only-testing:SyncClientTests/SyncStampTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **`. The `SyncClient` target has no sources yet, so you get `no such module 'SyncClient'` or `cannot find 'SyncStamp' in scope`.

- [ ] **Step 4: Write `SyncStamp`**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncStamp.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - SyncStamp

/// Whole-millisecond timestamps for sync (overview D21; plan 05 deviation 4).
/// Two dates are "the same stamp" when they round to the same Unix millisecond. The wire format is always
/// `yyyy-MM-ddTHH:mm:ss.SSSZ`, built by hand, so Double noise and formatter truncation can't create perpetual pending changes.
public enum SyncStamp {
  // MARK: Public

  public static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  public static func date(milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  }

  public static func same(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
      case (nil, nil):
        true
      case let (lhs?, rhs?):
        milliseconds(lhs) == milliseconds(rhs)
      default:
        false
    }
  }

  public static func string(from date: Date) -> String {
    let total = milliseconds(date)
    let seconds = total >= 0 ? total / 1000 : (total - 999) / 1000
    let fraction = Int(total - seconds * 1000)
    let components = utcCalendar().dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSince1970: Double(seconds))
    )
    return "\(pad(components.year ?? 0, 4))-\(pad(components.month ?? 0, 2))-\(pad(components.day ?? 0, 2))"
      + "T\(pad(components.hour ?? 0, 2)):\(pad(components.minute ?? 0, 2)):\(pad(components.second ?? 0, 2))"
      + ".\(pad(fraction, 3))Z"
  }

  /// Parses `yyyy-MM-ddTHH:mm:ss[.f…]Z` (UTC only). Fractions are rounded to whole milliseconds.
  public static func date(from text: String) -> Date? {
    guard text.hasSuffix("Z") else { return nil }
    let parts = text.dropLast().split(separator: "T", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let dateFields = parts[0].split(separator: "-", omittingEmptySubsequences: false)
    let timeAndFraction = parts[1].split(separator: ".", omittingEmptySubsequences: false)
    guard dateFields.count == 3, (1 ... 2).contains(timeAndFraction.count) else { return nil }
    let timeFields = timeAndFraction[0].split(separator: ":", omittingEmptySubsequences: false)
    guard
      timeFields.count == 3,
      let year = Int(dateFields[0]), dateFields[0].count == 4,
      let month = Int(dateFields[1]), (1 ... 12).contains(month),
      let day = Int(dateFields[2]), (1 ... 31).contains(day),
      let hour = Int(timeFields[0]), (0 ... 23).contains(hour),
      let minute = Int(timeFields[1]), (0 ... 59).contains(minute),
      let second = Int(timeFields[2]), (0 ... 60).contains(second)
    else { return nil }

    var fractionMilliseconds: Int64 = 0
    if timeAndFraction.count == 2 {
      let digits = timeAndFraction[1]
      guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Double("0.\(digits)") else { return nil }
      fractionMilliseconds = Int64((value * 1000).rounded())
    }

    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let whole = utcCalendar().date(from: components) else { return nil }
    return date(milliseconds: Int64(whole.timeIntervalSince1970.rounded()) * 1000 + fractionMilliseconds)
  }

  // MARK: Private

  private static func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
```

- [ ] **Step 5: Write the sync value types**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncChange.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SyncChange

/// One pending local change: an upsert of `item`, or a tombstone when `item` is nil.
public struct SyncChange: Equatable, Sendable {
  // MARK: Public

  public let symbol: String
  public let item: WatchlistItem?
  /// `item.updatedAt`, or the tombstone date.
  public let stamp: Date

  public var isDeletion: Bool {
    item == nil
  }

  public static func upsert(_ item: WatchlistItem) -> SyncChange {
    SyncChange(symbol: item.symbol, item: item, stamp: item.updatedAt)
  }

  public static func deletion(symbol: String, at date: Date) -> SyncChange {
    SyncChange(symbol: symbol, item: nil, stamp: date)
  }
}

// MARK: - RemoteWatchlistItem

/// A server row mapped into Domain types. `item.updatedAt` is the server's `clientUpdatedAt`.
public struct RemoteWatchlistItem: Equatable, Sendable {
  // MARK: Lifecycle

  public init(item: WatchlistItem, isDeleted: Bool, version: Int) {
    self.item = item
    self.isDeleted = isDeleted
    self.version = version
  }

  // MARK: Public

  public let item: WatchlistItem
  public let isDeleted: Bool
  public let version: Int

  public var symbol: String {
    item.symbol
  }

  public var stamp: Date {
    item.updatedAt
  }
}

// MARK: - SyncReport

public struct SyncReport: Equatable, Sendable {
  // MARK: Lifecycle

  public init(pushed: Int = 0, pulled: Int = 0, applied: Int = 0, rounds: Int = 0) {
    self.pushed = pushed
    self.pulled = pulled
    self.applied = applied
    self.rounds = rounds
  }

  // MARK: Public

  public static let empty = SyncReport()

  /// Changes sent to the server.
  public var pushed: Int
  /// Rows received from the server, echoes included.
  public var pulled: Int
  /// Remote rows that were newer than the local copy and replaced or deleted it.
  public var applied: Int
  /// HTTP round trips.
  public var rounds: Int

  public static func + (lhs: SyncReport, rhs: SyncReport) -> SyncReport {
    SyncReport(
      pushed: lhs.pushed + rhs.pushed,
      pulled: lhs.pulled + rhs.pulled,
      applied: lhs.applied + rhs.applied,
      rounds: lhs.rounds + rhs.rounds
    )
  }

  public static func += (lhs: inout SyncReport, rhs: SyncReport) {
    lhs = lhs + rhs
  }
}
```

- [ ] **Step 6: Run the test and confirm it passes**

Run, with `-only-testing:SyncClientTests/SyncStampTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 5 tests passing.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/SyncClient \
  Wait/Packages/WaitKit/Tests/SyncClientTests/SyncStampTests.swift
git commit -m "$(cat <<'MSG'
feat(sync): SyncClient target with millisecond stamps and sync value types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 10: `SyncPlanner`, the pending-change computation (pure)

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncPlanner.swift`
- Create: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncFixtures.swift` (shared test fixtures)
- Test: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncPlannerTests.swift`

- [ ] **Step 1: Write the shared fixtures**

Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncFixtures.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
@testable import SyncClient

/// 2026-11-20T15:00:00.000Z plus `milliseconds`.
func stamp(_ milliseconds: Int64 = 0) -> Date {
  SyncStamp.date(milliseconds: 1_795_186_800_000 + milliseconds)
}

func makeItem(
  _ symbol: String,
  memo: String = "",
  isFavorite: Bool = false,
  sortIndex: Int = 0,
  ladder: PriceLadder = .empty,
  updatedAt: Date = stamp()
) -> WatchlistItem {
  WatchlistItem(
    symbol: symbol,
    name: "\(symbol) Inc.",
    ladder: ladder,
    memo: memo,
    isFavorite: isFavorite,
    sortIndex: sortIndex,
    checklist: [],
    ladderHistory: [],
    createdAt: stamp(),
    updatedAt: updatedAt
  )
}

func remote(_ item: WatchlistItem, deleted: Bool = false, version: Int = 1) -> RemoteWatchlistItem {
  RemoteWatchlistItem(item: item, isDeleted: deleted, version: version)
}
```

- [ ] **Step 2: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncPlannerTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Persistence
@testable import SyncClient
import Testing

struct SyncPlannerTests {
  @Test
  func firstSyncUploadsEveryItemOldestFirst() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("MSFT", updatedAt: stamp(2)), makeItem("AAPL", updatedAt: stamp(1))]
    let pending = SyncPlanner.pendingChanges(items: items, state: .initial)
    #expect(pending.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(pending.allSatisfy { !$0.isDeletion })
  }

  @Test
  func sortsEqualStampsBySymbol() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("NVDA"), makeItem("AAPL")]
    #expect(SyncPlanner.pendingChanges(items: items, state: .initial).map(\.symbol) == ["AAPL", "NVDA"])
  }

  @Test
  func skipsItemsAcknowledgedAtTheSameMillisecond() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(5))]
    let noisy = Date(timeIntervalSince1970: stamp(5).timeIntervalSince1970.nextUp)
    let state = SyncState(acknowledged: ["AAPL": noisy])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).isEmpty)
  }

  @Test
  func includesItemsEditedAfterTheirAcknowledgement() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(9))]
    let state = SyncState(acknowledged: ["AAPL": stamp(5)])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).map(\.stamp) == [stamp(9)])
  }

  @Test
  func includesUnacknowledgedTombstonesOnly() {
    let state = SyncState(acknowledged: ["MSFT": stamp(3)], tombstones: ["AAPL": stamp(4), "MSFT": stamp(3)])
    let pending = SyncPlanner.pendingChanges(items: [], state: state)
    #expect(pending == [.deletion(symbol: "AAPL", at: stamp(4))])
  }

  @Test
  func leavesSymbolsTheServerWouldRejectLocalOnly() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL"), makeItem("BRK B"), makeItem("ÄPPLE"), makeItem("0700.HK")]
    let state = SyncState(tombstones: ["bad symbol": stamp(1)])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).map(\.symbol) == ["0700.HK", "AAPL"])
    #expect(SyncPlanner.unsyncableSymbols(items: items, state: state) == ["BRK B", "bad symbol", "ÄPPLE"])
    #expect(SyncPlanner.isSyncable("BRK.B"))
    #expect(!SyncPlanner.isSyncable(""))
  }

  @Test
  func newerItemWinsOverOlderTombstoneAndViceVersa() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(10)), makeItem("MSFT", updatedAt: stamp(1))]
    let state = SyncState(tombstones: ["AAPL": stamp(5), "MSFT": stamp(6)])
    let pending = SyncPlanner.pendingChanges(items: items, state: state)
    #expect(pending == [.deletion(symbol: "MSFT", at: stamp(6)), .upsert(items[id: "AAPL"]!)])
  }
}
```

- [ ] **Step 3: Run the test and confirm it fails**

Run, with `-only-testing:SyncClientTests/SyncPlannerTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **` with `cannot find 'SyncPlanner' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncPlanner.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import IdentifiedCollections
import Persistence

// MARK: - SyncPlanner

/// Which local changes the server hasn't acknowledged yet (overview §8.5, "Pending changes").
/// The first sync after migrating needs no special case: `acknowledged` starts empty, so every item is pending.
public enum SyncPlanner {
  /// The sync endpoint's symbol pattern (`SYNC_SYMBOL_PATTERN` in `server/src/schemas/watchlist.ts`).
  /// A symbol outside it would make the server reject the whole batch with a 400 on every sync, so it stays local-only.
  public static func isSyncable(_ symbol: String) -> Bool {
    symbol.wholeMatch(of: /[A-Z0-9][A-Z0-9.\-]{0,14}/) != nil
  }

  /// Symbols (items or tombstones) that `pendingChanges` leaves out, sorted. `SyncEngine` logs them.
  public static func unsyncableSymbols(items: IdentifiedArrayOf<WatchlistItem>, state: SyncState) -> [String] {
    Set(items.map(\.symbol)).union(state.tombstones.keys).filter { !isSyncable($0) }.sorted()
  }

  /// One change per symbol: whichever of the item and the tombstone is newer (the item wins a tie).
  /// Unsyncable symbols are skipped. Sorted oldest stamp first, then by symbol.
  public static func pendingChanges(items: IdentifiedArrayOf<WatchlistItem>, state: SyncState) -> [SyncChange] {
    var latest: [String: SyncChange] = [:]
    for item in items {
      latest[item.symbol] = .upsert(item)
    }
    for (symbol, date) in state.tombstones {
      if let existing = latest[symbol], SyncStamp.milliseconds(existing.stamp) >= SyncStamp.milliseconds(date) {
        continue
      }
      latest[symbol] = .deletion(symbol: symbol, at: date)
    }
    return latest.values
      .filter { isSyncable($0.symbol) && !SyncStamp.same(state.acknowledged[$0.symbol], $0.stamp) }
      .sorted { lhs, rhs in
        let left = SyncStamp.milliseconds(lhs.stamp)
        let right = SyncStamp.milliseconds(rhs.stamp)
        return left == right ? lhs.symbol < rhs.symbol : left < right
      }
  }
}
```

- [ ] **Step 5: Run the test and confirm it passes**

Run, with `-only-testing:SyncClientTests/SyncPlannerTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 7 tests passing.

- [ ] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Sources/SyncClient/SyncPlanner.swift \
  Wait/Packages/WaitKit/Tests/SyncClientTests/SyncFixtures.swift Wait/Packages/WaitKit/Tests/SyncClientTests/SyncPlannerTests.swift
git commit -m "$(cat <<'MSG'
feat(sync): pure planner for unacknowledged changes and tombstones

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

## Chunk 5: iOS merger and wire format

### Task 11: `SyncMerger`, acknowledging and applying remote rows (pure)

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncMerger.swift`
- Test: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMergerTests.swift`

- [ ] **Step 1: Write the failing test**

This test covers the full case matrix from overview §8.5, client step 3, plus deviation 2 (ties apply the remote row). Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMergerTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Persistence
@testable import SyncClient
import Testing

struct SyncMergerTests {
  @Test
  func acknowledgeRecordsTheSentStampForUpsertsAndDeletions() {
    let sent: [SyncChange] = [.upsert(makeItem("AAPL", updatedAt: stamp(1))), .deletion(symbol: "MSFT", at: stamp(2))]
    let state = SyncMerger.acknowledge(sent, in: SyncState(acknowledged: ["NVDA": stamp(0)]))
    #expect(state.acknowledged == ["AAPL": stamp(1), "MSFT": stamp(2), "NVDA": stamp(0)])
  }

  @Test
  func insertsANewRemoteItem() {
    let incoming = makeItem("NVDA", memo: "from B", updatedAt: stamp(5))
    let result = SyncMerger.apply([remote(incoming)], to: [], state: .initial)
    #expect(result.items[id: "NVDA"]?.memo == "from B")
    #expect(result.state.acknowledged["NVDA"] == stamp(5))
    #expect(result.applied == 1)
  }

  @Test
  func replacesAnOlderLocalItemButKeepsItsCreatedAt() {
    var local = makeItem("AAPL", memo: "old", updatedAt: stamp(1))
    local.createdAt = stamp(-1000)
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "new", updatedAt: stamp(2)))], to: [local], state: .initial)
    #expect(result.items[id: "AAPL"]?.memo == "new")
    #expect(result.items[id: "AAPL"]?.createdAt == stamp(-1000))
    #expect(result.applied == 1)
  }

  @Test
  func acknowledgesAnIdenticalEchoWithoutCountingIt() {
    let local = makeItem("AAPL", memo: "same", updatedAt: stamp(3))
    let result = SyncMerger.apply([remote(local)], to: [local], state: .initial)
    #expect(result.items == [local])
    #expect(result.state.acknowledged["AAPL"] == stamp(3))
    #expect(result.applied == 0)
  }

  @Test
  func tieAppliesTheRemoteContent() {
    let local = makeItem("AAPL", memo: "device A", updatedAt: stamp(3))
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "server", updatedAt: stamp(3)))], to: [local], state: .initial)
    #expect(result.items[id: "AAPL"]?.memo == "server")
    #expect(result.applied == 0)
  }

  @Test
  func keepsANewerLocalItemPending() {
    let local = makeItem("AAPL", memo: "newer", updatedAt: stamp(9))
    let state = SyncState(acknowledged: ["AAPL": stamp(4)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "older", updatedAt: stamp(4)))], to: [local], state: state)
    #expect(result.items == [local])
    #expect(result.state.acknowledged["AAPL"] == stamp(4))
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).map(\.symbol) == ["AAPL"])
  }

  @Test
  func deletesWhenTheRemoteTombstoneIsNewer() {
    let local = makeItem("AAPL", updatedAt: stamp(1))
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(2)), deleted: true)], to: [local], state: .initial)
    #expect(result.items.isEmpty)
    #expect(result.state.tombstones["AAPL"] == stamp(2))
    #expect(result.state.acknowledged["AAPL"] == stamp(2))
    #expect(result.applied == 1)
  }

  @Test
  func ignoresARemoteTombstoneForAnUnknownSymbol() {
    let result = SyncMerger.apply([remote(makeItem("TSLA", updatedAt: stamp(2)), deleted: true)], to: [], state: .initial)
    #expect(result.items.isEmpty)
    #expect(result.state == .initial)
  }

  @Test
  func keepsALocalItemNewerThanARemoteTombstone() {
    let local = makeItem("AAPL", updatedAt: stamp(5))
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(2)), deleted: true)], to: [local], state: .initial)
    #expect(result.items == [local])
  }

  @Test
  func resurrectsWhenTheRemoteItemIsNewerThanTheLocalTombstone() {
    let state = SyncState(tombstones: ["AAPL": stamp(2)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "back", updatedAt: stamp(3)))], to: [], state: state)
    #expect(result.items[id: "AAPL"]?.memo == "back")
    #expect(result.state.tombstones["AAPL"] == nil)
  }

  @Test
  func adoptsTheServerStampWhenAnIdenticalEchoComesBackClamped() {
    let local = makeItem("AAPL", memo: "same", updatedAt: stamp(9_000_000))
    let echo = makeItem("AAPL", memo: "same", updatedAt: stamp(300_000))
    let result = SyncMerger.apply([remote(echo)], to: [local], state: SyncState(acknowledged: ["AAPL": stamp(9_000_000)]))
    #expect(result.items[id: "AAPL"]?.updatedAt == stamp(300_000))
    #expect(result.state.acknowledged["AAPL"] == stamp(300_000))
    #expect(result.applied == 0)
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).isEmpty)
  }

  @Test
  func adoptsTheServerStampForAClampedTombstoneEcho() {
    let state = SyncState(acknowledged: ["AAPL": stamp(9_000_000)], tombstones: ["AAPL": stamp(9_000_000)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(300_000)), deleted: true)], to: [], state: state)
    #expect(result.state.tombstones["AAPL"] == stamp(300_000))
    #expect(result.state.acknowledged["AAPL"] == stamp(300_000))
  }

  @Test
  func staysDeletedWhenTheLocalTombstoneIsNewer() {
    let state = SyncState(tombstones: ["AAPL": stamp(5)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(3)))], to: [], state: state)
    #expect(result.items.isEmpty)
    #expect(result.state.tombstones["AAPL"] == stamp(5))
  }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run, with `-only-testing:SyncClientTests/SyncMergerTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **` with `cannot find 'SyncMerger' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncMerger.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import IdentifiedCollections
import Persistence

// MARK: - MergeResult

public struct MergeResult: Equatable, Sendable {
  public var items: IdentifiedArrayOf<WatchlistItem>
  public var state: SyncState
  /// Remote rows that were strictly newer than the local copy (or brand new) and changed local data.
  public var applied: Int
}

// MARK: - SyncMerger

/// Overview §8.5, client steps 2–3. Remote rows are written directly, never through the Persistence mutation
/// helpers, because those stamp `updatedAt = now` and would turn every remote row into a new local edit.
public enum SyncMerger {
  /// Step 2: every change sent in a request that returned 200 is acknowledged at the stamp that was sent.
  public static func acknowledge(_ sent: [SyncChange], in state: SyncState) -> SyncState {
    var state = state
    for change in sent {
      state.acknowledged[change.symbol] = change.stamp
    }
    return state
  }

  /// Step 3. A remote row is applied when there's no local copy, or when its stamp is ≥ the newest local stamp
  /// (the item's `updatedAt` or the tombstone). On a tie the server wins (plan 05 deviation 2). An older row only
  /// matters when it is a clamped echo of our own content (see `adoptClampedEcho`).
  public static func apply(
    _ remote: [RemoteWatchlistItem],
    to items: IdentifiedArrayOf<WatchlistItem>,
    state: SyncState
  ) -> MergeResult {
    var items = items
    var state = state
    var applied = 0

    for row in remote {
      let local = items[id: row.symbol]
      let tombstone = state.tombstones[row.symbol]
      let localStamp = [local?.updatedAt, tombstone].compactMap { $0 }.map(SyncStamp.milliseconds).max()
      let remoteStamp = SyncStamp.milliseconds(row.stamp)

      if let localStamp, remoteStamp < localStamp {
        adoptClampedEcho(row, local: local, tombstone: tombstone, items: &items, state: &state)
        continue
      }
      let isNewer = localStamp.map { remoteStamp > $0 } ?? true

      if row.isDeleted {
        guard local != nil || tombstone != nil else { continue }
        if local != nil, isNewer { applied += 1 }
        items.remove(id: row.symbol)
        state.tombstones[row.symbol] = row.stamp
      } else {
        var incoming = row.item
        if let local {
          incoming.createdAt = local.createdAt
        }
        if isNewer, incoming != local { applied += 1 }
        items[id: row.symbol] = incoming
        state.tombstones[row.symbol] = nil
      }
      state.acknowledged[row.symbol] = row.stamp
    }

    return MergeResult(items: items, state: state, applied: applied)
  }

  // MARK: Private

  /// The server clamps client stamps to now + 5 min (overview §8.5), and the client clamps outgoing stamps the same way
  /// (`SyncMapping.changeDTO`). When a row echoes our own content with an earlier stamp, the local copy takes the server's
  /// stamp, so later last-write-wins comparisons agree with the server. Any other older row is ignored.
  private static func adoptClampedEcho(
    _ row: RemoteWatchlistItem,
    local: WatchlistItem?,
    tombstone: Date?,
    items: inout IdentifiedArrayOf<WatchlistItem>,
    state: inout SyncState
  ) {
    if row.isDeleted {
      guard local == nil, tombstone != nil else { return }
      state.tombstones[row.symbol] = row.stamp
    } else {
      guard let local, hasSameContent(local, row.item) else { return }
      var adopted = local
      adopted.updatedAt = row.stamp
      items[id: row.symbol] = adopted
    }
    state.acknowledged[row.symbol] = row.stamp
  }

  private static func hasSameContent(_ local: WatchlistItem, _ remote: WatchlistItem) -> Bool {
    var comparable = remote
    comparable.createdAt = local.createdAt
    comparable.updatedAt = local.updatedAt
    return comparable == local
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run, with `-only-testing:SyncClientTests/SyncMergerTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 13 tests passing.

- [ ] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Sources/SyncClient/SyncMerger.swift Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMergerTests.swift
git commit -m "$(cat <<'MSG'
feat(sync): pure merger with last-write-wins, tombstones and resurrection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 12: Sync DTOs, `APIClient.syncWatchlist`, and the Domain ↔ wire mapping

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/APIClient/DTOs/WatchlistSyncDTOs.swift`
- Modify: `Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift` (one new endpoint in the struct, plus its live implementation)
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncMapping.swift`
- Test: `Wait/Packages/WaitKit/Tests/APIClientTests/WatchlistSyncDTOTests.swift`
- Test: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMappingTests.swift`

- [ ] **Step 1: Write the failing DTO test**

Create `Wait/Packages/WaitKit/Tests/APIClientTests/WatchlistSyncDTOTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Foundation
import Testing

struct WatchlistSyncDTOTests {
  @Test
  func encodesNilCursorAndUnsetRungsAsExplicitNulls() throws {
    let request = SyncRequestDTO(
      cursor: nil,
      changes: [
        WatchlistChangeDTO(
          symbol: "AAPL", name: "Apple Inc.", ladder: LadderDTO(buyHigh: "175"), memo: "", isFavorite: true, sortIndex: 0,
          checklist: [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)],
          ladderHistory: [LadderRevisionDTO(date: "2026-11-01T00:00:00.000Z", ladder: LadderDTO(buyHigh: "180"))],
          clientUpdatedAt: "2026-11-20T15:00:00.000Z", deleted: false
        ),
      ]
    )
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
    let json = try #require(object as? [String: Any])
    #expect(json["cursor"] is NSNull)
    let change = try #require((json["changes"] as? [[String: Any]])?.first)
    let ladder = try #require(change["ladder"] as? [String: Any])
    #expect(Set(ladder.keys) == ["buyLow", "buyHigh", "fair", "trim", "sell"])
    #expect(ladder["buyHigh"] as? String == "175")
    #expect(ladder["buyLow"] is NSNull)
    #expect(change["clientUpdatedAt"] as? String == "2026-11-20T15:00:00.000Z")
    #expect(change["version"] == nil)
  }

  @Test
  func decodesAServerResponse() throws {
    let body = """
      {"changes":[{"symbol":"AAPL","name":"Apple Inc.","ladder":{"buyLow":null,"buyHigh":"175","fair":null,"trim":null,"sell":null},
      "memo":"Wait","isFavorite":true,"sortIndex":2,"checklist":[],"ladderHistory":[{"date":"2026-11-01T00:00:00.000Z","ladder":{"buyHigh":"180"}}],
      "clientUpdatedAt":"2026-11-20T15:00:00.000Z","deleted":false,"version":7}],"cursor":"7:AAPL","hasMore":false}
      """
    let response = try JSONDecoder().decode(SyncResponseDTO.self, from: Data(body.utf8))
    #expect(response.cursor == "7:AAPL")
    #expect(response.hasMore == false)
    #expect(response.changes.first?.version == 7)
    #expect(response.changes.first?.ladder == LadderDTO(buyHigh: "175"))
    #expect(response.changes.first?.ladderHistory.first?.ladder.buyHigh == "180")
  }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run, with `-only-testing:APIClientTests/WatchlistSyncDTOTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **` with `cannot find 'SyncRequestDTO' in scope`.

- [ ] **Step 3: Write the DTOs**

Create `Wait/Packages/WaitKit/Sources/APIClient/DTOs/WatchlistSyncDTOs.swift`. The shapes come from overview §8.4: prices are decimal strings, and timestamps are pre-formatted ISO strings.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderDTO

/// Unset rungs are always sent as explicit `null` and are accepted as null or missing.
public struct LadderDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(buyLow: String? = nil, buyHigh: String? = nil, fair: String? = nil, trim: String? = nil, sell: String? = nil) {
    self.buyLow = buyLow
    self.buyHigh = buyHigh
    self.fair = fair
    self.trim = trim
    self.sell = sell
  }

  // MARK: Public

  public var buyLow: String?
  public var buyHigh: String?
  public var fair: String?
  public var trim: String?
  public var sell: String?

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(buyLow, forKey: .buyLow)
    try container.encode(buyHigh, forKey: .buyHigh)
    try container.encode(fair, forKey: .fair)
    try container.encode(trim, forKey: .trim)
    try container.encode(sell, forKey: .sell)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case buyLow
    case buyHigh
    case fair
    case trim
    case sell
  }
}

// MARK: - ChecklistItemDTO

public struct ChecklistItemDTO: Codable, Equatable, Sendable {
  public init(id: String, name: String, isChecked: Bool) {
    self.id = id
    self.name = name
    self.isChecked = isChecked
  }

  public var id: String
  public var name: String
  public var isChecked: Bool
}

// MARK: - LadderRevisionDTO

public struct LadderRevisionDTO: Codable, Equatable, Sendable {
  public init(date: String, ladder: LadderDTO) {
    self.date = date
    self.ladder = ladder
  }

  public var date: String
  public var ladder: LadderDTO
}

// MARK: - WatchlistChangeDTO

/// `ItemChange` in overview §8.4.
public struct WatchlistChangeDTO: Codable, Equatable, Sendable {
  public init(
    symbol: String,
    name: String,
    ladder: LadderDTO,
    memo: String,
    isFavorite: Bool,
    sortIndex: Int,
    checklist: [ChecklistItemDTO],
    ladderHistory: [LadderRevisionDTO],
    clientUpdatedAt: String,
    deleted: Bool
  ) {
    self.symbol = symbol
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.clientUpdatedAt = clientUpdatedAt
    self.deleted = deleted
  }

  public var symbol: String
  public var name: String
  public var ladder: LadderDTO
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItemDTO]
  public var ladderHistory: [LadderRevisionDTO]
  public var clientUpdatedAt: String
  public var deleted: Bool
}

// MARK: - WatchlistItemDTO

/// `ItemDTO` in overview §8.4: an `ItemChange` plus the server `version`.
public struct WatchlistItemDTO: Codable, Equatable, Sendable {
  public init(
    symbol: String,
    name: String,
    ladder: LadderDTO,
    memo: String,
    isFavorite: Bool,
    sortIndex: Int,
    checklist: [ChecklistItemDTO],
    ladderHistory: [LadderRevisionDTO],
    clientUpdatedAt: String,
    deleted: Bool,
    version: Int
  ) {
    self.symbol = symbol
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.clientUpdatedAt = clientUpdatedAt
    self.deleted = deleted
    self.version = version
  }

  public var symbol: String
  public var name: String
  public var ladder: LadderDTO
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItemDTO]
  public var ladderHistory: [LadderRevisionDTO]
  public var clientUpdatedAt: String
  public var deleted: Bool
  public var version: Int
}

// MARK: - SyncRequestDTO

public struct SyncRequestDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(cursor: String?, changes: [WatchlistChangeDTO]) {
    self.cursor = cursor
    self.changes = changes
  }

  // MARK: Public

  public var cursor: String?
  public var changes: [WatchlistChangeDTO]

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cursor, forKey: .cursor)
    try container.encode(changes, forKey: .changes)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case cursor
    case changes
  }
}

// MARK: - SyncResponseDTO

public struct SyncResponseDTO: Codable, Equatable, Sendable {
  public init(changes: [WatchlistItemDTO], cursor: String, hasMore: Bool) {
    self.changes = changes
    self.cursor = cursor
    self.hasMore = hasMore
  }

  public var changes: [WatchlistItemDTO]
  public var cursor: String
  public var hasMore: Bool
}
```
Every DTO has a public memberwise initializer, because `SyncClient` (another module) and its tests build them.

- [ ] **Step 4: Add the endpoint to `APIClient`**

`Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift` (plan 04) declares the endpoints in this order: `quotes`, `history`, `search`, `profile`, `deleteAccount`. Both `live(session:)` and `misconfigured` call the full memberwise init, and memberwise arguments follow declaration order. Append `syncWatchlist` **after `deleteAccount` in all three places**:

1. In `@DependencyClient public struct APIClient`, after the `deleteAccount` property:
   ```swift
     /// `POST /api/watchlist/sync` (overview §8.4–§8.5).
     public var syncWatchlist: @Sendable (_ request: SyncRequestDTO) async throws -> SyncResponseDTO
   ```
2. In `public static func live(session: HTTPSession) -> APIClient`, after the `deleteAccount: { … }` argument. Add a comma after its closing brace:
   ```swift
         syncWatchlist: { request in
           try await session.post("/api/watchlist/sync", body: request)
         }
   ```
3. In `static let misconfigured`, after `deleteAccount: { throw APIError.misconfigured }`. Again, add the comma:
   ```swift
       syncWatchlist: { _ in throw APIError.misconfigured }
   ```

Then confirm that each place has exactly one entry:
```bash
cd /Users/ckai/code/Wait-plan05/Wait/Packages/WaitKit
grep -c "syncWatchlist" Sources/APIClient/APIClient.swift
```
Expected: `3`.

- [ ] **Step 5: Run the DTO test and confirm it passes**

Run, with `-only-testing:APIClientTests/WatchlistSyncDTOTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 2 tests passing.

- [ ] **Step 6: Write the failing mapping test**

Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMappingTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation
@testable import SyncClient
import Testing

struct SyncMappingTests {
  @Test
  func mapsAnUpsertToTheWireShape() throws {
    var item = makeItem("AAPL", memo: "Wait", isFavorite: true, sortIndex: 3, updatedAt: stamp(123))
    item.ladder = try PriceLadder(buyLow: Decimal(string: "0.0075")!, buyHigh: Decimal(string: "14.2")!)
    item.checklist = [ChecklistItem(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, name: "Moat?", isChecked: true)]
    item.ladderHistory = [LadderRevision(date: stamp(0), ladder: try PriceLadder(buyHigh: 16))]

    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)

    #expect(dto.symbol == "AAPL")
    #expect(dto.ladder == LadderDTO(buyLow: "0.0075", buyHigh: "14.2"))
    #expect(dto.clientUpdatedAt == "2026-11-20T15:00:00.123Z")
    #expect(dto.checklist == [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)])
    #expect(dto.ladderHistory == [LadderRevisionDTO(date: "2026-11-20T15:00:00.000Z", ladder: LadderDTO(buyHigh: "16"))])
    #expect(!dto.deleted)
  }

  @Test
  func mapsATombstoneWithPlaceholderFields() {
    let dto = SyncMapping.changeDTO(.deletion(symbol: "MSFT", at: stamp(5)), now: .distantFuture)
    #expect(dto == WatchlistChangeDTO(
      symbol: "MSFT", name: "MSFT", ladder: LadderDTO(), memo: "", isFavorite: false, sortIndex: 0,
      checklist: [], ladderHistory: [], clientUpdatedAt: "2026-11-20T15:00:00.005Z", deleted: true
    ))
  }

  @Test
  func clampsOversizedFieldsToTheServerLimitsInUTF16Units() {
    var item = makeItem("AAPL")
    item.memo = String(repeating: "😀", count: 6000) // 12,000 UTF-16 units
    item.name = String(repeating: "n", count: 800)
    item.checklist = (0 ..< 150).map { ChecklistItem(id: UUID(), name: "q", isChecked: false) }
    item.ladderHistory = (0 ..< 250).map { LadderRevision(date: stamp(Int64($0)), ladder: .empty) }

    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)

    #expect(dto.memo.utf16.count == 10000)
    #expect(dto.memo.allSatisfy { $0 == "😀" })
    #expect(dto.name.count == 500)
    #expect(dto.checklist.count == 100)
    #expect(dto.ladderHistory.count == 200)
    #expect(dto.ladderHistory.first?.date == SyncStamp.string(from: stamp(50)))
  }

  @Test
  func roundsAnchorsToSixDecimals() throws {
    var item = makeItem("AAPL")
    item.ladder = try PriceLadder(buyHigh: Decimal(string: "1.23456789")!)
    #expect(SyncMapping.changeDTO(.upsert(item), now: .distantFuture).ladder.buyHigh == "1.234568")
  }

  @Test
  func clampsAFutureStampToNowPlusFiveMinutes() {
    let now = stamp(0)
    let future = makeItem("AAPL", updatedAt: stamp(3_600_000))
    #expect(SyncMapping.changeDTO(.upsert(future), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(300_000)))
    #expect(SyncMapping.changeDTO(.deletion(symbol: "MSFT", at: stamp(3_600_000)), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(300_000)))
    #expect(SyncMapping.changeDTO(.upsert(makeItem("AAPL", updatedAt: stamp(1))), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(1)))
  }

  @Test
  func mapsAServerRowBackToDomain() throws {
    let dto = WatchlistItemDTO(
      symbol: "AAPL", name: "Apple Inc.", ladder: LadderDTO(buyLow: "12", buyHigh: "16", fair: "23"), memo: "Wait",
      isFavorite: true, sortIndex: 2,
      checklist: [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)],
      ladderHistory: [
        LadderRevisionDTO(date: "2026-11-01T00:00:00.000Z", ladder: LadderDTO(buyHigh: "18")),
        LadderRevisionDTO(date: "not a date", ladder: LadderDTO(buyHigh: "18")),
      ],
      clientUpdatedAt: "2026-11-20T15:00:00.123Z", deleted: false, version: 7
    )

    let row = try SyncMapping.remote(dto)

    #expect(row.version == 7)
    #expect(!row.isDeleted)
    #expect(SyncStamp.milliseconds(row.stamp) == 1_795_186_800_123)
    #expect(row.item.ladder == (try PriceLadder(buyLow: 12, buyHigh: 16, fair: 23)))
    #expect(row.item.checklist.first?.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    #expect(row.item.ladderHistory.count == 1)
    #expect(row.item.createdAt == SyncStamp.date(from: "2026-11-01T00:00:00.000Z"))
  }

  @Test
  func rejectsAnUnreadableServerRow() {
    var dto = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("AAPL")), now: .distantFuture), version: 1)
    dto.ladder = LadderDTO(buyLow: "20", buyHigh: "10")
    #expect(throws: SyncMappingError.invalidLadder("AAPL")) { try SyncMapping.remote(dto) }
    dto.ladder = LadderDTO()
    dto.clientUpdatedAt = "yesterday"
    #expect(throws: SyncMappingError.invalidTimestamp("yesterday")) { try SyncMapping.remote(dto) }
  }
}
```

- [ ] **Step 7: Run it and confirm it fails**

Run, with `-only-testing:SyncClientTests/SyncMappingTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **` with `cannot find 'SyncMapping' in scope`.

- [ ] **Step 8: Write the mapping**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncMapping.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation

// MARK: - SyncMappingError

public enum SyncMappingError: Error, Equatable, Sendable {
  case invalidTimestamp(String)
  case invalidDecimal(String)
  case invalidLadder(String)
  case invalidChecklistID(String)
}

// MARK: - SyncMapping

/// Domain ↔ wire mapping for `POST /api/watchlist/sync`. Outgoing values are clamped to the server limits
/// (overview §8.4), because one oversized item fails the whole batch with a 400 and would block sync for good.
enum SyncMapping {
  // MARK: Internal

  static let maxMemoUTF16 = 10_000
  static let maxNameUTF16 = 500
  static let maxChecklistItems = 100
  static let maxLadderHistory = 200
  static let anchorFractionDigits = 6

  /// Matches the server's clamp (overview §8.5, server step 2).
  static let maxClockSkew: TimeInterval = 5 * 60

  /// `now` is the device clock. A stamp more than 5 minutes ahead of it (left over from a clock that has since been
  /// corrected) goes out clamped, and `SyncMerger` then adopts the clamped stamp the server echoes back.
  static func changeDTO(_ change: SyncChange, now: Date) -> WatchlistChangeDTO {
    let wireStamp = SyncStamp.string(from: min(change.stamp, now.addingTimeInterval(maxClockSkew)))
    guard let item = change.item else {
      return WatchlistChangeDTO(
        symbol: change.symbol, name: change.symbol, ladder: LadderDTO(), memo: "", isFavorite: false, sortIndex: 0,
        checklist: [], ladderHistory: [], clientUpdatedAt: wireStamp, deleted: true
      )
    }
    return WatchlistChangeDTO(
      symbol: item.symbol,
      name: clamp(item.name, toUTF16: maxNameUTF16),
      ladder: ladderDTO(item.ladder),
      memo: clamp(item.memo, toUTF16: maxMemoUTF16),
      isFavorite: item.isFavorite,
      sortIndex: item.sortIndex,
      checklist: item.checklist.prefix(maxChecklistItems).map {
        ChecklistItemDTO(id: $0.id.uuidString, name: clamp($0.name, toUTF16: maxNameUTF16), isChecked: $0.isChecked)
      },
      ladderHistory: item.ladderHistory.suffix(maxLadderHistory).map {
        LadderRevisionDTO(date: SyncStamp.string(from: $0.date), ladder: ladderDTO($0.ladder))
      },
      clientUpdatedAt: wireStamp,
      deleted: false
    )
  }

  static func remote(_ dto: WatchlistItemDTO) throws(SyncMappingError) -> RemoteWatchlistItem {
    guard let updatedAt = SyncStamp.date(from: dto.clientUpdatedAt) else {
      throw .invalidTimestamp(dto.clientUpdatedAt)
    }
    let ladder = try parseLadder(dto.ladder, symbol: dto.symbol)
    var checklist: [ChecklistItem] = []
    for entry in dto.checklist {
      guard let id = UUID(uuidString: entry.id) else { throw .invalidChecklistID(entry.id) }
      checklist.append(ChecklistItem(id: id, name: entry.name, isChecked: entry.isChecked))
    }
    // History is informational, so an unreadable entry is dropped instead of rejecting the whole row.
    let history: [LadderRevision] = dto.ladderHistory.compactMap { entry in
      guard
        let date = SyncStamp.date(from: entry.date),
        let revisionLadder = try? parseLadder(entry.ladder, symbol: dto.symbol)
      else {
        return nil
      }
      return LadderRevision(date: date, ladder: revisionLadder)
    }
    let item = WatchlistItem(
      symbol: dto.symbol,
      name: dto.name,
      ladder: ladder,
      memo: dto.memo,
      isFavorite: dto.isFavorite,
      sortIndex: dto.sortIndex,
      checklist: checklist,
      ladderHistory: history,
      createdAt: history.first?.date ?? updatedAt,
      updatedAt: updatedAt
    )
    return RemoteWatchlistItem(item: item, isDeleted: dto.deleted, version: dto.version)
  }

  /// Test helper: turns a change into the row the server would echo back.
  static func itemDTO(from change: WatchlistChangeDTO, version: Int) -> WatchlistItemDTO {
    WatchlistItemDTO(
      symbol: change.symbol, name: change.name, ladder: change.ladder, memo: change.memo, isFavorite: change.isFavorite,
      sortIndex: change.sortIndex, checklist: change.checklist, ladderHistory: change.ladderHistory,
      clientUpdatedAt: change.clientUpdatedAt, deleted: change.deleted, version: version
    )
  }

  // MARK: Private

  private static let posix = Locale(identifier: "en_US_POSIX")

  private static func ladderDTO(_ ladder: PriceLadder) -> LadderDTO {
    LadderDTO(
      buyLow: decimalString(ladder.buyLow),
      buyHigh: decimalString(ladder.buyHigh),
      fair: decimalString(ladder.fair),
      trim: decimalString(ladder.trim),
      sell: decimalString(ladder.sell)
    )
  }

  private static func parseLadder(_ dto: LadderDTO, symbol: String) throws(SyncMappingError) -> PriceLadder {
    do {
      return try PriceLadder(
        buyLow: decimal(dto.buyLow),
        buyHigh: decimal(dto.buyHigh),
        fair: decimal(dto.fair),
        trim: decimal(dto.trim),
        sell: decimal(dto.sell)
      )
    } catch let error as SyncMappingError {
      throw error
    } catch {
      throw .invalidLadder(symbol)
    }
  }

  private static func decimal(_ text: String?) throws(SyncMappingError) -> Decimal? {
    guard let text else { return nil }
    guard let value = Decimal(string: text, locale: posix) else { throw .invalidDecimal(text) }
    return value
  }

  /// Rounded to 6 fraction digits (NUMERIC(18,6)). `Decimal.description` doesn't depend on the locale.
  private static func decimalString(_ value: Decimal?) -> String? {
    guard var value else { return nil }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, anchorFractionDigits, .plain)
    return rounded.description
  }

  /// Truncates by whole grapheme clusters so the UTF-16 length (what the server's `.length` counts) stays ≤ `limit`.
  private static func clamp(_ text: String, toUTF16 limit: Int) -> String {
    guard text.utf16.count > limit else { return text }
    var count = 0
    var end = text.startIndex
    for index in text.indices {
      let width = text[index].utf16.count
      if count + width > limit { break }
      count += width
      end = text.index(after: index)
    }
    return String(text[..<end])
  }
}
```

- [ ] **Step 9: Run the mapping test and confirm it passes**

Run, with `-only-testing:SyncClientTests/SyncMappingTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 7 tests passing.

- [ ] **Step 10: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Sources/APIClient/DTOs/WatchlistSyncDTOs.swift Wait/Packages/WaitKit/Sources/APIClient/APIClient.swift \
  Wait/Packages/WaitKit/Sources/SyncClient/SyncMapping.swift \
  Wait/Packages/WaitKit/Tests/APIClientTests/WatchlistSyncDTOTests.swift Wait/Packages/WaitKit/Tests/SyncClientTests/SyncMappingTests.swift
git commit -m "$(cat <<'MSG'
feat(sync): watchlist sync DTOs, APIClient endpoint and clamped wire mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

## Chunk 6: iOS engine and app triggers

### Task 13: `SyncEngine` actor and the `SyncClient` dependency

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncEngine.swift`
- Create: `Wait/Packages/WaitKit/Sources/SyncClient/SyncClient.swift`
- Test: `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncEngineTests.swift`

Logging uses plan 02's `Log.sync`, a `LogChannel` with `error(_ message: String)`. Messages are plain strings, with no `privacy:` arguments, because `LogChannel` logs everything as public.

- [ ] **Step 1: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/SyncClientTests/SyncEngineTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
@testable import SyncClient
import Testing

// MARK: - Gate

/// Holds the first fake request open until the test calls `open()`.
actor Gate {
  // MARK: Internal

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { continuation = $0 }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }

  // MARK: Private

  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false
}

// MARK: - SyncEngineTests

struct SyncEngineTests {
  // MARK: Internal

  @Test
  func firstSyncUploadsEveryItemAndAcknowledgesIt() async throws {
    let requests = LockIsolated<[SyncRequestDTO]>([])
    let (engine, items, state) = makeEngine(items: [makeItem("MSFT", updatedAt: stamp(2)), makeItem("AAPL", updatedAt: stamp(1))]) { request in
      requests.withValue { $0.append(request) }
      return Self.echo(request, version: 1)
    }

    let report = try await engine.sync()

    #expect(requests.value.map(\.cursor) == [nil])
    #expect(requests.value[0].changes.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(report == SyncReport(pushed: 2, pulled: 2, applied: 0, rounds: 1))
    #expect(state.wrappedValue.cursor == "1:MSFT")
    #expect(SyncStamp.same(state.wrappedValue.lastSyncedAt, Self.now))
    #expect(SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue).isEmpty)
  }

  @Test
  func pullsRemoteItemsIntoAnEmptyWatchlist() async throws {
    let row = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("NVDA", memo: "from B", updatedAt: stamp(9))), now: .distantFuture), version: 4)
    let (engine, items, state) = makeEngine { _ in SyncResponseDTO(changes: [row], cursor: "4:NVDA", hasMore: false) }

    let report = try await engine.sync()

    #expect(items.wrappedValue[id: "NVDA"]?.memo == "from B")
    #expect(state.wrappedValue.cursor == "4:NVDA")
    #expect(report == SyncReport(pushed: 0, pulled: 1, applied: 1, rounds: 1))
  }

  @Test
  func keepsPullingWhileTheServerHasMore() async throws {
    let requests = LockIsolated<[SyncRequestDTO]>([])
    let (engine, _, state) = makeEngine { request in
      let count = requests.withValue { $0.append(request); return $0.count }
      return SyncResponseDTO(changes: [], cursor: count == 1 ? "1:A" : "2:B", hasMore: count == 1)
    }

    let report = try await engine.sync()

    #expect(requests.value.map(\.cursor) == [nil, "1:A"])
    #expect(report.rounds == 2)
    #expect(state.wrappedValue.cursor == "2:B")
  }

  @Test
  func stopsAfterMaxRounds() async throws {
    let calls = LockIsolated(0)
    let (engine, _, _) = makeEngine(maxRounds: 3) { _ in
      calls.withValue { $0 += 1 }
      return SyncResponseDTO(changes: [], cursor: "1:A", hasMore: true)
    }

    let report = try await engine.sync()

    #expect(calls.value == 3)
    #expect(report.rounds == 3)
  }

  @Test
  func anEditMadeDuringARequestIsPushedInTheNextRound() async throws {
    let items = Shared(value: IdentifiedArrayOf<WatchlistItem>([makeItem("AAPL", memo: "v1", updatedAt: stamp(1))]))
    let state = Shared(value: SyncState.initial)
    let requests = LockIsolated<[SyncRequestDTO]>([])
    var api = APIClient()
    api.syncWatchlist = { request in
      let count = requests.withValue { $0.append(request); return $0.count }
      if count == 1 {
        items.withLock {
          $0[id: "AAPL"]!.memo = "v2"
          $0[id: "AAPL"]!.updatedAt = stamp(2)
        }
      }
      return Self.echo(request, version: count)
    }
    let engine = SyncEngine(api: api, now: { Self.now }, items: items, state: state)

    let report = try await engine.sync()

    #expect(requests.value.count == 2)
    #expect(requests.value[1].changes.map(\.memo) == ["v2"])
    #expect(requests.value[1].changes.map(\.clientUpdatedAt) == [SyncStamp.string(from: stamp(2))])
    #expect(items.wrappedValue[id: "AAPL"]?.memo == "v2")
    #expect(report.rounds == 2)
  }

  @Test
  func concurrentCallsShareOneRunThatRerunsOnce() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, _) = makeEngine { _ in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { await gate.wait() }
      return SyncResponseDTO(changes: [], cursor: "0:", hasMore: false)
    }

    async let first = engine.sync()
    while calls.value < 1 { await Task.yield() }
    async let second = engine.sync()
    async let third = engine.sync()
    while await engine.joinedCallerCount < 2 { await Task.yield() }
    await gate.open()
    let reports = try await [first, second, third]

    #expect(calls.value == 2)
    #expect(reports == Array(repeating: SyncReport(rounds: 2), count: 3))
  }

  @Test
  func skipsUnreadableRowsButStillAdvancesTheCursor() async throws {
    var broken = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("BAD", updatedAt: stamp(3))), now: .distantFuture), version: 3)
    broken.ladder = LadderDTO(buyLow: "20", buyHigh: "10")
    let good = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("NVDA", updatedAt: stamp(3))), now: .distantFuture), version: 3)
    let (engine, items, state) = makeEngine { _ in SyncResponseDTO(changes: [broken, good], cursor: "3:NVDA", hasMore: false) }

    let report = try await engine.sync()

    #expect(items.wrappedValue.ids.elements == ["NVDA"])
    #expect(state.wrappedValue.cursor == "3:NVDA")
    #expect(report.pulled == 2)
    #expect(report.applied == 1)
  }

  @Test
  func aFailedSyncLeavesStateUntouchedAndTheNextOneRuns() async throws {
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { throw URLError(.notConnectedToInternet) }
      return Self.echo(request, version: 1)
    }

    await #expect(throws: URLError.self) { try await engine.sync() }
    #expect(state.wrappedValue == .initial)

    _ = try await engine.sync()
    #expect(SyncStamp.same(state.wrappedValue.acknowledged["AAPL"], stamp(1)))
  }

  @Test
  func aResetDuringARunDiscardsThatRunsMerge() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      calls.withValue { $0 += 1 }
      await gate.wait()
      return Self.echo(request, version: 1)
    }

    async let run = engine.sync()
    while calls.value < 1 { await Task.yield() }
    await engine.reset()
    await gate.open()
    _ = try await run

    #expect(state.wrappedValue == .initial)
  }

  @Test
  func aSyncRequestedAfterAMidRunResetStillRuns() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { await gate.wait() }
      return Self.echo(request, version: count)
    }

    async let first = engine.sync()
    while calls.value < 1 { await Task.yield() }
    await engine.reset()
    async let second = engine.sync()
    while await engine.joinedCallerCount < 1 { await Task.yield() }
    await gate.open()
    _ = try await [first, second]

    #expect(calls.value == 2)
    #expect(state.wrappedValue.cursor == "2:AAPL")
    #expect(SyncStamp.same(state.wrappedValue.acknowledged["AAPL"], stamp(1)))
    #expect(SyncStamp.same(state.wrappedValue.lastSyncedAt, Self.now))
  }

  @Test
  func resetForgetsCursorAndAcknowledgements() async {
    let (engine, _, state) = makeEngine(state: SyncState(cursor: "5:AAPL", acknowledged: ["AAPL": stamp(1)], lastSyncedAt: stamp(2))) { _ in
      SyncResponseDTO(changes: [], cursor: "0:", hasMore: false)
    }

    await engine.reset()

    #expect(state.wrappedValue == .initial)
  }

  // MARK: Private

  private static let now = stamp(60_000)

  /// The server echoing every pushed change back at `version`.
  private static func echo(_ request: SyncRequestDTO, version: Int) -> SyncResponseDTO {
    let rows = request.changes.map { SyncMapping.itemDTO(from: $0, version: version) }
    let cursor = rows.last.map { "\(version):\($0.symbol)" } ?? request.cursor ?? "0:"
    return SyncResponseDTO(changes: rows, cursor: cursor, hasMore: false)
  }

  private func makeEngine(
    items: IdentifiedArrayOf<WatchlistItem> = [],
    state: SyncState = .initial,
    maxRounds: Int = 10,
    handler: @escaping @Sendable (SyncRequestDTO) async throws -> SyncResponseDTO
  ) -> (SyncEngine, Shared<IdentifiedArrayOf<WatchlistItem>>, Shared<SyncState>) {
    let itemsReference = Shared(value: items)
    let stateReference = Shared(value: state)
    // Same style as plan 04's tests: start from the unimplemented client and override only what the test uses.
    var api = APIClient()
    api.syncWatchlist = handler
    let engine = SyncEngine(
      api: api,
      now: { Self.now },
      items: itemsReference,
      state: stateReference,
      maxRounds: maxRounds
    )
    return (engine, itemsReference, stateReference)
  }
}
```
`Shared(value:)` makes an unpersisted reference, so these tests don't touch file storage. `LockIsolated` comes from ConcurrencyExtras, which `Dependencies` re-exports.

- [ ] **Step 2: Run the test and confirm it fails**

Run, with `-only-testing:SyncClientTests/SyncEngineTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **` with `cannot find 'SyncEngine' in scope`.

- [ ] **Step 3: Write the engine**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncEngine.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation
import IdentifiedCollections
import Logging
import Persistence
import Sharing

// MARK: - SyncEngine

/// The client half of overview §8.5. Single-flight: a `sync()` call made during a run joins that run and asks it to
/// run once more afterwards, so edits made during the run are pushed too. Each run makes at most `maxRounds` requests.
public actor SyncEngine {
  // MARK: Lifecycle

  public init(
    api: APIClient,
    now: @escaping @Sendable () -> Date,
    items: Shared<IdentifiedArrayOf<WatchlistItem>>,
    state: Shared<SyncState>,
    batchSize: Int = 50,
    maxRounds: Int = 10
  ) {
    self.api = api
    self.now = now
    self.items = items
    self.state = state
    self.batchSize = batchSize
    self.maxRounds = maxRounds
  }

  // MARK: Public

  public func sync() async throws -> SyncReport {
    if let inFlight {
      rerunRequested = true
      joinedCallerCount += 1
      return try await inFlight.value
    }
    let task = Task { try await self.runUntilSettled() }
    inFlight = task
    return try await task.value
  }

  /// Forgets the cursor, acknowledgements and tombstones (used after account deletion). Local items are untouched.
  /// It also bumps `generation`, so a run that is mid-request when the reset happens discards its result instead of
  /// writing the old account's cursor back.
  public func reset() {
    generation += 1
    state.withLock { $0 = .initial }
  }

  // MARK: Internal

  /// The number of callers that joined an in-flight run. Tests use it to order concurrent calls.
  private(set) var joinedCallerCount = 0

  // MARK: Private

  private let api: APIClient
  private let now: @Sendable () -> Date
  private let items: Shared<IdentifiedArrayOf<WatchlistItem>>
  private let state: Shared<SyncState>
  private let batchSize: Int
  private let maxRounds: Int
  private var inFlight: Task<SyncReport, any Error>?
  private var rerunRequested = false
  private var generation = 0

  private static func readableRow(_ dto: WatchlistItemDTO) -> RemoteWatchlistItem? {
    do {
      return try SyncMapping.remote(dto)
    } catch {
      Log.sync.error("Skipping unreadable watchlist row \(dto.symbol): \(error)")
      return nil
    }
  }

  private func runUntilSettled() async throws -> SyncReport {
    // Clearing inFlight inside the task, with no suspension point after the last rerun check, means a caller can't
    // join a run that has already finished.
    defer { inFlight = nil }
    var startGeneration = generation
    var lastPassDiscarded = false
    var total = SyncReport.empty
    repeat {
      rerunRequested = false
      total += try await runRounds()
      lastPassDiscarded = generation != startGeneration
      if lastPassDiscarded {
        // A reset landed mid-pass, so that pass's merge was discarded. Adopt the new generation, and keep looping
        // while `rerunRequested`, so a sync that was requested after the reset still runs.
        startGeneration = generation
      }
    } while rerunRequested
    guard !lastPassDiscarded else { return total }
    let finishedAt = now().truncatedToMilliseconds
    state.withLock { $0.lastSyncedAt = finishedAt }
    return total
  }

  private func runRounds() async throws -> SyncReport {
    let skipped = SyncPlanner.unsyncableSymbols(items: items.wrappedValue, state: state.wrappedValue)
    if !skipped.isEmpty {
      Log.sync.error("Keeping \(skipped.joined(separator: ", ")) local-only: symbol not accepted by the sync endpoint")
    }
    var report = SyncReport.empty
    while report.rounds < maxRounds {
      let pending = SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue)
      let batch = Array(pending.prefix(batchSize))
      let sentAt = now()
      let request = SyncRequestDTO(cursor: state.wrappedValue.cursor, changes: batch.map { SyncMapping.changeDTO($0, now: sentAt) })

      let requestGeneration = generation
      let response = try await api.syncWatchlist(request)
      guard generation == requestGeneration else { break }

      let remote = response.changes.compactMap(Self.readableRow)
      let applied = items.withLock { items in
        state.withLock { state in
          let merged = SyncMerger.apply(remote, to: items, state: SyncMerger.acknowledge(batch, in: state))
          items = merged.items
          state = merged.state
          state.cursor = response.cursor
          return merged.applied
        }
      }
      report += SyncReport(pushed: batch.count, pulled: response.changes.count, applied: applied, rounds: 1)

      let stillPending = !SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue).isEmpty
      if !response.hasMore, !stillPending { break }
    }
    return report
  }
}
```

- [ ] **Step 4: Write the dependency**

Create `Wait/Packages/WaitKit/Sources/SyncClient/SyncClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import DependenciesMacros
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing

// MARK: - SyncClient

@DependencyClient
public struct SyncClient: Sendable {
  /// Pushes pending changes and pulls remote ones (overview §8.5). Concurrent calls share one run.
  public var sync: @Sendable () async throws -> SyncReport
  /// Forgets sync bookkeeping after account deletion. The local watchlist is kept and re-uploads under the new identity.
  public var reset: @Sendable () async -> Void
}

// MARK: DependencyKey

extension SyncClient: DependencyKey {
  public static let liveValue: SyncClient = {
    @Dependency(\.apiClient) var apiClient
    let engine = SyncEngine(api: apiClient, now: { Date() }, items: Shared(.watchlist), state: Shared(.syncState))
    return SyncClient(
      sync: { try await engine.sync() },
      reset: { await engine.reset() }
    )
  }()

  public static let testValue = SyncClient()
}

extension DependencyValues {
  public var syncClient: SyncClient {
    get { self[SyncClient.self] }
    set { self[SyncClient.self] = newValue }
  }
}
```
`liveValue` is a `static let`, so the app has exactly one engine. That's what makes single-flight work across every caller.

- [ ] **Step 5: Run the tests and confirm they pass**

Run, with `-only-testing:SyncClientTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`. That's 5 SyncStamp, 7 planner, 13 merger, 7 mapping and 11 engine tests.

- [ ] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Sources/SyncClient/SyncEngine.swift Wait/Packages/WaitKit/Sources/SyncClient/SyncClient.swift \
  Wait/Packages/WaitKit/Tests/SyncClientTests/SyncEngineTests.swift
git commit -m "$(cat <<'MSG'
feat(sync): single-flight SyncEngine actor and SyncClient dependency

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 14: Sync triggers in `AppFeature`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (the `AppFeature` target's dependencies)
- Modify: `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`
- Modify: `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureTests.swift` (plan 02's exhaustive `becomingActiveRefreshesQuotesAndPublishesOneSnapshot` now also receives `.syncFinished`)
- Test: `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureSyncTests.swift`

These are the triggers from overview §8.5 and §12.3 (including the TCA `onChange` rule):
- **Scene becomes active** (this covers launch too): sync now.
- **Watchlist changes** (any action that changes `watchlist.items`): sync 2 s after the last change, using cancel id `CancelID.sync`.
- **`WatchlistFeature.Action.delegate(.refreshRequested)`** (pull-to-refresh): sync now.

When the sync engine writes remote rows, no action is involved, so `onChange` doesn't fire. That means remote changes can't cause a sync loop. It also means the widget/watch snapshot wouldn't see them, so AppFeature republishes the snapshot on `.syncFinished` whenever `report.pulled > 0` (§12.3).

- [ ] **Step 1: Add the dependency**

In `Wait/Packages/WaitKit/Package.swift`, add `"SyncClient"` to the `AppFeature` target's `dependencies` array. Also make sure the `AppFeatureTests` test target lists `"SyncClient"`, `.dependenciesTestSupport` and `"Connectivity"` (plan 03 normally adds the last one), and add whichever are missing.

- [ ] **Step 2: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureSyncTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import AppFeature
import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Domain
import Foundation
import Persistence
import SyncClient
import Testing

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AppFeatureSyncTests {
  // MARK: Internal

  @Test
  func becomingActiveSyncs() async {
    let syncs = LockIsolated(0)
    let store = makeStore(syncs: syncs)

    await store.send(.scenePhaseChanged(.active))
    await store.receive(\.syncFinished)

    #expect(syncs.value == 1)
  }

  @Test
  func pullToRefreshSyncsImmediately() async {
    let syncs = LockIsolated(0)
    let store = makeStore(syncs: syncs)

    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)

    #expect(syncs.value == 1)
  }

  @Test
  func watchlistEditsSyncTwoSecondsAfterTheLastEdit() async {
    @Shared(.watchlist) var items
    $items.withLock { $0 = [Self.item("AAPL")] }
    let syncs = LockIsolated(0)
    let clock = TestClock()
    let store = makeStore(syncs: syncs, clock: clock)

    await store.send(.watchlist(.favoriteSwiped(symbol: "AAPL")))
    await clock.advance(by: .seconds(1))
    await store.send(.watchlist(.favoriteSwiped(symbol: "AAPL")))
    await clock.advance(by: .seconds(1))
    #expect(syncs.value == 0)

    await clock.advance(by: .seconds(1))
    await store.receive(\.syncFinished)
    #expect(syncs.value == 1)
  }

  @Test
  func aSyncThatPulledRowsRepublishesTheSnapshot() async {
    let publishes = LockIsolated(0)
    let clock = TestClock()
    let store = makeStore(syncs: LockIsolated(0), clock: clock, publishes: publishes) { SyncReport(pulled: 2, rounds: 1) }

    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)
    await clock.advance(by: .seconds(1))

    #expect(publishes.value == 1)
  }

  @Test
  func aSyncThatPulledNothingDoesNotRepublish() async {
    let publishes = LockIsolated(0)
    let clock = TestClock()
    let store = makeStore(syncs: LockIsolated(0), clock: clock, publishes: publishes) { SyncReport(pushed: 1, rounds: 1) }

    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)
    await clock.advance(by: .seconds(1))

    #expect(publishes.value == 0)
  }

  @Test
  func aFailedSyncIsReportedNotThrown() async {
    let store = makeStore(syncs: LockIsolated(0)) { throw URLError(.timedOut) }

    await store.send(.scenePhaseChanged(.active))
    await store.receive(\.syncFailed)
  }

  // MARK: Private

  private static func item(_ symbol: String) -> WatchlistItem {
    let date = Date(timeIntervalSince1970: 1_795_186_800)
    return WatchlistItem(
      symbol: symbol, name: "\(symbol) Inc.", ladder: .empty, memo: "", isFavorite: false, sortIndex: 0,
      checklist: [], ladderHistory: [], createdAt: date, updatedAt: date
    )
  }

  /// Exhaustivity is off: these tests only assert the sync effects. Every dependency that the existing (plan 02)
  /// `.active` and `onChange` paths touch is stubbed so it can't report "unimplemented".
  private func makeStore(
    syncs: LockIsolated<Int>,
    clock: TestClock<Duration> = TestClock(),
    publishes: LockIsolated<Int> = LockIsolated(0),
    result: @escaping @Sendable () async throws -> SyncReport = { SyncReport(rounds: 1) }
  ) -> TestStoreOf<AppFeature> {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = Date(timeIntervalSince1970: 1_795_186_900)
      $0.marketData.quotes = { _, _ in [] }
      $0.snapshotClient.publish = { _ in publishes.withValue { $0 += 1 } }
      $0.connectivity = .noop
      $0.syncClient.sync = {
        syncs.withValue { $0 += 1 }
        return try await result()
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }
}
```

- [ ] **Step 3: Run the test and confirm it fails**

Run, with `-only-testing:AppFeatureTests/AppFeatureSyncTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **`, with errors like `type 'AppFeature.Action' has no member 'syncFinished'` and `value of type 'DependencyValues' has no member 'syncClient'`.

- [ ] **Step 4: Add the triggers to `AppFeature`**

All edits are in `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`. After plans 02 and 03, `body` has the §12.3 shape: `CombineReducers { BindingReducer(); Scope…; Scope…; Reduce { … } }`, followed by one `.onChange(of: \.watchlist.snapshotInputs) { _, inputs in Reduce { _, _ in publishSnapshot(inputs) } }`. The debounced `publishSnapshot(_:)` helper calls `snapshotClient.alsoSending(to: connectivity).publish(…)`.

1. Add the imports next to the others, keeping them alphabetical:
   ```swift
   import Logging
   import SyncClient
   ```
2. Next to the reducer's other `@Dependency` properties (`clock`, `date`, `snapshotClient`, `connectivity`), add:
   ```swift
     @Dependency(\.syncClient) var syncClient
   ```
3. Add `sync` to the existing `CancelID` enum:
   ```swift
     public enum CancelID: Hashable, Sendable {
       case publishSnapshot
       case sync
     }
   ```
4. Add these two cases to `public enum Action`:
   ```swift
       case syncFinished(SyncReport)
       case syncFailed(String)
   ```
5. **Reuse the existing snapshot helper; don't add one.** Plan 02 already routes both launch and the `snapshotInputs` `.onChange` through `private func publishSnapshot(_ inputs: WatchlistFeature.SnapshotInputs) -> Effect<Action>`, and plan 03 added `connectivity` to its capture list. Leave that helper and its `.onChange` exactly as they are. The only new call site is in `.syncFinished` (item 6).
6. In the `Reduce` inside `CombineReducers`:
   - **The `.scenePhaseChanged(.active)` branch.** Plan 02 returns `.send(.watchlist(.sceneBecameActive))` there. Merge in a sync:
     ```swift
                 case .active:
                   return .merge(.send(.watchlist(.sceneBecameActive)), sync(after: nil))
     ```
     If that branch returns something else, keep its expression as the first argument of the `.merge`.
   - **New cases.** Add these **before** plan 02's catch-all `case .binding, .watchlist, .settings:`:
     ```swift
           case .watchlist(.delegate(.refreshRequested)):
             return sync(after: nil)

           case let .syncFinished(report):
             // SyncEngine writes merged rows straight into @Shared, which onChange can't see (§12.3).
             return report.pulled > 0 ? publishSnapshot(state.watchlist.snapshotInputs) : .none

           case let .syncFailed(message):
             Log.sync.error("Watchlist sync failed: \(message)")
             return .none
     ```
7. **Add the debounce trigger.** Chain a second `.onChange` on the same `CombineReducers`, directly after the snapshot one. It has to wrap the whole composition, because the edits happen in child reducers (§12.3):
   ```swift
     .onChange(of: \.watchlist.items) { _, _ in
       Reduce { _, _ in sync(after: .seconds(2)) }
     }
   ```
   After this edit, `body` looks like this (with plan 02's and plan 03's contents unchanged):
   ```swift
     public var body: some ReducerOf<Self> {
       CombineReducers {
         BindingReducer()
         Scope(state: \.watchlist, action: \.watchlist) { WatchlistFeature() }
         Scope(state: \.settings, action: \.settings) { SettingsFeature() }
         Reduce { state, action in
           // …plan 02/03 cases, plus the cases from item 6…
         }
       }
       .onChange(of: \.watchlist.snapshotInputs) { _, inputs in
         Reduce { _, _ in publishSnapshot(inputs) }
       }
       .onChange(of: \.watchlist.items) { _, _ in
         Reduce { _, _ in sync(after: .seconds(2)) }
       }
     }
   ```
8. Add the sync helper under `// MARK: Private`, next to the existing `publishSnapshot(_:)`:
   ```swift
     /// One sync, optionally debounced. Every trigger shares `CancelID.sync`, so a newer trigger replaces a pending one.
     /// The engine itself is single-flight, so cancelling a caller never cancels a run that is already in progress.
     private func sync(after delay: Duration?) -> Effect<Action> {
       .run { [clock, syncClient] send in
         if let delay {
           try await clock.sleep(for: delay)
         }
         do {
           await send(.syncFinished(try await syncClient.sync()))
         } catch {
           await send(.syncFailed(error.localizedDescription))
         }
       }
       .cancellable(id: CancelID.sync, cancelInFlight: true)
     }
   ```

- [ ] **Step 5: Run the new tests and confirm they pass**

Run, with `-only-testing:AppFeatureTests/AppFeatureSyncTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`, with 6 tests passing. The earlier AppFeature suites are fixed and run in Step 6.

- [ ] **Step 6: Update the earlier exhaustive AppFeature tests that reach the new sync paths**

`.active` and the `.refreshRequested` delegate now sync, and any action that changes `watchlist.items` starts the 2 s debounce. Exhaustive tests from plans 02 and 03 that hit these paths must stub `syncClient.sync` and receive `.syncFinished`. Find them:
```bash
cd /Users/ckai/code/Wait-plan05/Wait/Packages/WaitKit
grep -rn "scenePhaseChanged(.active)\|delegate(.refreshRequested)\|favoriteSwiped\|deleteSwiped\|\.moved(" Tests/AppFeatureTests
```
Expected: matches only in `AppFeatureSyncTests.swift` (this task) and one in `AppFeatureTests.swift`, inside plan 02's `becomingActiveRefreshesQuotesAndPublishesOneSnapshot`. Plan 03's `AppFeatureConnectivityTests` only sends `.appDelegate(.didFinishLaunching)` (and is non-exhaustive), so it needs no change. If the grep shows another exhaustive test, give it the same two edits.

In `Tests/AppFeatureTests/AppFeatureTests.swift`:
1. Add `import SyncClient` to the imports.
2. In `becomingActiveRefreshesQuotesAndPublishesOneSnapshot`, add this stub to its `withDependencies` closure. It waits on the test's clock, so `.syncFinished` arrives at a known point (after the 1 s advance) and can't race `quotesLoaded`:
   ```swift
         $0.syncClient.sync = {
           try await clock.sleep(for: .seconds(1))
           return .empty
         }
   ```
3. Directly after its `await clock.advance(by: .seconds(1))`, add:
   ```swift
       await store.receive(\.syncFinished)
   ```
   The report has `pulled == 0`, so nothing is republished, and the test's `published.value.count == 1` assertion still holds.

Run, with `-only-testing:AppFeatureTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`. Every plan 02/03 AppFeature test passes, plus the 6 new ones.

- [ ] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift \
  Wait/Packages/WaitKit/Tests/AppFeatureTests
git commit -m "$(cat <<'MSG'
feat(app): sync on activation, pull-to-refresh and debounced watchlist edits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

## Chunk 7: Settings, end-to-end check, docs

### Task 15: Settings "Sync" section, and resetting sync state on account deletion

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (the `SettingsFeature` target's dependencies)
- Modify: `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`
- Create: `Wait/Packages/WaitKit/Sources/SettingsFeature/SyncSection.swift`
- Modify: `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`
- Modify: `Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsAccountTests.swift` (plan 04's exhaustive delete-account test now reaches `syncClient.reset()`)
- Test: `Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsSyncTests.swift`

Load swiftui-expert:swiftui-expert-skill before writing the view.

- [ ] **Step 1: Add the dependencies**

In `Wait/Packages/WaitKit/Package.swift`:
- Add `"SyncClient"` and `"Persistence"` to the `SettingsFeature` target's `dependencies` array, if they aren't already there.
- Add `"Persistence"`, `"SyncClient"` and `.dependenciesTestSupport` to the `SettingsFeatureTests` test target, if any of them are missing. The new and updated tests import `Persistence` and `SyncClient`.

- [ ] **Step 2: Write the failing test**

Create `Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsSyncTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Persistence
@testable import SettingsFeature
import SyncClient
import Testing

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SettingsSyncTests {
  @Test
  func syncNowShowsProgressThenFinishes() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.syncClient.sync = { SyncReport(pushed: 1, pulled: 1, applied: 0, rounds: 1) }
    }

    await store.send(.syncNowTapped) { $0.isSyncing = true }
    await store.receive(\.syncFinished) { $0.isSyncing = false }
  }

  @Test
  func aFailedSyncShowsTheMessage() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.syncClient.sync = { throw URLError(.notConnectedToInternet) }
    }

    await store.send(.syncNowTapped) { $0.isSyncing = true }
    await store.receive(\.syncFailed) {
      $0.isSyncing = false
      $0.syncError = URLError(.notConnectedToInternet).localizedDescription
    }
  }

  @Test
  func tappingWhileASyncIsRunningDoesNothing() async {
    var state = SettingsFeature.State()
    state.isSyncing = true
    let store = TestStore(initialState: state) { SettingsFeature() }

    await store.send(.syncNowTapped)
  }

  @Test
  func lastSyncedAtReadsTheSharedSyncState() {
    @Shared(.syncState) var syncState
    $syncState.withLock { $0.lastSyncedAt = Date(timeIntervalSince1970: 1_795_186_800) }

    #expect(SettingsFeature.State().lastSyncedAt == Date(timeIntervalSince1970: 1_795_186_800))
  }

  @Test
  func deletingTheAccountResetsSyncState() async {
    let resets = LockIsolated(0)
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = {}
      $0.identity.reset = {}
      $0.syncClient.reset = { resets.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.deleteAccountTapped)
    await store.send(.alert(.presented(.confirmDeleteAccount)))
    await store.finish()

    #expect(resets.value == 1)
  }
}
```
The last test drives plan 04's delete-account flow (`deleteAccountTapped`, then the alert's confirm action). If plan 04 named the confirm action differently, use plan 04's name. If plan 04's deletion effect calls more dependencies, stub them the same way.

- [ ] **Step 3: Run the test and confirm it fails**

Run, with `-only-testing:SettingsFeatureTests/SettingsSyncTests`, the package command from the chunk header.
Expected: `** TEST BUILD FAILED **`, with errors like `type 'SettingsFeature.Action' has no member 'syncNowTapped'`.

- [ ] **Step 4: Extend `SettingsFeature`**

All edits are in `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`.

1. Add the imports:
   ```swift
   import Persistence
   import SyncClient
   ```
2. Add to `@ObservableState public struct State`:
   ```swift
       @SharedReader(.syncState) public var syncState: SyncState
       public var isSyncing = false
       public var syncError: String?

       public var lastSyncedAt: Date? {
         syncState.lastSyncedAt
       }
   ```
   `.syncState` is declared on `SharedReaderKey` (Task 8), so `@SharedReader(.syncState)` resolves directly.
3. Add to `public enum Action`:
   ```swift
       case syncNowTapped
       case syncFinished(SyncReport)
       case syncFailed(String)
   ```
4. Add next to the other dependencies:
   ```swift
     @Dependency(\.syncClient) var syncClient
   ```
5. Add these cases to the `Reduce`:
   ```swift
         case .syncNowTapped:
           guard !state.isSyncing else { return .none }
           state.isSyncing = true
           state.syncError = nil
           return .run { [syncClient] send in
             do {
               await send(.syncFinished(try await syncClient.sync()))
             } catch {
               await send(.syncFailed(error.localizedDescription))
             }
           }

         case .syncFinished:
           state.isSyncing = false
           return .none

         case let .syncFailed(message):
           state.isSyncing = false
           state.syncError = message
           return .none
   ```
6. In plan 04's account-deletion effect (the `.run` after the confirm alert):
   - Change its capture list from `[apiClient, identity]` to `[apiClient, identity, syncClient]`.
   - Add this line directly after `try await apiClient.deleteAccount()`:
     ```swift
                 await syncClient.reset()
     ```
   Deleting the account keeps the local watchlist (it's offline-first). With the sync state reset, the next sync uploads the list under the new anonymous identity.

- [ ] **Step 5: Write the section view**

Create `Wait/Packages/WaitKit/Sources/SettingsFeature/SyncSection.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

// MARK: - SyncSection

struct SyncSection: View {
  // MARK: Internal

  let lastSyncedAt: Date?
  let isSyncing: Bool
  let errorMessage: String?
  let onSyncNow: () -> Void

  var body: some View {
    Section {
      LabeledContent("Last synced") {
        if let lastSyncedAt {
          Text(lastSyncedAt, format: .relative(presentation: .named))
        } else {
          Text("Never")
        }
      }

      Button(action: onSyncNow) {
        HStack {
          Text("Sync now")
          Spacer()
          if isSyncing {
            ProgressView()
          }
        }
      }
      .disabled(isSyncing)

      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    } header: {
      Text("Sync")
    } footer: {
      Text("Your watchlist syncs when Wait opens, after each change, and when you pull to refresh.")
    }
  }
}

#Preview {
  Form {
    SyncSection(lastSyncedAt: .now.addingTimeInterval(-120), isSyncing: false, errorMessage: nil, onSyncNow: {})
    SyncSection(lastSyncedAt: nil, isSyncing: true, errorMessage: "The Internet connection appears to be offline.", onSyncNow: {})
  }
}
```

- [ ] **Step 6: Show the section**

In `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`, inside the settings `Form`/`List`, add this directly after plan 04's `AccountSection(…)`:
```swift
        SyncSection(
          lastSyncedAt: store.lastSyncedAt,
          isSyncing: store.isSyncing,
          errorMessage: store.syncError,
          onSyncNow: { store.send(.syncNowTapped) }
        )
```

- [ ] **Step 7: Run the tests and confirm they pass**

First update plan 04's exhaustive test, which now reaches `syncClient.reset()` (an unimplemented dependency fails it). In `Tests/SettingsFeatureTests/SettingsAccountTests.swift`:
- Add `import SyncClient`.
- In `deletingAsksForConfirmationThenDeletesAndResetsTheIdentity`, add this to `withDependencies`, after `$0.identity.reset = …`:
  ```swift
        $0.syncClient.reset = {}
  ```
Its expected state changes and received actions stay the same, because `reset()` mutates no feature state.

Run, with `-only-testing:SettingsFeatureTests`, the package command from the chunk header.
Expected: `** TEST SUCCEEDED **`. Plan 02's settings tests, plan 04's updated account tests, and these 5 all pass.

- [ ] **Step 8: Build the app**

Run (overview §5.1):
```bash
xcodebuild -project /Users/ckai/code/Wait-plan05/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/SettingsFeature \
  Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsSyncTests.swift
git commit -m "$(cat <<'MSG'
feat(settings): sync status and Sync now; reset sync state on account deletion

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

### Task 16: End-to-end check (manual: user + executor)

**Files:** none changed. This task is verification only.

- [ ] **Step 1: Deploy the server (manual: user)**

Merge or deploy this branch to the Vercel project, then run the migration from Task 7, Step 10. Export the base URL the app uses (plan 04's `WAIT_API_BASE_URL`):
```bash
export WAIT_API_BASE_URL="https://<your-wait-api-host>"
curl -s "$WAIT_API_BASE_URL/health"
```
Expected: `{"status":"ok","timestamp":"…"}`.

- [ ] **Step 2: Install and launch the app on the simulator**

```bash
cd /Users/ckai/code/Wait-plan05
xcodebuild -project Wait/Wait.xcodeproj -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation -derivedDataPath /tmp/wait-plan05-dd build
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcrun simctl install booted /tmp/wait-plan05-dd/Build/Products/Debug-iphonesimulator/Wait.app
xcrun simctl launch booted com.chenkai.wait
```
Expected: the app opens and shows the watchlist. If the simulator has no data yet, add 2 stocks (for example AAPL and MSFT), and give one of them a note.

- [ ] **Step 3: Get a token for the same identity**

The anonymous ID is shown in Settings → Account (plan 04). Copy it, then:
```bash
export ANON_ID="<paste from Settings>"
export TOKEN=$(curl -s -X POST "$WAIT_API_BASE_URL/api/auth/register" -H 'content-type: application/json' \
  -d "{\"anonymousId\":\"$ANON_ID\"}" | jq -r .token)
curl -s "$WAIT_API_BASE_URL/api/watchlist" -H "authorization: Bearer $TOKEN" | jq '[.items[] | {symbol, memo, isFavorite, ladder}]'
```
Expected: every stock on the device is listed, with the same memo, favorite flag and ladder. This was the first upload, which needs no special case.

- [ ] **Step 4: A local edit reaches the server**

In the app, change a stock's note. Wait about 3 seconds (the 2 s debounce plus the request), then repeat the `GET` from Step 3.
Expected: the new memo appears, and the item's `clientUpdatedAt` is the edit time.

- [ ] **Step 5: A remote edit reaches the device (simulates a second device)**

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
curl -s -X POST "$WAIT_API_BASE_URL/api/watchlist/sync" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d "{\"cursor\":null,\"changes\":[{\"symbol\":\"NVDA\",\"name\":\"NVIDIA Corp\",\"ladder\":{\"buyHigh\":\"120\"},\"memo\":\"added from curl\",\"isFavorite\":true,\"sortIndex\":99,\"checklist\":[],\"ladderHistory\":[],\"clientUpdatedAt\":\"$NOW\",\"deleted\":false}]}" | jq '.changes | length'
```
In the app, pull to refresh the watchlist.
Expected: NVDA appears in Favorites with the note "added from curl". Settings → Sync shows "Last synced" a few seconds ago.

- [ ] **Step 6: A delete becomes a tombstone**

In the app, swipe to delete NVDA and wait about 3 seconds. Then:
```bash
curl -s -X POST "$WAIT_API_BASE_URL/api/watchlist/sync" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"cursor":null,"changes":[]}' | jq '.changes[] | select(.symbol=="NVDA") | {symbol, deleted}'
curl -s "$WAIT_API_BASE_URL/api/watchlist" -H "authorization: Bearer $TOKEN" | jq '[.items[].symbol]'
```
Expected:
- The first command prints `{"symbol":"NVDA","deleted":true}`.
- The second command's list doesn't include NVDA.

- [ ] **Step 7: A reinstall restores the list from the server**

```bash
xcrun simctl uninstall booted com.chenkai.wait
xcrun simctl install booted /tmp/wait-plan05-dd/Build/Products/Debug-iphonesimulator/Wait.app
xcrun simctl launch booted com.chenkai.wait
```
Expected:
- After the first sync (a few seconds after launch), the watchlist shows the same stocks and notes as before. Uninstalling deleted the app-group files, so this data came from the server.
- Settings → Account shows the same anonymous ID, which survived in the Keychain.
- If the ID is different, the simulator dropped the Keychain item (overview risk 9). Report it, and skip this step rather than failing the plan.

- [ ] **Step 8: Record the results**

Add a note to the PR description (or tell the user) saying which of Steps 3–7 passed. If any failed, include the `curl` output.

### Task 17: Docs and final verification

**Files:**
- Modify: `CLAUDE.md` (repo root)
- Modify: `Wait/Packages/WaitKit/README.md`
- Modify: `server/README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Under `## Architecture`, add this subsection after the data-flow subsection:
```markdown
### Watchlist sync (plan 05)

- Offline-first, last-write-wins per item, keyed by `(user, symbol)` (overview §8.5). The local `@Shared(.watchlist)` file stays the UI's source of truth.
- `SyncClient` (`Packages/WaitKit/Sources/SyncClient`) wraps a single-flight `SyncEngine` actor. It pushes pending changes (`SyncPlanner`), and `SyncMerger` applies the rows the server returns. Bookkeeping lives in `sync-state.json` in the app group: the cursor, acknowledged stamps, tombstones and `lastSyncedAt`.
- Local edits go through the Persistence helpers, which stamp `updatedAt` (always truncated to milliseconds) and record tombstones. Remote rows are written directly, never through the helpers.
- Triggers live in `AppFeature`: scene becomes active, a 2 s debounce after any watchlist change, and pull-to-refresh. Settings → Sync shows "Last synced" and has a "Sync now" button.
- Stamps are compared as whole milliseconds (`SyncStamp`), and sync DTOs carry them as pre-formatted ISO strings. Never route them through `JSONEncoder` date strategies.
- Server: `server/src/services/WatchlistSyncService.ts` and `server/src/db/NeonWatchlistRepository.ts` (one CTE for push, `(version, symbol)` cursor for pull). The server's ladder logic in `server/src/domain/ladder.ts` must keep passing `shared/ladder-test-vectors.json`.
```

- [ ] **Step 2: Update `Wait/Packages/WaitKit/README.md`**

Append:
```markdown
## SyncClient

| File | Role |
|---|---|
| `SyncStamp.swift` | Millisecond comparison and a deterministic `yyyy-MM-ddTHH:mm:ss.SSSZ` formatter and parser |
| `SyncChange.swift` | `SyncChange` (upsert or tombstone), `RemoteWatchlistItem`, `SyncReport` |
| `SyncPlanner.swift` | Pure: which items and tombstones the server hasn't acknowledged |
| `SyncMerger.swift` | Pure: acknowledge sent changes; apply remote rows (newer wins, ties go to the server, tombstones, resurrection) |
| `SyncMapping.swift` | Domain ↔ `APIClient` DTOs; clamps outgoing values to the server limits (UTF-16 lengths, 6-decimal anchors) |
| `SyncEngine.swift` | A single-flight actor; at most 10 rounds per run and 50 changes per request |
| `SyncClient.swift` | `@DependencyClient` (`sync`, `reset`); `\.syncClient` |

Tests: `xcodebuild test -scheme WaitKit-Package … -only-testing:SyncClientTests`.
```

- [ ] **Step 3: Update `server/README.md`**

Append:
```markdown
## Watchlist sync

- `POST /api/watchlist/sync` with `{ cursor, changes[] }` (at most 200 changes) returns `{ changes[], cursor, hasMore }`. `GET /api/watchlist` returns the live items. Shapes and rules are in `docs/superpowers/plans/2026-11-22-wait-00-overview.md` §8.4–§8.5.
- Migration: `migrations/003_watchlist.sql`. `npm run migrate` applies it.
- Tests:
  - `test/db/watchlistRepositoryContract.ts` runs against both `NeonWatchlistRepository` (on PGlite) and `MockWatchlistRepository`.
  - The service is tested in `test/services/WatchlistSyncService.test.ts`, and the routes in `test/routes/watchlist.test.ts`.
- `src/domain/ladder.ts` mirrors the Swift ladder. `test/domain/ladder.test.ts` reads `../shared/ladder-test-vectors.json`.
```

- [ ] **Step 4: Run every suite one last time**

```bash
cd /Users/ckai/code/Wait-plan05/server && npm run typecheck && npm test
cd /Users/ckai/code/Wait-plan05/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation
xcodebuild -project /Users/ckai/code/Wait-plan05/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation build
```
Expected, in order:
- `tsc` exits 0, and vitest reports that every file passed.
- `** TEST SUCCEEDED **`.
- `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait-plan05
git add CLAUDE.md Wait/Packages/WaitKit/README.md server/README.md
git commit -m "$(cat <<'MSG'
docs: document watchlist sync on iOS and server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 6: Finish the branch**

Use superpowers:finishing-a-development-branch.
