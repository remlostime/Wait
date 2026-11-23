# WaitKit

The local Swift package that holds all of Wait's code except the three thin Xcode targets.

## Targets

| Target | Responsibility | watchOS |
|---|---|---|
| Domain | Value types and pure logic (ladder, temperature, market types, snapshot, legacy decoders) | ✓ |
| Logging | `Log.<channel>` on `os.Logger` | ✓ |
| DesignSystem | Palette, Spacing, StatusPill, TemperatureBadge | ✓ |
| Persistence | App-group files, `@Shared` keys, mutation helpers, snapshot, legacy migration | ✓ |
| MarketDataClient | Market data dependency with a device cache (TTL, disk, coalescing, 429 cooldown) | – |
| ChecklistFeature, StockChartFeature, StockDetailsFeature, WatchlistFeature, SettingsFeature, AppFeature | TCA features and their views | – |

## Conventions
- **Mutations.** Mutate the watchlist only through the `Persistence` helpers. They stamp `updatedAt` truncated to milliseconds, which sync (plan 05) relies on.
- **Wire format.** Prices are `Decimal` and are encoded as decimal strings.
- **Dependencies.** New dependencies are `@DependencyClient` structs with `@Sendable` closures, and they are registered on `DependencyValues`.
- **TCA.**
  - Use the canonical scope forms (`Scope(\.child, action: \.child)`, `store.scope(\.child, action: \.child)`, `$store.scope(\.$destination, action: \.destination).case`), because the package enables the `ComposableArchitecture2Deprecations` trait.
  - Use the effect-returning `.onChange(of:) { oldValue, state in Effect }`. It only sees mutations made by the reducer it wraps, so attach it outside `CombineReducers` when it watches child state.
- **watchOS.** `DesignSystem` guards its UIKit-backed dynamic colors with `#if os(iOS)`; watchOS uses the dark variants.
- **Market data key.** `MarketDataClient.liveValue` reads `TwelveDataAPIKey` from Info.plist and checks it with `TwelveDataAPIKey.isUsable`. An unset key (blank, an unexpanded `$(...)` or the placeholder) makes every call throw `.unavailable` without a request.
- **Price input.** `PriceInput.parse` accepts a grouping separator only in a well-formed position (`1,234.5`), so `12.50` in `de_DE` is invalid, not 1250.
- **Tests.**
  - Every target has a Swift Testing target, and TCA tests are `@MainActor`.
  - Suites that touch `@Shared` use `@Suite(.dependencies { $0.defaultFileStorage = .inMemory })`.
  - Run them with `scripts/test-waitkit.sh [Target[/Suite]]`. `swift test` doesn't work, because the features use iOS-only SwiftUI.
- **Adding a target.** Append its `.target` and `.testTarget` to `Package.swift`. If an Xcode target links it, add a `.library` product and list that product in `Wait/project.yml`.
