# WaitKit

All of Wait's code except the three thin Xcode targets (`Wait`, `WaitWidgetExtension`, `WaitWatch`, defined in `Wait/project.yml`).
- Platforms: iOS 17 and watchOS 10.
- `swift-tools-version: 6.1`; every target uses Swift 6 language mode.

## Targets

| Target | Responsibility | Depends on | watchOS | Linked by |
|---|---|---|---|---|
| `Domain` | Value types and pure logic: `PriceLadder`, `Temperature`, `LadderStatus`, `WatchlistItem`, `WatchlistSnapshot`, market types, `MarketCalendar`, `PriceInput`, legacy decoders | – | ✓ | widget, watch, everything |
| `Logging` | `Log.<channel>` on `os.Logger` | – (os) | ✓ | Persistence, MarketDataClient, AppFeature |
| `DesignSystem` | `Palette`, `Spacing`, `StatusPill`, `TemperatureBadge` | Domain | ✓ | widget, watch, features |
| `Persistence` | App-group files, `@Shared(.watchlist)` and `@Shared(.checklistTemplate)`, mutation helpers, `SnapshotStore`, `SnapshotClient`, `LegacyMigration` | Domain, Logging, Sharing, IdentifiedCollections, Dependencies | ✓ | widget, ChecklistFeature, StockDetailsFeature, WatchlistFeature, AppFeature |
| `MarketDataClient` | `\.marketData` dependency: caching decorator (TTL, disk, coalescing, 429 cooldown) around `MarketDataClient.backend`, which reads the Wait backend through `APIClient` | Domain, Logging, APIClient, Dependencies, DependenciesMacros | – | StockChartFeature, StockDetailsFeature, WatchlistFeature |
| `Connectivity` | `\.connectivity` dependency: `WCSession` behind the `WCSessionAdapter` protocol, `ConnectivityEngine` (latest-wins send and receive), snapshot coding, and the watch's `WatchSnapshotStore` | Domain, Dependencies, DependenciesMacros | ✓ | watch, AppFeature |
| `ChecklistFeature` | Per-stock checklist and the checklist template editor (TCA) | Domain, Persistence, DesignSystem, TCA | – | WatchlistFeature, SettingsFeature |
| `StockChartFeature` | Price-history chart: loads one range at a time, chart geometry and view | Domain, MarketDataClient, DesignSystem, TCA | – | StockDetailsFeature |
| `StockDetailsFeature` | The stock detail screen: quote, stats, chart, ladder editor, notes editor, ladder history | Domain, Persistence, MarketDataClient, StockChartFeature, DesignSystem, TCA | – | WatchlistFeature |
| `WatchlistFeature` | The watchlist screen, add-stock sheet, and navigation to details and checklist | Domain, Persistence, MarketDataClient, StockDetailsFeature, ChecklistFeature, DesignSystem, TCA | – | AppFeature |
| `SettingsFeature` | The settings tab: checklist template editor, account section (anonymous ID, Delete Account), sync section ("Last synced", "Sync now"), data attribution | APIClient, ChecklistFeature, DesignSystem, Persistence, SyncClient, TCA | – | AppFeature |
| `AppFeature` | Root feature and `AppView`, deep links, `AppDelegate` (owns the store and runs the legacy migration), snapshot publishing to the widget and the watch, sync triggers | Domain, DesignSystem, Logging, Persistence, Connectivity, SyncClient, SettingsFeature, WatchlistFeature, TCA | – | app |
| `APIClient` | Wait backend client: `HTTPSession` actor, `APIClient` endpoints and DTOs, `KeychainClient`, `IdentityClient` | Domain, Dependencies, DependenciesMacros | – | MarketDataClient, SettingsFeature, SyncClient |
| `SyncClient` | `\.syncClient` dependency: watchlist sync (single-flight `SyncEngine`, pure `SyncPlanner` and `SyncMerger`, DTO mapping) | Domain, Persistence, APIClient, Logging, Sharing, IdentifiedCollections, Dependencies, DependenciesMacros | – | AppFeature, SettingsFeature |
| `NotificationClient` (plan 06) | Push registration | Logging, Dependencies, DependenciesMacros | – | AppFeature, SettingsFeature |

