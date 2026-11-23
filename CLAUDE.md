# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Wait ("Great Stock Takes Time") is a SwiftUI stock-alert app. The user keeps a watchlist with an *expected price* per stock, and the app shows whether the current price says **buy / almost / wait** (`Stock.tradeAction`, with a 5% "almost" band). The repo has an iOS app (iOS 16), a WidgetKit extension, and a watchOS 9 app. CI runs on Bitrise; its config lives in Bitrise, not in this repo.

## Commands

Everything is in one Xcode project at `Wait/Wait.xcodeproj`. There is no workspace, Tuist, CocoaPods or `Package.swift`. SPM dependencies are declared in the project and pinned in `Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

```sh
# Build the iOS app (also builds the widget and every framework target)
xcodebuild -project Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation build

# Run all unit tests
xcodebuild test -project Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation

# Run one test target / class / method
xcodebuild test -project Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation \
  -only-testing:ChecklistEditFeatureTests/ChecklistEditFeatureTests/testAddNewItem

# Format and lint (configs live in Wait/, so run from there; neither runs as a build phase)
cd Wait && swiftformat .
cd Wait && swiftlint

# Dead-code scan: build the "Unused Code" aggregate target, which runs
#   periphery scan --project Wait.xcodeproj --schemes Wait --targets Wait --format xcode
```

Only three test targets exist: `ChecklistTests`, `ChecklistEditFeatureTests` and `StockDetailsFeatureTests`. The shared `Wait` scheme still has TestableReferences to targets that were deleted (`WaitTests`, `TestTests`, `StockChartsTests`, `SettingsTabTests`, `CacheServiceTests`, `WaitlistTabTests`), so prefer `-only-testing:`. The only shared schemes are `Wait` and `Color`. The watch app has no shared scheme.

## Architecture

### Module graph

Each top-level folder under `Wait/` is a separate dynamic framework target that the app embeds. Only `public` symbols are visible across modules. Dependencies, from the actual imports:

```
Color, Size, Logging(SwiftyBeaver)            leaf modules
Model            -> Color, Money              domain value types (Stock, StockCurrentQuote, StockQuote, StockOverview, ChecklistItem, TradeAction…)
Networking       -> Model, Logging            NetworkingURLBuilder + URLDomain, StockCurrentQuoteNetworkClient
CacheService     -> Model, Logging            Storage<T: Codable> (JSON file), Cache<K,V> (NSCache), StockCache.shared
StockCharts      -> Model, Networking, CacheService, Color   price-history chart data + views
Checklist        -> Model, CacheService, Size, TCA           per-stock checklist (TCA)
ChecklistEditFeature -> Model, Logging, TCA                  checklist template editor (TCA); only used in previews so far
StockDetailsFeature  -> StockCharts, Checklist, CacheService, Networking, Model   the stock detail screen
SettingsTab      -> ChecklistEditFeature, TCA                placeholder view
Wait (app)       -> all of the above; owns the Waitlist screens (Wait/Wait/Waitlist)
WaitWidget       -> CacheService, Networking, Model, Size
```

`UI` (a UIKit number-scroll counter) is a framework target that nothing imports right now.

### Data flow

- **Watchlist source of truth:** `CacheService.StockCache.shared` holds `[Stock]` in memory and persists it through `Storage` to `Documents/stocks`. `Waitlist/DataSource/StockCurrentQuoteDataSource` loads from it, then refreshes every quote in one batch call. `StockDetailsView` writes edits back with `StockCache.shared.saveStock`.
- **APIs:** `NetworkingURLBuilder.buildURL(domain:api:params:)` adds each `URLDomain`'s API key as a query item.
  - Twelve Data (the default): `quote`, `symbol_search` and `time_series`.
  - Alpha Vantage: only the `OVERVIEW` fundamentals call in `StockDetailsFeature/Network`.
  - A batch `quote` call with one symbol returns a different JSON shape. `StockCurrentQuoteNetworkClient.fetchDetails(stocks:)` handles that case separately.
- **On-disk caches:** all are `Storage` JSON files in Documents:
  - chart history: `cache-price-history-<SYMBOL>` (`StockCharts/Stock/ChartCache`)
  - per-stock checklists: `checklist-<SYMBOL>` (`Checklist/ChecklistStorage`, which falls back to `ChecklistItem.allItems`)
  - the checklist template: `checklist-items.json` (`ChecklistEditFeature/DefaultChecklistDataManager`)
- **`Stock` is immutable.** Derive copies with `with(currentQuote:)` or `with(memo:)`. `==` and `hash` ignore `currentQuote`, and hashing uses only `symbol`. Prices are `Money<USD>` (Flight-School/Money), not `Double`.

### Two presentation patterns coexist

1. **Most screens:** a SwiftUI view with an `ObservableObject` `*DataSource`, which calls a `*NetworkClient` that returns a Combine `AnyPublisher` built on `URLSession.dataTaskPublisher`. The exception is `PriceHistoryNetworkClient`, which uses Alamofire + SwiftyJSON callbacks. `StockOverviewNetworkClient` is the pattern for testable DI: a protocol plus a `Default*` implementation injected through `init`, with a mock in tests. Many other data sources still create concrete clients or singletons directly.
2. **Checklist features:** TCA **0.31**. These use the old `Reducer<State, Action, Environment>` closure API, built by `*ReducerBuilder.build()`, and dependencies such as the `uuid` closure or the storage/data-manager protocol go in a `*Environment` struct. `ReducerProtocol`, `@Reducer`, `@Dependency` and `@ObservableState` don't exist in this version. Tests use `TestStore(initialState:reducer:environment:)`.

### watchOS app and connectivity

- `WaitWatch Watch App` can't link the iOS frameworks. It compiles its own internal **copies** of `Stock`, `StockCurrentQuote`, `TradeAction`, `TimeSection`, `Size`, `PriceHistory*` and `StockCurrentQuote*`, and these have already drifted from the originals. When you change model or networking code, check whether the watch copy needs the same change.
- The watch's `StockCurrentQuoteDataSource.fetchStocks()` still uses a hard-coded stock list.
- The watch app isn't embedded in the iOS app target: there's no Embed Watch Content phase.
- `Shared/Connectivity.swift` is compiled into both the iOS app and the watch app. It wraps `WCSession`. iOS `MainView` sends the watchlist symbols on appear, but the watch UI doesn't read `Connectivity.stockSymbols` yet.

### Widget caveat

`WaitWidget` calls `StockCache.shared`, but `Storage` writes to the current process's own Documents directory, not the app-group container. `group.chenkai.wait.contents` is declared only in the Release entitlements and no code uses it. So the widget doesn't see the app's saved stocks unless `Storage` is changed to use the shared container.

### Third-party setup and credentials

- Shake SDK setup is in `Wait/Wait/WaitApp.swift`, and SwiftyBeaver logging setup is in `Logging/Logging.swift`. Log through `Logger.shared.verbose/error`.
- API keys and SDK credentials are hard-coded in `Networking/URLDomain.swift`, `Logging/Logging.swift` and `Wait/WaitApp.swift`.

## Code style

The tools enforce this style through `Wait/.swiftformat` and `Wait/.swiftlint.yml`:

- 2-space indent. `case` is indented inside `switch`. No explicit `self`. Implicit returns. Line length is 180.
- SwiftFormat's `organizeDeclarations` and `markTypes` rules are on:
  - Each type is preceded by `// MARK: - TypeName`.
  - Members are grouped under `// MARK: Lifecycle`, `// MARK: Public`, `// MARK: Internal` and `// MARK: Private`, in that order.
  - Protocol conformances go in extensions marked `// MARK: ProtocolName`.
- File header, from `IDETemplateMacros.plist`:
  ```
  //
  // Created by: <name> on <date>.
  // Copyright © 2021 Wait. All rights reserved.
  //
  ```
