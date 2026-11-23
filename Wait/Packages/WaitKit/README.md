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
| `MarketDataClient` | `\.marketData` dependency: caching decorator (TTL, disk, coalescing, 429 cooldown) around the Twelve Data stopgap adapter | Domain, Logging, Dependencies, DependenciesMacros | – | StockChartFeature, StockDetailsFeature, WatchlistFeature |
| `Connectivity` | `\.connectivity` dependency: `WCSession` behind the `WCSessionAdapter` protocol, `ConnectivityEngine` (latest-wins send and receive), snapshot coding, and the watch's `WatchSnapshotStore` | Domain, Dependencies, DependenciesMacros | ✓ | watch, AppFeature |
| `ChecklistFeature` | Per-stock checklist and the checklist template editor (TCA) | Domain, Persistence, DesignSystem, TCA | – | WatchlistFeature, SettingsFeature |
| `StockChartFeature` | Price-history chart: loads one range at a time, chart geometry and view | Domain, MarketDataClient, DesignSystem, TCA | – | StockDetailsFeature |
| `StockDetailsFeature` | The stock detail screen: quote, stats, chart, ladder editor, notes editor, ladder history | Domain, Persistence, MarketDataClient, StockChartFeature, DesignSystem, TCA | – | WatchlistFeature |
| `WatchlistFeature` | The watchlist screen, add-stock sheet, and navigation to details and checklist | Domain, Persistence, MarketDataClient, StockDetailsFeature, ChecklistFeature, DesignSystem, TCA | – | AppFeature |
| `SettingsFeature` | The settings tab (hosts the checklist template editor) | ChecklistFeature, DesignSystem, TCA | – | AppFeature |
| `AppFeature` | Root feature and `AppView`, deep links, `AppDelegate` (owns the store and runs the legacy migration), snapshot publishing to the widget and the watch | Domain, DesignSystem, Logging, Persistence, Connectivity, SettingsFeature, WatchlistFeature, TCA | – | app |
| `APIClient` (plan 04) | Backend client | Domain, Dependencies, DependenciesMacros | – | MarketDataClient, SyncClient |
| `SyncClient` (plan 05) | Watchlist sync | Domain, Persistence, APIClient, Logging, Dependencies | – | AppFeature, SettingsFeature |
| `NotificationClient` (plan 06) | Push registration | Logging, Dependencies, DependenciesMacros | – | AppFeature, SettingsFeature |

The last three rows exist only after their plan has run. Each target has a matching `<Target>Tests` test target.

## Conventions
- **Mutations.** Mutate the watchlist only through the `Persistence` helpers. They stamp `updatedAt` truncated to milliseconds, which sync (plan 05) relies on.
- **Wire format.** Prices are `Decimal` and are encoded as decimal strings.
- **Dependencies.** New clients are `@DependencyClient` structs with `@Sendable` closures. Give each one an unimplemented `testValue`, a `previewValue` and a `DependencyValues` accessor.
- **TCA.**
  - Use the canonical scope forms (`Scope(\.child, action: \.child)`, `store.scope(\.child, action: \.child)`, `$store.scope(\.$destination, action: \.destination).case`), because the package enables the `ComposableArchitecture2Deprecations` trait.
  - Use the effect-returning `.onChange(of:) { oldValue, state in Effect }`. It only sees mutations made by the reducer it wraps, so attach it outside `CombineReducers` when it watches child state.
- **watchOS.** Keep watchOS-compatible targets (see the table) free of UIKit and iOS-only APIs. `DesignSystem` guards its UIKit-backed dynamic colors with `#if os(iOS)`; watchOS uses the dark variants.
- **Market data key.** `MarketDataClient.liveValue` reads `TwelveDataAPIKey` from Info.plist and checks it with `TwelveDataAPIKey.isUsable`. An unset key (blank, an unexpanded `$(...)` or the placeholder) makes every call throw `.unavailable` without a request.
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
  - Per-target fixtures live in `Tests/<Target>Tests/Fixtures/` (today `DomainTests` and `MarketDataClientTests`).
  - The ladder vectors live outside the package, at `shared/ladder-test-vectors.json`. Tests find them through `#filePath` because the server reads the same file.
- **Not yet compiled by Xcode:** these tests were written in code-only mode. The `Connectivity` suites were additionally run in a throwaway harness (30 tests), but `xcodebuild test` hasn't run on the package. See the repo's `CLAUDE.md`.

## Adding a target

1. Add the `.target` and its `.testTarget` to `Package.swift`. Add a `.library` product if an Xcode target links it.
2. If an Xcode target links it, add `- package: WaitKit` / `product: <Name>` to that target's `dependencies` in `Wait/project.yml`, then run `cd Wait && xcodegen generate`.
3. Clients are `@DependencyClient` structs. Give each one an unimplemented `testValue`, a `previewValue`, and a `DependencyValues` accessor.
4. Keep watchOS-compatible targets free of UIKit and iOS-only APIs.