The `NotificationClient` row exists only after plan 06 has run. Each target has a matching `<Target>Tests` test target.

## Conventions
- **Mutations.** Mutate the watchlist only through the `Persistence` helpers. They stamp `updatedAt` truncated to milliseconds, which sync relies on.
- **Wire format.** Prices are `Decimal` and are encoded as decimal strings.
- **Dependencies.** New clients are `@DependencyClient` structs with `@Sendable` closures. Give each one an unimplemented `testValue`, a `previewValue` and a `DependencyValues` accessor.
- **TCA.**
  - Use the canonical scope forms (`Scope(\.child, action: \.child)`, `store.scope(\.child, action: \.child)`, `$store.scope(\.$destination, action: \.destination).case`), because the package enables the `ComposableArchitecture2Deprecations` trait.
  - Use the effect-returning `.onChange(of:) { oldValue, state in Effect }`. It only sees mutations made by the reducer it wraps, so attach it outside `CombineReducers` when it watches child state.
- **watchOS.** Keep watchOS-compatible targets (see the table) free of UIKit and iOS-only APIs. `DesignSystem` guards its UIKit-backed dynamic colors with `#if os(iOS)`; watchOS uses the dark variants.
- **Backend URL.** `APIClient.liveValue` reads `WaitAPIBaseURL` from Info.plist (filled from `WAIT_API_BASE_URL` in `Config/*.xcconfig`). If it is missing, every call throws `APIError.misconfigured` without a request. The app holds no provider keys; `scripts/check-client-has-no-provider-keys.sh` enforces it.
- **Price input.** `PriceInput.parse` accepts a grouping separator only in a well-formed position (`1,234.5`), so `12.50` in `de_DE` is invalid, not 1250.

## Testing

```sh
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation [-only-testing:ConnectivityTests]
```

Or `scripts/test-waitkit.sh [Target[/Suite]]` from the repo root.

- **No `swift test`:** it doesn't work, because the feature targets use iOS-only SwiftUI.
- **Test style:** Swift Testing (`@Suite`, `@Test`, `#expect`). TCA tests are `@MainActor` `TestStore` tests that override every dependency they touch. Suites that touch `@Shared` use `@Suite(.dependencies { $0.defaultFileStorage = .inMemory })`.
- **Fixtures:**
  - Per-target fixtures live in `Tests/<Target>Tests/Fixtures/` (today `DomainTests` and `APIClientTests`).
  - The ladder vectors live outside the package, at `shared/ladder-test-vectors.json`. Tests find them through `#filePath` because the server reads the same file.
- **Not yet compiled by Xcode:** these tests were written in code-only mode. The `Connectivity` suites were additionally run in a throwaway harness (30 tests), but `xcodebuild test` hasn't run on the package. See the repo's `CLAUDE.md`.

## Adding a target

1. Add the `.target` and its `.testTarget` to `Package.swift`. Add a `.library` product if an Xcode target links it.
2. If an Xcode target links it, add `- package: WaitKit` / `product: <Name>` to that target's `dependencies` in `Wait/project.yml`, then run `cd Wait && xcodegen generate`.
3. Clients are `@DependencyClient` structs. Give each one an unimplemented `testValue`, a `previewValue`, and a `DependencyValues` accessor.
4. Keep watchOS-compatible targets free of UIKit and iOS-only APIs.

## APIClient (plan 04)

- `HTTPSession` is an actor. It sends the JWT from memory, registers on first use with `IdentityClient.anonymousID()`, re-registers once on a 401, and maps every non-2xx response to `APIError`.
- `APIClient` (`@Dependency(\.apiClient)`) exposes the market endpoints plus `deleteAccount`. `syncWatchlist` is the sync endpoint. Plan 06 adds device endpoints.
- `KeychainClient` and `IdentityClient` store the anonymous ID under service `com.chenkai.wait`, account `anonymous-id`, synchronizable. Tests always use `KeychainClient.inMemory()`.
- `MarketDataClient.backend(_:)` maps DTOs to Domain types. The live value is `.cached(.backend(.liveValue), disk: .live, now:)`.

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
