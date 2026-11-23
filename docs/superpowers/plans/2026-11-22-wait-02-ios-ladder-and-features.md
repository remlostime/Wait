# Wait iOS — Ladder, Features and New UI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy Waitlist and StockDetails screens with TCA 1.26 features built on a new Swift 6 `Domain` (price ladder plus a 0–100 temperature), an app-group `Persistence` layer that migrates the old data, and a cached, rate-limit-safe `MarketDataClient`. Rewrite the widget to use a shared snapshot. Then delete every legacy module.

**Architecture:**
- Leaf targets come first, each test-driven inside `Wait/Packages/WaitKit`:
  - `Domain`: pure value types and the ladder math, checked against shared JSON vectors.
  - `Logging`.
  - `Persistence`: `@Shared(.fileStorage)` in the app group, mutation helpers, snapshot, legacy migration.
  - `MarketDataClient`: a `@DependencyClient` behind a caching actor, with a Twelve Data stopgap adapter.
- Then the TCA features (Checklist, StockChart, editors, StockDetails, AddStock, Watchlist, Settings, AppFeature) and the widget.
- The legacy targets compile next to the new ones until the cutover task deletes them.

**Tech Stack:**
- Swift 6.4 / Xcode 27, iOS 17 / watchOS 10, SwiftUI and Swift Charts.
- TCA 1.26.2 (trait `ComposableArchitecture2Deprecations`), swift-dependencies 1.17, swift-sharing 2.10, swift-identified-collections 1.1.
- Swift Testing, XcodeGen 2.46.

**Spec / contracts:** `docs/superpowers/plans/2026-11-22-wait-00-overview.md`. In particular §5 commands, §6.3 TTLs, §7 domain, §9 wire and app group, §12 paths, keys and extension points. Read it first.

> **Deviation from overview (§12.1 path):** `AppDelegate` lives in the **`AppFeature` package target** at `Packages/WaitKit/Sources/AppFeature/AppDelegate.swift`, not in the app target.
> - The app target links only the `AppFeature` product, so it can't name `StoreOf<AppFeature>` without importing TCA.
> - Keeping the delegate in the package means the app target never imports TCA, and the delegate can be tested.
> - The app target keeps only `Wait/Wait/WaitApp.swift`.
> - Plan 06 adds its `didRegisterForRemoteNotifications…` methods to this file.

---

## Prerequisites

- [ ] **Plan 01 is complete.** `git log --oneline | grep -i "tca 1.26"` shows the plan 01 TCA commit, and the canonical build passes. Plan 01 leaves:
  - `Wait/project.yml`, with three targets: `Wait`, `WaitWidgetExtension`, `WaitWatch`.
  - `Wait/Packages/WaitKit/Package.swift`, containing the legacy targets `DesignSystem`, `Logging` (`LegacyLogger.swift` shim), `Model`, `CacheService`, `Networking`, `StockCharts`, `Checklist`, `ChecklistEditFeature`, `LegacyStockDetails`, `SettingsTab`, and the test targets `ChecklistTests` and `ChecklistEditFeatureTests`.
  - TCA 1.26.2 already declared.
  - `Wait/Config/Base.xcconfig` plus a gitignored `Secrets.xcconfig` that defines `TWELVE_DATA_API_KEY`.
  - Info.plist key `TwelveDataAPIKey = $(TWELVE_DATA_API_KEY)` in the app.
- [ ] **Work in a worktree** off `ck/new-version`, never `master` (superpowers:using-git-worktrees):
  ```sh
  cd /Users/ckai/code/Wait && git worktree add ../Wait-plan02 -b ck/plan02-ladder-features ck/new-version
  ```
  Every command below uses `$(git rev-parse --show-toplevel)`, so it works from anywhere inside the worktree.
- [ ] **Load skills:**
  - `superpowers:test-driven-development` for every task.
  - `swiftui-expert:swiftui-expert-skill` for every task with a `View`.
  - `ios-code-best-practice:ios-code-best-practice`, for its Swift-concurrency and module-dependency sections only.
- [ ] **Simulator:** `xcrun simctl list devices available | grep "iPhone 17 (" ` shows an iOS 27.0 `iPhone 17`.
- [ ] **Twelve Data key:** a fresh key from plan 01's key rotation is in `Wait/Config/Secrets.xcconfig` (`TWELVE_DATA_API_KEY = …`). It's needed only for the manual simulator checks.

### Conventions used in every task
- **New Swift files** start with this header (use the real date):
  ```swift
  //
  // Created by: Claude on 2026-11-22.
  // Copyright © 2021 Wait. All rights reserved.
  //
  ```
  Then `// MARK: - TypeName` and the `Lifecycle / Public / Internal / Private` groups. Indent with 2 spaces. No explicit `self`.
- **Sandboxing:** `xcodebuild` and `xcodegen`, and so both helper scripts, must run **unsandboxed** in agent sessions, because they need the simulator service and the SwiftPM network.
- **Test helper scripts** are created in Task 1 and used by every later task:
  - `scripts/test-waitkit.sh <TestTarget>[/<Suite>] …` runs package tests. It prints only errors, failing tests and the summary, and its exit code matches `xcodebuild`.
  - `scripts/build-app.sh` builds the `Wait` scheme for the iPhone 17 simulator.
- **"Expected FAIL"** for a new type means the test target doesn't compile. You see `error: cannot find 'X' in scope` and `** TEST FAILED **`.
- **"Expected PASS"** shows `** TEST SUCCEEDED **`, and Swift Testing reports `Test run with N tests … passed`.
- **Commit trailer:** every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

## File Structure

All paths are relative to `Wait/` unless they start with `scripts/` or `shared/`, which are relative to the repo root.

| Path | Responsibility |
|---|---|
| `shared/ladder-test-vectors.json` | Shared ladder vectors, byte-identical to overview §7.4. Swift reads it here; TS reads it in plan 05. |
| `scripts/test-waitkit.sh`, `scripts/build-app.sh` | The canonical test and build commands |
| `Packages/WaitKit/Sources/Domain/PriceLadder.swift` | Ladder type, `Rung`, validation, `Codable` |
| `…/Domain/PriceLadder+Evaluation.swift` | Derived fair, rungs, knots, temperature, status, distance to buy |
| `…/Domain/LadderStatus.swift`, `Temperature.swift` | Status enum with rank and title; temperature and band |
| `…/Domain/DecimalCoding.swift` | Decimal ⇄ string helpers for `Codable` containers, `Decimal.doubleValue`, rounding |
| `…/Domain/PriceInput.swift` | Parses and formats locale-aware price text |
| `…/Domain/MarketTypes.swift` | `Quote`, `ChartRange`, `PricePoint`, `PriceSeries`, `SymbolSearchResult`, `CompanyProfile` |
| `…/Domain/MarketCalendar.swift` | NYSE hours in America/New_York (no holiday table) |
| `…/Domain/ChecklistItem.swift`, `ChecklistTemplate.swift`, `LadderRevision.swift`, `WatchlistItem.swift`, `WatchlistSnapshot.swift`, `Date+Milliseconds.swift` | Persisted models and the widget/watch snapshot |
| `…/Domain/Legacy/LegacyStock.swift` | Decoders for the old `stocks` file, and the mapping to `WatchlistItem` |
| `…/Logging/Log.swift` | `os.Logger` channels (`Log.app`, `.network`, `.persistence`, `.ui`, `.sync`, `.push`, `.connectivity`) |
| `…/Persistence/AppGroup.swift`, `SharedKeys.swift`, `Shared+Watchlist.swift`, `SnapshotStore.swift`, `SnapshotClient.swift`, `LegacyMigration.swift` | App-group files, `@Shared` keys, mutation helpers, snapshot I/O, the one-time migration |
| `…/MarketDataClient/MarketDataClient.swift`, `MarketDataError.swift`, `CachePolicy.swift`, `CacheTTL.swift`, `CachingMarketDataClient.swift`, `DiskCache.swift` | Client interface, `liveValue`, TTL rules, caching actor, disk cache |
| `…/MarketDataClient/TwelveData/TwelveDataMarketData.swift`, `TwelveDataDTOs.swift` | Stopgap adapter (deleted in plan 04) |
| `…/DesignSystem/Palette.swift`, `Spacing.swift`, `StatusPill.swift`, `TemperatureBadge.swift`, `LadderStatus+Style.swift` | Design tokens and shared components |
| `…/ChecklistFeature/*`, `StockChartFeature/*`, `StockDetailsFeature/*`, `WatchlistFeature/*`, `SettingsFeature/*`, `AppFeature/*` | TCA features and views (overview §12.1), plus `AppFeature/AppDelegate.swift` |
| `Packages/WaitKit/Tests/<Target>Tests/*` | One Swift Testing target per source target; fixtures in `Fixtures/` |
| `Wait/WaitApp.swift` | App entry point. It holds only `@UIApplicationDelegateAdaptor` and `AppView`. |
| `WaitWidget/WaitWidget.swift`, `WaitWidget/WidgetRowView.swift`, `WaitWidget/WaitWidget.entitlements` | Widget rewritten on `SnapshotStore` |
| `Wait/Wait.entitlements` | Gains the app group in Debug |

---

## Chunk 1: Domain — ladder core

### Task 1: Test scripts, shared vectors, `PriceLadder` and validation

**Files:**
- Create: `scripts/test-waitkit.sh`, `scripts/build-app.sh`
- Create: `shared/ladder-test-vectors.json`
- Create: `Wait/Packages/WaitKit/Sources/Domain/PriceLadder.swift`, `Wait/Packages/WaitKit/Sources/Domain/DecimalCoding.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/LadderVectors.swift`, `Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderValidationTests.swift`, `Wait/Packages/WaitKit/Tests/DomainTests/TestSupport.swift`
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `Domain` product, target and test target)

- [x] **Step 1: Create the helper scripts.** If plan 01 already created files with these names, overwrite them. — scripts created and `bash -n` checked; the `scripts/build-app.sh` baseline run is NOT RUN (code-only)

`scripts/test-waitkit.sh`:
```bash
#!/bin/bash
# Usage: scripts/test-waitkit.sh [TestTarget[/Suite[/test()]] ...]   (no args = all package tests)
# ${ARGS[@]+...} keeps `set -u` happy on macOS bash 3.2 when there are no arguments.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT/Wait/Packages/WaitKit" || exit 1
ARGS=()
for t in "$@"; do ARGS+=("-only-testing:$t"); done
xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation ${ARGS[@]+"${ARGS[@]}"} 2>&1 \
  | tee /tmp/wk-test.log \
  | grep -E "error:|✘|recorded an issue|Test run with|\*\* TEST (SUCCEEDED|FAILED) \*\*"
exit "${PIPESTATUS[0]}"
```

`scripts/build-app.sh`:
```bash
#!/bin/bash
# Usage: scripts/build-app.sh [scheme]   (default scheme: Wait)
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SCHEME="${1:-Wait}"
if [ "$SCHEME" = "WaitWatch" ]; then DEST='platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0'
else DEST='platform=iOS Simulator,name=iPhone 17,OS=27.0'; fi
xcodebuild -project "$ROOT/Wait/Wait.xcodeproj" -scheme "$SCHEME" -destination "$DEST" \
  -skipMacroValidation -skipPackagePluginValidation build 2>&1 \
  | tee /tmp/wait-build.log \
  | grep -E "error:|\*\* BUILD (SUCCEEDED|FAILED) \*\*"
exit "${PIPESTATUS[0]}"
```

Run: `chmod +x scripts/test-waitkit.sh scripts/build-app.sh && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`. This is the plan 01 baseline.

- [x] **Step 2: Create `shared/ladder-test-vectors.json` from overview §7.4.** Extract the file directly from the overview, so it is byte-identical, then check it with `diff`:

Run:
```sh
cd "$(git rev-parse --show-toplevel)" && mkdir -p shared && python3 -I - <<'PY'
import re
overview = open("docs/superpowers/plans/2026-11-22-wait-00-overview.md").read()
section = overview[overview.index("### 7.4"):]
block = re.search(r"```json\n(.*?)\n```", section, re.S).group(1)
open("/tmp/ladder-vectors-from-overview.json", "w").write(block + "\n")
PY
cp /tmp/ladder-vectors-from-overview.json shared/ladder-test-vectors.json
python3 -I -c "import json;d=json.load(open('shared/ladder-test-vectors.json'));print(d['version'],len(d['evaluations']),len(d['alerts']))"
```
Expected: `1 23 11`.

Run this independent check. It re-reads both files and doesn't trust the copy above. Rerun it in Task 29 Step 6, and whenever §7.4 or the JSON file changes:
```sh
cd "$(git rev-parse --show-toplevel)" && python3 -I - <<'PY'
import json, re, sys
overview = open("docs/superpowers/plans/2026-11-22-wait-00-overview.md").read()
block = re.search(r"```json\n(.*?)\n```", overview[overview.index("### 7.4"):], re.S).group(1)
on_disk = open("shared/ladder-test-vectors.json").read()
if on_disk != block + "\n" or json.loads(on_disk) != json.loads(block):
    sys.exit("vectors DIFFER from overview §7.4")
print("vectors match overview")
PY
```
Expected: `vectors match overview`. If §7.4 changes later, re-create the file with the block above, then rerun this check. The Swift and TS suites must both pass in the same commit (overview risk 32).

- [x] **Step 3: Register the `Domain` target in `Package.swift`.** Make three additions and change nothing else:
  - Add `.library(name: "Domain", targets: ["Domain"]),` to the `products:` array.
  - Add `.target(name: "Domain"),` to the `targets:` array.
  - Add `.testTarget(name: "DomainTests", dependencies: ["Domain"]),` to the `targets:` array.

  `Domain` has no `swiftSettings`, so it compiles in the package default Swift 6 mode.
  - SwiftPM refuses to load a package with a source-less target. Create `Wait/Packages/WaitKit/Sources/Domain/PriceLadder.swift` containing only the file header (see Conventions). Step 7 fills it in.

- [x] **Step 4: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/TestSupport.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

/// Exact decimal from a string literal (never via Double).
func dec(_ string: String) -> Decimal {
  Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// `2026-11-20T15:00:00Z`, a Friday at 10:00 ET when the market is open.
let fridayOpen = Date(timeIntervalSince1970: 1_795_186_800)
```

`Wait/Packages/WaitKit/Tests/DomainTests/LadderVectors.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - LadderVectors

/// Decodes `shared/ladder-test-vectors.json` (overview §7.4). The `alerts` section is TS-only and ignored here.
struct LadderVectors: Decodable {
  // MARK: Internal

  enum LadderRef: Decodable {
    case named(String)
    case inline([String: String])

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let name = try? container.decode(String.self) {
        self = .named(name)
      } else {
        self = try .inline(container.decode([String: String].self))
      }
    }
  }

  struct ValidationCase: Decodable {
    struct Failure: Decodable {
      let kind: String
      let rung: String?
      let lower: String?
      let upper: String?
    }

    let ladder: LadderRef
    let valid: Bool
    let error: Failure?
  }

  struct KnotCase: Decodable {
    let ladder: LadderRef
    let derivedFair: Double?
    let knots: [[Double]]
  }

  struct EvaluationCase: Decodable {
    let ladder: LadderRef
    let price: String
    let temperature: Double?
    let band: String?
    let status: String
  }

  let version: Int
  let ladders: [String: [String: String]]
  let validation: [ValidationCase]
  let knots: [KnotCase]
  let evaluations: [EvaluationCase]

  static func load() throws -> LadderVectors {
    // Tests/DomainTests/LadderVectors.swift → repo root is six levels up.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // DomainTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // WaitKit
      .deletingLastPathComponent() // Packages
      .deletingLastPathComponent() // Wait (Xcode folder)
      .deletingLastPathComponent() // repo root
      .appending(path: "shared/ladder-test-vectors.json")
    return try JSONDecoder().decode(LadderVectors.self, from: Data(contentsOf: url))
  }

  func raw(_ ref: LadderRef) -> [String: String] {
    switch ref {
      case let .named(name): ladders[name] ?? [:]
      case let .inline(raw): raw
    }
  }

  func ladder(_ ref: LadderRef) throws(LadderValidationError) -> PriceLadder {
    let raw = raw(ref)
    return try PriceLadder(
      buyLow: raw["buyLow"].flatMap(DecimalCoding.parse),
      buyHigh: raw["buyHigh"].flatMap(DecimalCoding.parse),
      fair: raw["fair"].flatMap(DecimalCoding.parse),
      trim: raw["trim"].flatMap(DecimalCoding.parse),
      sell: raw["sell"].flatMap(DecimalCoding.parse)
    )
  }
}
```

`Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderValidationTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceLadderValidationTests {
  @Test func vectorsValidation() throws {
    let vectors = try LadderVectors.load()
    #expect(vectors.version == 1)
    for testCase in vectors.validation {
      do throws(LadderValidationError) {
        _ = try vectors.ladder(testCase.ladder)
        #expect(testCase.valid, "expected \(testCase.ladder) to be invalid")
      } catch {
        #expect(!testCase.valid, "unexpected error \(error)")
        switch error {
          case let .nonPositive(rung):
            #expect(testCase.error?.kind == "nonPositive")
            #expect(testCase.error?.rung == rung.rawValue)
          case let .outOfOrder(lower, upper):
            #expect(testCase.error?.kind == "outOfOrder")
            #expect(testCase.error?.lower == lower.rawValue)
            #expect(testCase.error?.upper == upper.rawValue)
        }
      }
    }
  }

  @Test func equalAdjacentAnchorsAreAllowed() throws {
    let ladder = try PriceLadder(buyLow: 50, buyHigh: 50)
    #expect(ladder.buyLow == 50)
    #expect(ladder.buyHigh == 50)
  }

  @Test func rejectsNegative() {
    #expect(throws: LadderValidationError.nonPositive(.sell)) {
      try PriceLadder(buyHigh: 10, sell: -1)
    }
  }

  @Test func emptyLadder() {
    #expect(PriceLadder.empty.isEmpty)
    #expect(PriceLadder.empty.value(for: .fair) == nil)
  }

  @Test func encodesDecimalStringsAndOmitsMissingRungs() throws {
    let ladder = try PriceLadder(buyHigh: dec("0.0075"), trim: dec("175.5"))
    let json = try String(decoding: JSONEncoder().encode(ladder), as: UTF8.self)
    #expect(json.contains(#""buyHigh":"0.0075""#))
    #expect(json.contains(#""trim":"175.5""#))
    #expect(!json.contains("buyLow"))
  }

  @Test func decodesStringsOrNumbersAndRoundTrips() throws {
    let fromNumber = try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyHigh":3.133}"#.utf8))
    let fromString = try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyHigh":"3.133"}"#.utf8))
    #expect(fromString.buyHigh == dec("3.133"))
    #expect(abs((fromNumber.buyHigh?.doubleValue ?? 0) - 3.133) < 1e-9)
    let roundTrip = try JSONDecoder().decode(PriceLadder.self, from: JSONEncoder().encode(fromString))
    #expect(roundTrip == fromString)
  }

  @Test func decodingAnInvertedLadderThrows() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyLow":"20","buyHigh":"10"}"#.utf8))
    }
  }
}
```

- [ ] **Step 5: Run the tests and confirm they fail** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests`
Expected FAIL: `error: cannot find type 'PriceLadder' in scope` (and `DecimalCoding`), then `** TEST FAILED **`.

- [x] **Step 6: Implement `DecimalCoding.swift`**

`Wait/Packages/WaitKit/Sources/Domain/DecimalCoding.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DecimalCoding

/// Prices travel as decimal strings (overview D20). These helpers read a string or a number and always write a string.
public enum DecimalCoding {
  // MARK: Public

  public static let posix = Locale(identifier: "en_US_POSIX")

  /// Parses a plain decimal literal such as `"175.50"`, `"-3"` or `"1e-3"`. Returns nil for anything else.
  public static func parse(_ string: String) -> Decimal? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    guard
      !trimmed.isEmpty,
      trimmed.range(of: #"^-?\d+(\.\d+)?([eE][-+]?\d+)?$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    return Decimal(string: trimmed, locale: posix)
  }

  /// `Decimal.description` is locale-independent ("175.5").
  public static func string(_ value: Decimal) -> String {
    value.description
  }
}

public extension Decimal {
  var doubleValue: Double {
    NSDecimalNumber(decimal: self).doubleValue
  }

  /// Rounds half-up to `scale` fractional digits.
  func rounded(scale: Int) -> Decimal {
    var input = self
    var result = Decimal()
    NSDecimalRound(&result, &input, scale, .plain)
    return result
  }
}

public extension KeyedDecodingContainer {
  func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
    guard contains(key), try !decodeNil(forKey: key) else {
      return nil
    }
    if let string = try? decode(String.self, forKey: key) {
      guard let value = DecimalCoding.parse(string) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a decimal: \(string)")
      }
      return value
    }
    return try decode(Decimal.self, forKey: key)
  }

  func decodeDecimal(forKey key: Key) throws -> Decimal {
    guard let value = try decodeDecimalIfPresent(forKey: key) else {
      throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing decimal \(key.stringValue)"))
    }
    return value
  }
}

public extension KeyedEncodingContainer {
  mutating func encodeDecimal(_ value: Decimal, forKey key: Key) throws {
    try encode(DecimalCoding.string(value), forKey: key)
  }

  mutating func encodeDecimalIfPresent(_ value: Decimal?, forKey key: Key) throws {
    if let value {
      try encodeDecimal(value, forKey: key)
    }
  }
}
```

- [x] **Step 7: Replace the contents of `PriceLadder.swift` with the implementation**

`Wait/Packages/WaitKit/Sources/Domain/PriceLadder.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderValidationError

public enum LadderValidationError: Error, Equatable, Sendable {
  case nonPositive(PriceLadder.Rung)
  case outOfOrder(lower: PriceLadder.Rung, upper: PriceLadder.Rung)
}

// MARK: - PriceLadder

/// The user's price anchors (overview §7.2). Present anchors must be > 0 and non-decreasing in rung order.
public struct PriceLadder: Hashable, Sendable {
  // MARK: Lifecycle

  public init(
    buyLow: Decimal? = nil,
    buyHigh: Decimal? = nil,
    fair: Decimal? = nil,
    trim: Decimal? = nil,
    sell: Decimal? = nil
  ) throws(LadderValidationError) {
    let ordered: [(Rung, Decimal?)] = [(.buyLow, buyLow), (.buyHigh, buyHigh), (.fair, fair), (.trim, trim), (.sell, sell)]
    var previous: (rung: Rung, value: Decimal)?
    for (rung, value) in ordered {
      guard let value else {
        continue
      }
      guard value > 0 else {
        throw .nonPositive(rung)
      }
      if let previous, value < previous.value {
        throw .outOfOrder(lower: previous.rung, upper: rung)
      }
      previous = (rung, value)
    }
    self.init(unchecked: buyLow, buyHigh, fair, trim, sell)
  }

  private init(unchecked buyLow: Decimal?, _ buyHigh: Decimal?, _ fair: Decimal?, _ trim: Decimal?, _ sell: Decimal?) {
    self.buyLow = buyLow
    self.buyHigh = buyHigh
    self.fair = fair
    self.trim = trim
    self.sell = sell
  }

  // MARK: Public

  public enum Rung: String, CaseIterable, Codable, Sendable {
    case buyLow
    case buyHigh
    case fair
    case trim
    case sell

    // MARK: Public

    public var score: Double {
      switch self {
        case .buyLow: 10
        case .buyHigh: 30
        case .fair: 50
        case .trim: 80
        case .sell: 95
      }
    }

    public var title: String {
      switch self {
        case .buyLow: "Buy low"
        case .buyHigh: "Buy high"
        case .fair: "Fair"
        case .trim: "Trim"
        case .sell: "Sell"
      }
    }
  }

  public static let empty = PriceLadder(unchecked: nil, nil, nil, nil, nil)

  public private(set) var buyLow: Decimal?
  public private(set) var buyHigh: Decimal?
  public private(set) var fair: Decimal?
  public private(set) var trim: Decimal?
  public private(set) var sell: Decimal?

  public var isEmpty: Bool {
    buyLow == nil && buyHigh == nil && fair == nil && trim == nil && sell == nil
  }

  public func value(for rung: Rung) -> Decimal? {
    switch rung {
      case .buyLow: buyLow
      case .buyHigh: buyHigh
      case .fair: fair
      case .trim: trim
      case .sell: sell
    }
  }
}

// MARK: Codable

extension PriceLadder: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        buyLow: container.decodeDecimalIfPresent(forKey: .buyLow),
        buyHigh: container.decodeDecimalIfPresent(forKey: .buyHigh),
        fair: container.decodeDecimalIfPresent(forKey: .fair),
        trim: container.decodeDecimalIfPresent(forKey: .trim),
        sell: container.decodeDecimalIfPresent(forKey: .sell)
      )
    } catch let error as LadderValidationError {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ladder: \(error)"))
    }
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeDecimalIfPresent(buyLow, forKey: .buyLow)
    try container.encodeDecimalIfPresent(buyHigh, forKey: .buyHigh)
    try container.encodeDecimalIfPresent(fair, forKey: .fair)
    try container.encodeDecimalIfPresent(trim, forKey: .trim)
    try container.encodeDecimalIfPresent(sell, forKey: .sell)
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
```

- [ ] **Step 8: Run the tests and confirm they pass** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`. Swift Testing reports 7 tests passed.

- [x] **Step 9: Commit**
```bash
git add scripts/test-waitkit.sh scripts/build-app.sh shared/ladder-test-vectors.json Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Domain Wait/Packages/WaitKit/Tests/DomainTests
git commit -m "feat(domain): add PriceLadder with validation and shared ladder vectors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Knots, derived fair, temperature and band

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Domain/Temperature.swift`, `Wait/Packages/WaitKit/Sources/Domain/PriceLadder+Evaluation.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderTemperatureTests.swift`

- [x] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderTemperatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceLadderTemperatureTests {
  @Test func vectorsKnots() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.knots {
      let ladder = try vectors.ladder(testCase.ladder)
      let knots = ladder.knots()
      #expect(knots.count == testCase.knots.count, "\(testCase.ladder)")
      for (actual, expected) in zip(knots, testCase.knots) {
        #expect(abs(actual.price - expected[0]) < 0.001, "\(testCase.ladder) price \(actual.price) vs \(expected[0])")
        #expect(abs(actual.score - expected[1]) < 0.001)
      }
      if let derived = testCase.derivedFair {
        let value = try #require(ladder.derivedFair)
        #expect(abs(value.doubleValue - derived) < 0.001)
      } else {
        #expect(ladder.derivedFair == nil)
      }
    }
  }

  @Test func vectorsTemperatures() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.evaluations {
      let ladder = try vectors.ladder(testCase.ladder)
      let temperature = ladder.temperature(at: dec(testCase.price))
      if let expected = testCase.temperature {
        let actual = try #require(temperature, "\(testCase.ladder) @ \(testCase.price)")
        #expect(abs(actual.value - expected) <= 0.05, "\(testCase.ladder) @ \(testCase.price): \(actual.value) vs \(expected)")
        #expect(actual.band.rawValue == testCase.band)
      } else {
        #expect(temperature == nil)
        #expect(testCase.band == nil)
      }
    }
  }

  @Test func derivedFairUsesTenSevenths() throws {
    let ladder = try PriceLadder(buyHigh: 175)
    #expect(ladder.derivedFair == Decimal(250))
    #expect(ladder.effectiveFair == Decimal(250))
    #expect(ladder.rungs.map(\.rung) == [.buyHigh, .fair])
    #expect(ladder.rungs.last?.isDerived == true)
  }

  @Test func noDerivedFairWhenAnUpperAnchorExists() throws {
    let ladder = try PriceLadder(buyHigh: 100, trim: 150)
    #expect(ladder.derivedFair == nil)
    #expect(ladder.effectiveFair == nil)
  }

  @Test func bandBoundaries() {
    #expect(Temperature(value: 19.99).band == .freezing)
    #expect(Temperature(value: 20).band == .cold)
    #expect(Temperature(value: 40).band == .neutral)
    #expect(Temperature(value: 60).band == .warm)
    #expect(Temperature(value: 80).band == .hot)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests/PriceLadderTemperatureTests`
Expected FAIL: `error: value of type 'PriceLadder' has no member 'knots'` and `cannot find 'Temperature' in scope`.

- [x] **Step 3: Implement `Temperature.swift`**

`Wait/Packages/WaitKit/Sources/Domain/Temperature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - TemperatureBand

public enum TemperatureBand: String, CaseIterable, Sendable {
  case freezing
  case cold
  case neutral
  case warm
  case hot

  // MARK: Public

  public var title: String {
    switch self {
      case .freezing: "Freezing"
      case .cold: "Cold"
      case .neutral: "Neutral"
      case .warm: "Warm"
      case .hot: "Hot"
    }
  }
}

// MARK: - Temperature

/// 0 means cold/cheap and 100 means hot/expensive. Interpolated from the ladder knots.
public struct Temperature: Equatable, Sendable {
  // MARK: Lifecycle

  public init(value: Double) {
    self.value = value
  }

  // MARK: Public

  public let value: Double

  public var band: TemperatureBand {
    switch value {
      case ..<20: .freezing
      case ..<40: .cold
      case ..<60: .neutral
      case ..<80: .warm
      default: .hot
    }
  }

  /// Whole-degree label, e.g. "27°".
  public var formatted: String {
    "\(Int(value.rounded()))°"
  }
}
```

- [x] **Step 4: Implement `PriceLadder+Evaluation.swift`.** It also holds the status and distance helpers, which Task 3 tests.

`Wait/Packages/WaitKit/Sources/Domain/PriceLadder+Evaluation.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderRung

public struct LadderRung: Equatable, Sendable {
  public let rung: PriceLadder.Rung
  public let price: Decimal
  /// True for the synthesized fair (`(buyHigh ?? buyLow) × 10 / 7`).
  public let isDerived: Bool
}

// MARK: - LadderKnot

public struct LadderKnot: Equatable, Sendable {
  public let price: Double
  public let score: Double
}

public extension PriceLadder {
  /// Only when a buy band exists and fair, trim and sell are all absent (overview §7.2 step 2).
  var derivedFair: Decimal? {
    guard fair == nil, trim == nil, sell == nil, let band = buyHigh ?? buyLow else {
      return nil
    }
    return band * 10 / 7
  }

  var effectiveFair: Decimal? {
    fair ?? derivedFair
  }

  /// Present anchors in rung order, with the derived fair in place of a missing fair.
  var rungs: [LadderRung] {
    Rung.allCases.compactMap { rung in
      if let value = value(for: rung) {
        return LadderRung(rung: rung, price: value, isDerived: false)
      }
      if rung == .fair, let derived = derivedFair {
        return LadderRung(rung: .fair, price: derived, isDerived: true)
      }
      return nil
    }
  }

  /// Anchor knots plus synthetic tails `(0.5 × lowest, 0)` and `(1.5 × highest, 100)`, stable-sorted by price.
  func knots() -> [LadderKnot] {
    let anchors = rungs.map { LadderKnot(price: $0.price.doubleValue, score: $0.rung.score) }
    guard let lowest = anchors.map(\.price).min(), let highest = anchors.map(\.price).max() else {
      return []
    }
    let all = anchors + [LadderKnot(price: lowest * 0.5, score: 0), LadderKnot(price: highest * 1.5, score: 100)]
    return all.enumerated()
      .sorted { ($0.element.price, $0.offset) < ($1.element.price, $1.offset) }
      .map(\.element)
  }

  /// Piecewise-linear, clamped. On duplicate knots the first matching segment wins. Nil when there are no anchors.
  func temperature(at price: Decimal) -> Temperature? {
    let knots = knots()
    guard let first = knots.first, let last = knots.last else {
      return nil
    }
    let p = price.doubleValue
    if p <= first.price {
      return Temperature(value: first.score)
    }
    if p >= last.price {
      return Temperature(value: last.score)
    }
    for (a, b) in zip(knots, knots.dropFirst()) where a.price <= p && p <= b.price {
      guard b.price != a.price else {
        return Temperature(value: a.score)
      }
      return Temperature(value: a.score + (p - a.price) / (b.price - a.price) * (b.score - a.score))
    }
    return Temperature(value: last.score)
  }

  /// Price vs anchors, compared as Decimal (overview §7.2 step 5).
  func status(at price: Decimal) -> LadderStatus {
    guard !isEmpty else {
      return .noAnchors
    }
    if let sell, price >= sell {
      return .sell
    }
    if let trim, price >= trim {
      return .trim
    }
    if let fair = effectiveFair, price >= fair {
      return .atOrAboveFair
    }
    if let buyLow, price <= buyLow {
      return .deepBuy
    }
    if let buyHigh, price <= buyHigh {
      return .buyZone
    }
    return .watch
  }

  /// `(buyHigh − price) / price × 100`. A value ≥ 0 means the price is inside the buy band.
  func distanceToBuy(from price: Decimal) -> Double? {
    guard let buyHigh, price > 0 else {
      return nil
    }
    return ((buyHigh - price) / price * 100).doubleValue
  }
}
```

- [x] **Step 5: Create a minimal `LadderStatus.swift`** so that `status(at:)` compiles. Task 3 adds the full version and its tests.

`Wait/Packages/WaitKit/Sources/Domain/LadderStatus.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderStatus

public enum LadderStatus: String, Codable, CaseIterable, Sendable {
  case deepBuy = "DEEP_BUY"
  case buyZone = "BUY_ZONE"
  case watch = "WATCH"
  case atOrAboveFair = "AT_OR_ABOVE_FAIR"
  case trim = "TRIM"
  case sell = "SELL"
  case noAnchors = "NO_ANCHORS"
}
```

- [ ] **Step 6: Run the tests and confirm they pass** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`, with all 12 Domain tests passing.

- [x] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Domain Wait/Packages/WaitKit/Tests/DomainTests
git commit -m "feat(domain): ladder knots, derived fair and temperature bands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: `LadderStatus` rank and titles, status vectors, distance to buy

**Files:**
- Modify: `Wait/Packages/WaitKit/Sources/Domain/LadderStatus.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderStatusTests.swift`

- [x] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderStatusTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceLadderStatusTests {
  @Test func vectorsStatuses() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.evaluations {
      let ladder = try vectors.ladder(testCase.ladder)
      #expect(ladder.status(at: dec(testCase.price)).rawValue == testCase.status, "\(testCase.ladder) @ \(testCase.price)")
    }
  }

  @Test func ranks() {
    #expect(LadderStatus.deepBuy.rank == 0)
    #expect(LadderStatus.buyZone.rank == 1)
    #expect(LadderStatus.watch.rank == 2)
    #expect(LadderStatus.atOrAboveFair.rank == 3)
    #expect(LadderStatus.trim.rank == 4)
    #expect(LadderStatus.sell.rank == 5)
    #expect(LadderStatus.noAnchors.rank == nil)
  }

  @Test func titles() {
    #expect(LadderStatus.atOrAboveFair.title == "At/Above Fair")
    #expect(LadderStatus.buyZone.title == "Buy Zone")
  }

  @Test func distanceToBuy() throws {
    let ladder = try PriceLadder(buyHigh: 90)
    #expect(ladder.distanceToBuy(from: 100) == -10)
    #expect(ladder.distanceToBuy(from: 90) == 0)
    #expect(try PriceLadder(fair: 10).distanceToBuy(from: 5) == nil)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests/PriceLadderStatusTests`
Expected FAIL: `error: value of type 'LadderStatus' has no member 'rank'`.

- [x] **Step 3: Replace `LadderStatus.swift`**

`Wait/Packages/WaitKit/Sources/Domain/LadderStatus.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderStatus

/// Raw values are the wire strings shared with the server (overview §7.1).
public enum LadderStatus: String, Codable, CaseIterable, Sendable {
  case deepBuy = "DEEP_BUY"
  case buyZone = "BUY_ZONE"
  case watch = "WATCH"
  case atOrAboveFair = "AT_OR_ABOVE_FAIR"
  case trim = "TRIM"
  case sell = "SELL"
  case noAnchors = "NO_ANCHORS"

  // MARK: Public

  /// 0 (cheapest) … 5 (richest). Nil for `noAnchors`.
  public var rank: Int? {
    switch self {
      case .deepBuy: 0
      case .buyZone: 1
      case .watch: 2
      case .atOrAboveFair: 3
      case .trim: 4
      case .sell: 5
      case .noAnchors: nil
    }
  }

  public var title: String {
    switch self {
      case .deepBuy: "Deep Buy"
      case .buyZone: "Buy Zone"
      case .watch: "Watch"
      case .atOrAboveFair: "At/Above Fair"
      case .trim: "Trim"
      case .sell: "Sell"
      case .noAnchors: "No Anchors"
    }
  }

  public var isBuyZone: Bool {
    self == .deepBuy || self == .buyZone
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [x] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Domain/LadderStatus.swift Wait/Packages/WaitKit/Tests/DomainTests/PriceLadderStatusTests.swift
git commit -m "feat(domain): ladder status rank, titles and distance to buy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 2: Domain — price input and market types

### Task 4: `PriceInput`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Domain/PriceInput.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/PriceInputTests.swift`

- [x] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/PriceInputTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceInputTests {
  let us = Locale(identifier: "en_US")
  let de = Locale(identifier: "de_DE")

  @Test func parsesGroupedUSInput() {
    #expect(PriceInput.parse("1,234.50", locale: us) == .some(dec("1234.50")))
    #expect(PriceInput.parse("$12", locale: us) == .some(dec("12")))
    #expect(PriceInput.parse(" 0.0075 ", locale: us) == .some(dec("0.0075")))
  }

  @Test func parsesGermanDecimalComma() {
    #expect(PriceInput.parse("0,75", locale: de) == .some(dec("0.75")))
    #expect(PriceInput.parse("1.234,5", locale: de) == .some(dec("1234.5")))
  }

  @Test func emptyIsSomeNil() {
    let result = PriceInput.parse("   ", locale: us)
    #expect(result != nil)
    #expect(result! == nil)
  }

  @Test func invalidIsNil() {
    #expect(PriceInput.parse("abc", locale: us) == nil)
    #expect(PriceInput.parse("-5", locale: us) == nil)
    #expect(PriceInput.parse("1.2.3", locale: us) == nil)
  }

  @Test func formats() {
    #expect(PriceInput.format(dec("1234.5"), locale: us) == "1234.5")
    #expect(PriceInput.format(dec("1234.5"), locale: de) == "1234,5")
    #expect(PriceInput.format(dec("16"), locale: us) == "16")
    #expect(PriceInput.format(nil, locale: us) == "")
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests/PriceInputTests`
Expected FAIL: `error: cannot find 'PriceInput' in scope`.

- [x] **Step 3: Implement**

`Wait/Packages/WaitKit/Sources/Domain/PriceInput.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - PriceInput

/// Parses user-typed prices in the user's locale and formats ladder values back for editing.
public enum PriceInput {
  /// `nil` means invalid. `.some(nil)` means the field is empty. Negative values are invalid.
  public static func parse(_ text: String, locale: Locale) -> Decimal?? {
    var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if string.isEmpty {
      return .some(nil)
    }
    for symbol in ["$", locale.currencySymbol ?? ""] where !symbol.isEmpty {
      string = string.replacingOccurrences(of: symbol, with: "")
    }
    let decimalSeparator = locale.decimalSeparator ?? "."
    let groupingSeparator = locale.groupingSeparator ?? ","
    for space in [" ", "\u{00A0}", "\u{202F}"] {
      string = string.replacingOccurrences(of: space, with: "")
    }
    if !groupingSeparator.isEmpty, groupingSeparator != decimalSeparator {
      string = string.replacingOccurrences(of: groupingSeparator, with: "")
    }
    if decimalSeparator != "." {
      string = string.replacingOccurrences(of: decimalSeparator, with: ".")
    }
    guard
      string.range(of: #"^(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil,
      let value = Decimal(string: string, locale: DecimalCoding.posix)
    else {
      return nil
    }
    return value
  }

  /// No grouping, 0–4 fraction digits, in the given locale. Empty string for nil.
  public static func format(_ value: Decimal?, locale: Locale) -> String {
    guard let value else {
      return ""
    }
    return value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 4)))
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests/PriceInputTests`
Expected PASS: 5 tests pass.

- [x] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Domain/PriceInput.swift Wait/Packages/WaitKit/Tests/DomainTests/PriceInputTests.swift
git commit -m "feat(domain): locale-aware PriceInput parse and format

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Market types and `MarketCalendar`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Domain/MarketTypes.swift`, `Wait/Packages/WaitKit/Sources/Domain/MarketCalendar.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/MarketCalendarTests.swift`, `Wait/Packages/WaitKit/Tests/DomainTests/MarketTypesCodingTests.swift`

- [x] **Step 1: Write the failing tests.** All the expected UTC instants below were cross-checked with Python `zoneinfo`.

`Wait/Packages/WaitKit/Tests/DomainTests/MarketCalendarTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct MarketCalendarTests {
  func utc(_ iso: String) throws -> Date {
    try Date(iso, strategy: .iso8601)
  }

  @Test func openAndClosedDuringAWeekday() throws {
    #expect(try MarketCalendar.isOpen(at: utc("2026-11-20T15:00:00Z"))) // Fri 10:00 EST
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-20T21:00:00Z"))) // Fri 16:00 EST (close is exclusive)
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-21T15:00:00Z"))) // Saturday
  }

  @Test func nextOpenAcrossDSTStart() throws {
    // Fri 2026-03-06 16:00 EST → Mon 2026-03-09 09:30 EDT
    #expect(try MarketCalendar.nextOpen(after: utc("2026-03-06T21:00:00Z")) == utc("2026-03-09T13:30:00Z"))
  }

  @Test func nextOpenAcrossDSTEnd() throws {
    // Fri 2026-10-30 16:00 EDT → Mon 2026-11-02 09:30 EST
    #expect(try MarketCalendar.nextOpen(after: utc("2026-10-30T20:00:00Z")) == utc("2026-11-02T14:30:00Z"))
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-02T14:00:00Z")))
    #expect(try MarketCalendar.isOpen(at: utc("2026-11-02T14:30:00Z")))
  }

  @Test func nextClose() throws {
    #expect(try MarketCalendar.nextClose(after: utc("2026-11-20T15:00:00Z")) == utc("2026-11-20T21:00:00Z"))
    #expect(try MarketCalendar.nextClose(after: utc("2026-11-20T22:00:00Z")) == utc("2026-11-23T21:00:00Z"))
  }

  @Test func postCloseWindow() throws {
    #expect(try MarketCalendar.isWithinPostClose(utc("2026-11-20T21:10:00Z"), minutes: 30))
    #expect(try !MarketCalendar.isWithinPostClose(utc("2026-11-20T21:40:00Z"), minutes: 30))
    #expect(try !MarketCalendar.isWithinPostClose(utc("2026-11-21T21:10:00Z"), minutes: 30))
  }
}
```

`Wait/Packages/WaitKit/Tests/DomainTests/MarketTypesCodingTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct MarketTypesCodingTests {
  @Test func quoteRoundTripsWithDecimalStrings() throws {
    let quote = Quote(symbol: "AAPL", price: dec("189.98"), previousClose: dec("187.66"), changePercent: 1.23, volume: 1000, asOf: fridayOpen)
    let data = try JSONEncoder().encode(quote)
    #expect(String(decoding: data, as: UTF8.self).contains(#""price":"189.98""#))
    #expect(try JSONDecoder().decode(Quote.self, from: data) == quote)
  }

  @Test func quoteMarkedStale() {
    let quote = Quote(symbol: "AAPL", price: 1, asOf: fridayOpen)
    #expect(quote.with(isStale: true).isStale)
    #expect(quote.with(isStale: true).price == 1)
  }

  @Test func seriesRoundTrips() throws {
    let series = PriceSeries(symbol: "AAPL", range: .oneDay, points: [PricePoint(date: fridayOpen, close: dec("0.0075"))], asOf: fridayOpen, delayedMinutes: 15)
    #expect(try JSONDecoder().decode(PriceSeries.self, from: JSONEncoder().encode(series)) == series)
  }

  @Test func seriesWithoutOptionalFieldsDecodes() throws {
    let json = #"{"symbol":"AAPL","range":"1Y","points":[],"asOf":0}"#
    let series = try JSONDecoder().decode(PriceSeries.self, from: Data(json.utf8))
    #expect(series.isStale == false)
    #expect(series.delayedMinutes == nil)
  }

  @Test func chartRangeRawValues() {
    #expect(ChartRange.allCases.map(\.rawValue) == ["1D", "1W", "1M", "1Y", "5Y"])
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests/MarketCalendarTests DomainTests/MarketTypesCodingTests`
Expected FAIL: `error: cannot find 'MarketCalendar' in scope` and `cannot find 'Quote' in scope`.

- [x] **Step 3: Implement `MarketCalendar.swift`**

`Wait/Packages/WaitKit/Sources/Domain/MarketCalendar.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - MarketCalendar

/// Regular NYSE/Nasdaq session, Mon–Fri 09:30–16:00 America/New_York. There is no holiday table; on a holiday the cache simply refetches once.
public enum MarketCalendar {
  // MARK: Public

  public static let timeZone = TimeZone(identifier: "America/New_York")!

  public static func isOpen(at date: Date) -> Bool {
    guard isWeekday(date) else {
      return false
    }
    return date >= open(on: date) && date < close(on: date)
  }

  public static func nextOpen(after date: Date) -> Date {
    nextSessionBoundary(after: date, boundary: open(on:))
  }

  public static func nextClose(after date: Date) -> Date {
    nextSessionBoundary(after: date, boundary: close(on:))
  }

  /// True on a weekday in `[close, close + minutes)`.
  public static func isWithinPostClose(_ date: Date, minutes: Int) -> Bool {
    guard isWeekday(date) else {
      return false
    }
    let close = close(on: date)
    return date >= close && date < close.addingTimeInterval(TimeInterval(minutes * 60))
  }

  // MARK: Private

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private static func isWeekday(_ date: Date) -> Bool {
    let weekday = calendar.component(.weekday, from: date)
    return weekday != 1 && weekday != 7
  }

  private static func open(on date: Date) -> Date {
    calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date)!
  }

  private static func close(on date: Date) -> Date {
    calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)!
  }

  private static func nextSessionBoundary(after date: Date, boundary: (Date) -> Date) -> Date {
    var day = calendar.startOfDay(for: date)
    for _ in 0 ..< 8 {
      if isWeekday(day) {
        let candidate = boundary(day)
        if candidate > date {
          return candidate
        }
      }
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return boundary(day)
  }
}
```

- [x] **Step 4: Implement `MarketTypes.swift`**

`Wait/Packages/WaitKit/Sources/Domain/MarketTypes.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChartRange

/// Raw values match the server `range` query parameter (overview §7.1).
public enum ChartRange: String, CaseIterable, Codable, Hashable, Sendable {
  case oneDay = "1D"
  case oneWeek = "1W"
  case oneMonth = "1M"
  case oneYear = "1Y"
  case fiveYears = "5Y"

  // MARK: Public

  public var title: String {
    rawValue
  }
}

// MARK: - Quote

public struct Quote: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    price: Decimal,
    previousClose: Decimal? = nil,
    open: Decimal? = nil,
    high: Decimal? = nil,
    low: Decimal? = nil,
    change: Decimal? = nil,
    changePercent: Double? = nil,
    volume: Int? = nil,
    fiftyTwoWeekHigh: Decimal? = nil,
    fiftyTwoWeekLow: Decimal? = nil,
    asOf: Date,
    isStale: Bool = false
  ) {
    self.symbol = symbol
    self.price = price
    self.previousClose = previousClose
    self.open = open
    self.high = high
    self.low = low
    self.change = change
    self.changePercent = changePercent
    self.volume = volume
    self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
    self.fiftyTwoWeekLow = fiftyTwoWeekLow
    self.asOf = asOf
    self.isStale = isStale
  }

  // MARK: Public

  public let symbol: String
  public let price: Decimal
  public let previousClose: Decimal?
  public let open: Decimal?
  public let high: Decimal?
  public let low: Decimal?
  public let change: Decimal?
  public let changePercent: Double?
  public let volume: Int?
  public let fiftyTwoWeekHigh: Decimal?
  public let fiftyTwoWeekLow: Decimal?
  public let asOf: Date
  public let isStale: Bool

  public func with(isStale: Bool) -> Quote {
    Quote(
      symbol: symbol, price: price, previousClose: previousClose, open: open, high: high, low: low, change: change,
      changePercent: changePercent, volume: volume, fiftyTwoWeekHigh: fiftyTwoWeekHigh, fiftyTwoWeekLow: fiftyTwoWeekLow,
      asOf: asOf, isStale: isStale
    )
  }
}

// MARK: Codable

extension Quote: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      price: c.decodeDecimal(forKey: .price),
      previousClose: c.decodeDecimalIfPresent(forKey: .previousClose),
      open: c.decodeDecimalIfPresent(forKey: .open),
      high: c.decodeDecimalIfPresent(forKey: .high),
      low: c.decodeDecimalIfPresent(forKey: .low),
      change: c.decodeDecimalIfPresent(forKey: .change),
      changePercent: c.decodeIfPresent(Double.self, forKey: .changePercent),
      volume: c.decodeIfPresent(Int.self, forKey: .volume),
      fiftyTwoWeekHigh: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekHigh),
      fiftyTwoWeekLow: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekLow),
      asOf: c.decode(Date.self, forKey: .asOf),
      isStale: c.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encodeDecimal(price, forKey: .price)
    try c.encodeDecimalIfPresent(previousClose, forKey: .previousClose)
    try c.encodeDecimalIfPresent(open, forKey: .open)
    try c.encodeDecimalIfPresent(high, forKey: .high)
    try c.encodeDecimalIfPresent(low, forKey: .low)
    try c.encodeDecimalIfPresent(change, forKey: .change)
    try c.encodeIfPresent(changePercent, forKey: .changePercent)
    try c.encodeIfPresent(volume, forKey: .volume)
    try c.encodeDecimalIfPresent(fiftyTwoWeekHigh, forKey: .fiftyTwoWeekHigh)
    try c.encodeDecimalIfPresent(fiftyTwoWeekLow, forKey: .fiftyTwoWeekLow)
    try c.encode(asOf, forKey: .asOf)
    try c.encode(isStale, forKey: .isStale)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, price, previousClose, open, high, low, change, changePercent, volume, fiftyTwoWeekHigh, fiftyTwoWeekLow, asOf, isStale
  }
}

// MARK: - PricePoint

public struct PricePoint: Equatable, Sendable {
  // MARK: Lifecycle

  public init(date: Date, close: Decimal) {
    self.date = date
    self.close = close
  }

  // MARK: Public

  public let date: Date
  public let close: Decimal
}

// MARK: Codable

extension PricePoint: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(date: c.decode(Date.self, forKey: .date), close: c.decodeDecimal(forKey: .close))
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(date, forKey: .date)
    try c.encodeDecimal(close, forKey: .close)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case date, close
  }
}

// MARK: - PriceSeries

public struct PriceSeries: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(symbol: String, range: ChartRange, points: [PricePoint], asOf: Date, delayedMinutes: Int? = nil, isStale: Bool = false) {
    self.symbol = symbol
    self.range = range
    self.points = points
    self.asOf = asOf
    self.delayedMinutes = delayedMinutes
    self.isStale = isStale
  }

  // MARK: Public

  public let symbol: String
  public let range: ChartRange
  /// Oldest first.
  public let points: [PricePoint]
  public let asOf: Date
  public let delayedMinutes: Int?
  public let isStale: Bool

  public func with(isStale: Bool) -> PriceSeries {
    PriceSeries(symbol: symbol, range: range, points: points, asOf: asOf, delayedMinutes: delayedMinutes, isStale: isStale)
  }
}

// MARK: Decodable

extension PriceSeries {
  /// `delayedMinutes` and `isStale` are optional, so older cache entries and server payloads without them still decode.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      range: c.decode(ChartRange.self, forKey: .range),
      points: c.decode([PricePoint].self, forKey: .points),
      asOf: c.decode(Date.self, forKey: .asOf),
      delayedMinutes: c.decodeIfPresent(Int.self, forKey: .delayedMinutes),
      isStale: c.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
    )
  }

  private enum CodingKeys: String, CodingKey {
    case symbol, range, points, asOf, delayedMinutes, isStale
  }
}

// MARK: - SymbolSearchResult

public struct SymbolSearchResult: Codable, Equatable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(symbol: String, name: String, exchange: String? = nil, type: String? = nil) {
    self.symbol = symbol
    self.name = name
    self.exchange = exchange
    self.type = type
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let exchange: String?
  public let type: String?

  public var id: String {
    symbol
  }
}

// MARK: - CompanyProfile

/// Fundamentals. Plan 02 has no source for these (Twelve Data stopgap). Plan 04 fills them from the backend.
public struct CompanyProfile: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String? = nil,
    exchange: String? = nil,
    industry: String? = nil,
    logoURL: URL? = nil,
    marketCap: Decimal? = nil,
    peRatio: Double? = nil,
    pbRatio: Double? = nil,
    dividendYield: Double? = nil,
    roe: Double? = nil,
    roa: Double? = nil,
    profitMargin: Double? = nil,
    fiftyTwoWeekHigh: Decimal? = nil,
    fiftyTwoWeekLow: Decimal? = nil,
    beta: Double? = nil,
    asOf: Date
  ) {
    self.symbol = symbol
    self.name = name
    self.exchange = exchange
    self.industry = industry
    self.logoURL = logoURL
    self.marketCap = marketCap
    self.peRatio = peRatio
    self.pbRatio = pbRatio
    self.dividendYield = dividendYield
    self.roe = roe
    self.roa = roa
    self.profitMargin = profitMargin
    self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
    self.fiftyTwoWeekLow = fiftyTwoWeekLow
    self.beta = beta
    self.asOf = asOf
  }

  // MARK: Public

  public let symbol: String
  public let name: String?
  public let exchange: String?
  public let industry: String?
  public let logoURL: URL?
  public let marketCap: Decimal?
  public let peRatio: Double?
  public let pbRatio: Double?
  public let dividendYield: Double?
  public let roe: Double?
  public let roa: Double?
  public let profitMargin: Double?
  public let fiftyTwoWeekHigh: Decimal?
  public let fiftyTwoWeekLow: Decimal?
  public let beta: Double?
  public let asOf: Date
}

// MARK: Codable

extension CompanyProfile: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      name: c.decodeIfPresent(String.self, forKey: .name),
      exchange: c.decodeIfPresent(String.self, forKey: .exchange),
      industry: c.decodeIfPresent(String.self, forKey: .industry),
      logoURL: c.decodeIfPresent(URL.self, forKey: .logoURL),
      marketCap: c.decodeDecimalIfPresent(forKey: .marketCap),
      peRatio: c.decodeIfPresent(Double.self, forKey: .peRatio),
      pbRatio: c.decodeIfPresent(Double.self, forKey: .pbRatio),
      dividendYield: c.decodeIfPresent(Double.self, forKey: .dividendYield),
      roe: c.decodeIfPresent(Double.self, forKey: .roe),
      roa: c.decodeIfPresent(Double.self, forKey: .roa),
      profitMargin: c.decodeIfPresent(Double.self, forKey: .profitMargin),
      fiftyTwoWeekHigh: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekHigh),
      fiftyTwoWeekLow: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekLow),
      beta: c.decodeIfPresent(Double.self, forKey: .beta),
      asOf: c.decode(Date.self, forKey: .asOf)
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(exchange, forKey: .exchange)
    try c.encodeIfPresent(industry, forKey: .industry)
    try c.encodeIfPresent(logoURL, forKey: .logoURL)
    try c.encodeDecimalIfPresent(marketCap, forKey: .marketCap)
    try c.encodeIfPresent(peRatio, forKey: .peRatio)
    try c.encodeIfPresent(pbRatio, forKey: .pbRatio)
    try c.encodeIfPresent(dividendYield, forKey: .dividendYield)
    try c.encodeIfPresent(roe, forKey: .roe)
    try c.encodeIfPresent(roa, forKey: .roa)
    try c.encodeIfPresent(profitMargin, forKey: .profitMargin)
    try c.encodeDecimalIfPresent(fiftyTwoWeekHigh, forKey: .fiftyTwoWeekHigh)
    try c.encodeDecimalIfPresent(fiftyTwoWeekLow, forKey: .fiftyTwoWeekLow)
    try c.encodeIfPresent(beta, forKey: .beta)
    try c.encode(asOf, forKey: .asOf)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, exchange, industry, logoURL, marketCap, peRatio, pbRatio, dividendYield, roe, roa, profitMargin
    case fiftyTwoWeekHigh, fiftyTwoWeekLow, beta, asOf
  }
}
```

- [ ] **Step 5: Run the tests and confirm they pass** — NOT RUN (code-only)

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [x] **Step 6: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Domain Wait/Packages/WaitKit/Tests/DomainTests
git commit -m "feat(domain): market value types and DST-aware MarketCalendar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 3: Domain — watchlist models and legacy decoding

### Task 6: Watchlist models, snapshot and millisecond timestamps

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Domain/Date+Milliseconds.swift`, `ChecklistItem.swift`, `ChecklistTemplate.swift`, `LadderRevision.swift`, `WatchlistItem.swift`, `WatchlistSnapshot.swift`. All of these go under `Sources/Domain/`.
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/WatchlistModelTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/WatchlistModelTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct WatchlistModelTests {
  @Test func millisecondTruncationIsIdempotentAndMatchesISOParsing() throws {
    let raw = Date(timeIntervalSince1970: 1_795_186_800.123_9)
    let truncated = raw.truncatedToMilliseconds
    #expect(truncated.millisecondsSince1970 == 1_795_186_800_123)
    #expect(truncated.truncatedToMilliseconds == truncated)
    let parsed = try Date("2026-11-20T15:00:00.123Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    #expect(parsed.isSameMillisecond(as: truncated))
  }

  @Test func initsTruncateDatesToMilliseconds() throws {
    let raw = Date(timeIntervalSince1970: 1_795_186_800.123_9)
    let item = WatchlistItem(symbol: "AAPL", name: "Apple", createdAt: raw, updatedAt: raw)
    #expect(item.createdAt.millisecondsSince1970 == 1_795_186_800_123)
    #expect(item.updatedAt == raw.truncatedToMilliseconds)
    #expect(LadderRevision(date: raw, ladder: .empty).date == raw.truncatedToMilliseconds)
  }

  @Test func symbolIsUppercasedAndDefaultsApply() {
    let item = WatchlistItem(symbol: "aapl", name: "Apple", createdAt: fridayOpen, updatedAt: fridayOpen)
    #expect(item.symbol == "AAPL")
    #expect(item.id == "AAPL")
    #expect(item.ladder.isEmpty)
    #expect(item.memo.isEmpty)
    #expect(!item.isFavorite)
  }

  @Test func itemDecodesWithOnlyASymbol() throws {
    let item = try JSONDecoder().decode(WatchlistItem.self, from: Data(#"{"symbol":"msft"}"#.utf8))
    #expect(item.symbol == "MSFT")
    #expect(item.name == "MSFT")
    #expect(item.checklist.isEmpty)
  }

  @Test func itemRoundTrips() throws {
    let item = WatchlistItem(
      symbol: "PINS",
      name: "Pinterest",
      ladder: try PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33),
      memo: "line 1\nline 2",
      isFavorite: true,
      sortIndex: 3,
      checklist: [ChecklistItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Wait 30 min", isChecked: true)],
      ladderHistory: [LadderRevision(date: fridayOpen, ladder: try PriceLadder(buyHigh: 16))],
      createdAt: fridayOpen,
      updatedAt: fridayOpen
    )
    #expect(try JSONDecoder().decode(WatchlistItem.self, from: JSONEncoder().encode(item)) == item)
  }

  @Test func checklistItemDecodesLegacyShape() throws {
    let json = #"{"name":"等30分钟再决定","isChecked":true,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#
    let item = try JSONDecoder().decode(ChecklistItem.self, from: Data(json.utf8))
    #expect(item.isChecked)
    #expect(item.name == "等30分钟再决定")
  }

  @Test func templateHasSeventeenDeterministicItems() {
    #expect(ChecklistTemplate.defaultPrompts.count == 17)
    #expect(ChecklistTemplate.defaultItems.map(\.id) == ChecklistTemplate.defaultItems.map(\.id))
    #expect(ChecklistTemplate.defaultItems.first?.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    #expect(ChecklistTemplate.defaultItems.allSatisfy { !$0.isChecked })
  }

  @Test func snapshotOrdersFavoritesFirstAndScoresRows() throws {
    let pins = WatchlistItem(symbol: "PINS", name: "Pinterest", ladder: try PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33), sortIndex: 0, createdAt: fridayOpen, updatedAt: fridayOpen)
    let aapl = WatchlistItem(symbol: "AAPL", name: "Apple", isFavorite: true, sortIndex: 1, createdAt: fridayOpen, updatedAt: fridayOpen)
    let quotes = ["PINS": Quote(symbol: "PINS", price: dec("14.20"), changePercent: -1.5, asOf: fridayOpen)]
    let snapshot = WatchlistSnapshot.make(items: [pins, aapl], quotes: quotes, now: fridayOpen)
    #expect(snapshot.rows.map(\.symbol) == ["AAPL", "PINS"])
    #expect(snapshot.rows[1].status == .buyZone)
    #expect(abs((snapshot.rows[1].temperature ?? 0) - 21.0) < 0.05)
    #expect(snapshot.rows[0].price == nil)
    #expect(snapshot.rows[0].status == nil)
    #expect(snapshot.quotesAsOf == fridayOpen)
    #expect(try JSONDecoder().decode(WatchlistSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh DomainTests/WatchlistModelTests`
Expected FAIL: `error: cannot find 'WatchlistItem' in scope`, along with `truncatedToMilliseconds`, `ChecklistItem` and `WatchlistSnapshot`.

- [ ] **Step 3: Implement `Date+Milliseconds.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

/// Every persisted or synced timestamp is truncated to whole milliseconds (overview D21).
public extension Date {
  /// Whole milliseconds since 1970. The +0.001 absorbs Double error, so re-truncating a truncated date is stable.
  var millisecondsSince1970: Int64 {
    Int64((timeIntervalSince1970 * 1000 + 0.001).rounded(.down))
  }

  var truncatedToMilliseconds: Date {
    Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000)
  }

  /// Use this, not `==`, when comparing a local stamp with one echoed by the server.
  func isSameMillisecond(as other: Date) -> Bool {
    millisecondsSince1970 == other.millisecondsSince1970
  }
}
```

- [ ] **Step 4: Implement `ChecklistItem.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChecklistItem

/// The JSON keys (`id`, `name`, `isChecked`) match the legacy `Model.ChecklistItem` files.
public struct ChecklistItem: Codable, Equatable, Hashable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(id: UUID, name: String, isChecked: Bool = false) {
    self.id = id
    self.name = name
    self.isChecked = isChecked
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    isChecked = try c.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
  }

  // MARK: Public

  public var id: UUID
  public var name: String
  public var isChecked: Bool

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case id, name, isChecked
  }
}
```

- [ ] **Step 5: Implement `ChecklistTemplate.swift`.** The prompts are copied verbatim from legacy `Model/ChecklistItem.swift` `allItems`.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChecklistTemplate

/// The default per-stock checklist. The UUIDs are deterministic, so tests and migrations are stable.
public enum ChecklistTemplate {
  public static let defaultPrompts: [String] = [
    "等30分钟再决定",
    "愿意持有10年吗",
    "wash sale - vested date, 30 days rule etc",
    "管理团队健康情况",
    "我是不是听别人的评论才想买这支股票？",
    "我有没有做过仔细的研究？多长时间？研究过哪些方面？",
    "卖家为什么想卖？",
    "还有什么我没考虑到的问题？",
    "公司有可能破产吗？",
    "如果这家公司每年的增长率保持在20%以上是否合理？",
    "有什么情况要卖出股票？",
    "这是好行业吗？",
    "是好公司吗？",
    "价格够低吗？",
    "如果价格够低？为什么那么低？是暂时的还是长久的？",
    "别人为什么要卖？",
    "去雪球和seeking alpha看看反对的观点。你能反驳吗",
  ]

  public static var defaultItems: [ChecklistItem] {
    defaultPrompts.enumerated().map { offset, prompt in
      ChecklistItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!, name: prompt)
    }
  }
}
```

- [ ] **Step 6: Implement `LadderRevision.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderRevision

/// One entry in a stock's ladder history, recorded each time the user saves a changed ladder.
public struct LadderRevision: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  /// `date` is truncated to milliseconds (overview D21).
  public init(date: Date, ladder: PriceLadder) {
    self.date = date.truncatedToMilliseconds
    self.ladder = ladder
  }

  // MARK: Public

  public static let maxCount = 200

  public var date: Date
  public var ladder: PriceLadder
}
```

- [ ] **Step 7: Implement `WatchlistItem.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WatchlistItem

/// One watched stock. Quotes are not stored here. `updatedAt` is the last-write-wins clock (overview §8.5). The init truncates both dates to milliseconds (D21).
public struct WatchlistItem: Equatable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    ladder: PriceLadder = .empty,
    memo: String = "",
    isFavorite: Bool = false,
    sortIndex: Int = 0,
    checklist: [ChecklistItem] = [],
    ladderHistory: [LadderRevision] = [],
    createdAt: Date,
    updatedAt: Date
  ) {
    self.symbol = symbol.uppercased()
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.createdAt = createdAt.truncatedToMilliseconds
    self.updatedAt = updatedAt.truncatedToMilliseconds
  }

  // MARK: Public

  public let symbol: String
  public var name: String
  public var ladder: PriceLadder
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItem]
  /// Oldest first, at most `LadderRevision.maxCount` entries.
  public var ladderHistory: [LadderRevision]
  public var createdAt: Date
  public var updatedAt: Date

  public var id: String {
    symbol
  }

  public var checkedCount: Int {
    checklist.filter(\.isChecked).count
  }
}

// MARK: Codable

extension WatchlistItem: Codable {
  // MARK: Lifecycle

  /// Every field except `symbol` is optional, so the format can grow without breaking old files.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let symbol = try c.decode(String.self, forKey: .symbol).uppercased()
    let createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSinceReferenceDate: 0)
    try self.init(
      symbol: symbol,
      name: c.decodeIfPresent(String.self, forKey: .name) ?? symbol,
      ladder: c.decodeIfPresent(PriceLadder.self, forKey: .ladder) ?? .empty,
      memo: c.decodeIfPresent(String.self, forKey: .memo) ?? "",
      isFavorite: c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false,
      sortIndex: c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0,
      checklist: c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? [],
      ladderHistory: c.decodeIfPresent([LadderRevision].self, forKey: .ladderHistory) ?? [],
      createdAt: createdAt,
      updatedAt: c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(name, forKey: .name)
    try c.encode(ladder, forKey: .ladder)
    try c.encode(memo, forKey: .memo)
    try c.encode(isFavorite, forKey: .isFavorite)
    try c.encode(sortIndex, forKey: .sortIndex)
    try c.encode(checklist, forKey: .checklist)
    try c.encode(ladderHistory, forKey: .ladderHistory)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(updatedAt, forKey: .updatedAt)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, ladder, memo, isFavorite, sortIndex, checklist, ladderHistory, createdAt, updatedAt
  }
}
```

- [ ] **Step 8: Implement `WatchlistSnapshot.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WatchlistSnapshot

/// The read-only view of the watchlist that the app publishes for the widget (app group `snapshot.json`) and the watch (WCSession, plan 03).
public struct WatchlistSnapshot: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(generatedAt: Date, quotesAsOf: Date?, rows: [Row]) {
    self.generatedAt = generatedAt
    self.quotesAsOf = quotesAsOf
    self.rows = rows
  }

  // MARK: Public

  public struct Row: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
      symbol: String,
      name: String,
      price: Decimal?,
      changePercent: Double?,
      status: LadderStatus?,
      temperature: Double?,
      ladder: PriceLadder,
      isFavorite: Bool
    ) {
      self.symbol = symbol
      self.name = name
      self.price = price
      self.changePercent = changePercent
      self.status = status
      self.temperature = temperature
      self.ladder = ladder
      self.isFavorite = isFavorite
    }

    // MARK: Public

    public let symbol: String
    public let name: String
    public let price: Decimal?
    public let changePercent: Double?
    public let status: LadderStatus?
    public let temperature: Double?
    public let ladder: PriceLadder
    public let isFavorite: Bool

    public var id: String {
      symbol
    }
  }

  public let generatedAt: Date
  /// The oldest quote time among the rows that have a quote.
  public let quotesAsOf: Date?
  /// Favorites first, then by `sortIndex`.
  public let rows: [Row]

  public static func make(items: [WatchlistItem], quotes: [String: Quote], now: Date) -> WatchlistSnapshot {
    let ordered = items.sorted { ($0.isFavorite ? 0 : 1, $0.sortIndex) < ($1.isFavorite ? 0 : 1, $1.sortIndex) }
    let rows = ordered.map { item in
      let quote = quotes[item.symbol]
      return Row(
        symbol: item.symbol,
        name: item.name,
        price: quote?.price,
        changePercent: quote?.changePercent,
        status: quote.map { item.ladder.status(at: $0.price) },
        temperature: quote.flatMap { item.ladder.temperature(at: $0.price)?.value },
        ladder: item.ladder,
        isFavorite: item.isFavorite
      )
    }
    let asOf = ordered.compactMap { quotes[$0.symbol]?.asOf }.min()
    return WatchlistSnapshot(generatedAt: now, quotesAsOf: asOf, rows: rows)
  }
}

// MARK: - WatchlistSnapshot.Row + Codable

extension WatchlistSnapshot.Row: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      name: c.decode(String.self, forKey: .name),
      price: c.decodeDecimalIfPresent(forKey: .price),
      changePercent: c.decodeIfPresent(Double.self, forKey: .changePercent),
      status: c.decodeIfPresent(LadderStatus.self, forKey: .status),
      temperature: c.decodeIfPresent(Double.self, forKey: .temperature),
      ladder: c.decodeIfPresent(PriceLadder.self, forKey: .ladder) ?? .empty,
      isFavorite: c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(name, forKey: .name)
    try c.encodeDecimalIfPresent(price, forKey: .price)
    try c.encodeIfPresent(changePercent, forKey: .changePercent)
    try c.encodeIfPresent(status, forKey: .status)
    try c.encodeIfPresent(temperature, forKey: .temperature)
    try c.encode(ladder, forKey: .ladder)
    try c.encode(isFavorite, forKey: .isFavorite)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, price, changePercent, status, temperature, ladder, isFavorite
  }
}
```

- [ ] **Step 9: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Domain Wait/Packages/WaitKit/Tests/DomainTests
git commit -m "feat(domain): watchlist item, checklist template, snapshot and ms timestamps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Legacy `stocks` decoding and mapping to `WatchlistItem`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Domain/Legacy/LegacyStock.swift`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/Fixtures/legacy-stocks.json`
- Create: `Wait/Packages/WaitKit/Tests/DomainTests/LegacyStockTests.swift`
- Modify: `Wait/Packages/WaitKit/Package.swift` (`DomainTests` gains a resource)

- [ ] **Step 1: Add the fixture resource.** In `Package.swift`, change the `DomainTests` test target to:
```swift
.testTarget(name: "DomainTests", dependencies: ["Domain"], resources: [.copy("Fixtures")]),
```

- [ ] **Step 2: Create the fixture.** It uses the exact legacy on-disk shape: the Money keyed container `{amount, currencyCode}`, `Double` dates measured from the 2001 reference date (`JSONEncoder` default), a duplicate `AAPL`, the `"Empty"` placeholder, a lower-case symbol, a string amount, and a zero target.

`Wait/Packages/WaitKit/Tests/DomainTests/Fixtures/legacy-stocks.json`:
```json
[
  {
    "symbol": "AAPL",
    "name": "Apple Inc",
    "expectedPrice": { "amount": 150.12000000000001, "currencyCode": "USD" },
    "memo": "Long term\nhold",
    "currentQuote": {
      "symbol": "AAPL", "name": "Apple Inc",
      "open": { "amount": 189.1, "currencyCode": "USD" }, "high": { "amount": 190, "currencyCode": "USD" },
      "low": { "amount": 188, "currencyCode": "USD" }, "close": { "amount": 189.5, "currencyCode": "USD" },
      "volume": "1000", "datetime": 690000000, "percentChange": "1.2"
    },
    "expectedPriceHistory": [
      { "date": 690000000.1234567, "price": { "amount": 160, "currencyCode": "USD" } },
      { "date": 700000000, "price": { "amount": 150.12000000000001, "currencyCode": "USD" } }
    ]
  },
  {
    "symbol": "Empty", "name": "Empty", "expectedPrice": { "amount": 0, "currencyCode": "USD" }, "memo": "Empty",
    "currentQuote": { "symbol": "empty", "name": "Empty", "open": { "amount": 0, "currencyCode": "USD" }, "high": { "amount": 0, "currencyCode": "USD" },
      "low": { "amount": 0, "currencyCode": "USD" }, "close": { "amount": 0, "currencyCode": "USD" }, "volume": "0", "datetime": 690000000, "percentChange": "0" },
    "expectedPriceHistory": []
  },
  {
    "symbol": "AAPL", "name": "Apple duplicate", "expectedPrice": { "amount": 1, "currencyCode": "USD" }, "memo": "dup",
    "expectedPriceHistory": []
  },
  {
    "symbol": " baba ", "name": "Alibaba", "expectedPrice": { "amount": "80.5", "currencyCode": "USD" }, "memo": "",
    "expectedPriceHistory": []
  },
  {
    "symbol": "BABA", "name": "Alibaba duplicate", "expectedPrice": { "amount": "1", "currencyCode": "USD" }, "memo": "dup"
  },
  {
    "symbol": "ZERO", "name": "Zero target", "expectedPrice": { "amount": 0, "currencyCode": "USD" }
  }
]
```

- [ ] **Step 3: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DomainTests/LegacyStockTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct LegacyStockTests {
  func fixture() throws -> [LegacyStock] {
    let url = try #require(Bundle.module.url(forResource: "legacy-stocks", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([LegacyStock].self, from: Data(contentsOf: url))
  }

  @Test func decodesTheLegacyMoneyShapes() throws {
    let stocks = try fixture()
    #expect(stocks.count == 6)
    #expect(stocks[0].expectedPrice?.amount.rounded(scale: 4) == dec("150.12"))
    #expect(stocks[3].expectedPrice?.amount == dec("80.5"))
    #expect(stocks[0].expectedPriceHistory?.first?.date == Date(timeIntervalSinceReferenceDate: 690_000_000.123_456_7))
    #expect(stocks[5].memo == nil)
  }

  @Test func legacyMoneyAcceptsSingleValues() throws {
    let number = try JSONDecoder().decode(LegacyMoney.self, from: Data("12.5".utf8))
    let string = try JSONDecoder().decode(LegacyMoney.self, from: Data(#""12.5""#.utf8))
    #expect(number.amount == dec("12.5"))
    #expect(string.amount == dec("12.5"))
  }

  @Test func mapsSkipsEmptyAndDedupes() throws {
    let now = fridayOpen
    let aaplChecklist = [ChecklistItem(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, name: "Custom", isChecked: true)]
    let items = LegacyStockMapper.items(
      from: try fixture(),
      checklists: ["AAPL": aaplChecklist, "BABA": []],
      template: ChecklistTemplate.defaultItems,
      now: now
    )
    #expect(items.map(\.symbol) == ["AAPL", "BABA", "ZERO"])
    #expect(items.map(\.sortIndex) == [0, 1, 2])

    let aapl = items[0]
    #expect(aapl.name == "Apple Inc")
    #expect(aapl.memo == "Long term\nhold")
    #expect(aapl.ladder == (try PriceLadder(buyHigh: dec("150.12"))))
    #expect(aapl.ladderHistory.count == 2)
    #expect(aapl.ladderHistory[0].ladder.buyHigh == 160)
    // D21: the fractional legacy date is truncated to whole milliseconds (2022-11-13T02:40:00.123Z).
    #expect(aapl.createdAt.millisecondsSince1970 == 1_668_307_200_123)
    #expect(aapl.ladderHistory[0].date == aapl.createdAt)
    #expect(aapl.updatedAt == now)
    #expect(!aapl.isFavorite)
    #expect(aapl.checklist == aaplChecklist)

    #expect(items[1].name == "Alibaba") // " baba " and "BABA" map to the same key; the first one wins
    #expect(items[1].ladder.buyHigh == dec("80.5"))
    #expect(items[1].createdAt == now)
    #expect(items[1].checklist.isEmpty) // looked up under the mapped key "BABA"
    #expect(items[2].checklist == ChecklistTemplate.defaultItems)
    #expect(items[2].ladder.isEmpty)
  }
}
```

- [ ] **Step 4: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh DomainTests/LegacyStockTests`
Expected FAIL: `error: cannot find type 'LegacyStock' in scope`.

- [ ] **Step 5: Implement**

`Wait/Packages/WaitKit/Sources/Domain/Legacy/LegacyStock.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LegacyMoney

/// Decodes Flight-School `Money<USD>`. That type encoded as `{"amount": <number|string>, "currencyCode": "USD"}` and decoded single values too.
public struct LegacyMoney: Decodable, Sendable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: CodingKeys.self), keyed.contains(.amount) {
      amount = try keyed.decodeDecimal(forKey: .amount)
      return
    }
    let single = try decoder.singleValueContainer()
    if let string = try? single.decode(String.self) {
      guard let value = DecimalCoding.parse(string) else {
        throw DecodingError.dataCorruptedError(in: single, debugDescription: "Not a decimal: \(string)")
      }
      amount = value
    } else {
      amount = try single.decode(Decimal.self)
    }
  }

  // MARK: Public

  public let amount: Decimal

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case amount
  }
}

// MARK: - LegacyPriceHistory

public struct LegacyPriceHistory: Decodable, Sendable {
  public let date: Date
  public let price: LegacyMoney
}

// MARK: - LegacyStock

/// The legacy `Model.Stock` as written to `Documents/stocks`. `currentQuote` is ignored.
public struct LegacyStock: Decodable, Sendable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    symbol = try c.decode(String.self, forKey: .symbol)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    expectedPrice = try c.decodeIfPresent(LegacyMoney.self, forKey: .expectedPrice)
    memo = try c.decodeIfPresent(String.self, forKey: .memo)
    expectedPriceHistory = try c.decodeIfPresent([LegacyPriceHistory].self, forKey: .expectedPriceHistory)
  }

  // MARK: Public

  public let symbol: String
  public let name: String?
  public let expectedPrice: LegacyMoney?
  public let memo: String?
  public let expectedPriceHistory: [LegacyPriceHistory]?

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, expectedPrice, memo, expectedPriceHistory
  }
}

// MARK: - WatchlistItem + Legacy

public extension WatchlistItem {
  /// Overview §7.6:
  /// - `expectedPrice` becomes `buyHigh`, rounded to 4 decimal places. A value ≤ 0 gives an empty ladder.
  /// - Each history entry becomes `LadderRevision(buyHigh:)`.
  /// - `isFavorite` is false.
  /// - `createdAt` is the first history date, otherwise `now`. All dates are truncated to milliseconds (D21).
  init?(legacy: LegacyStock, index: Int, checklist: [ChecklistItem], now: Date) {
    let symbol = legacy.symbol.trimmingCharacters(in: .whitespaces)
    guard !symbol.isEmpty, symbol != "Empty" else {
      return nil
    }
    let history: [LadderRevision] = (legacy.expectedPriceHistory ?? []).compactMap { entry in
      let price = entry.price.amount.rounded(scale: 4)
      guard price > 0, let ladder = try? PriceLadder(buyHigh: price) else {
        return nil
      }
      return LadderRevision(date: entry.date, ladder: ladder)
    }
    let buyHigh = legacy.expectedPrice.map { $0.amount.rounded(scale: 4) }
    let ladder = buyHigh.flatMap { $0 > 0 ? try? PriceLadder(buyHigh: $0) : nil } ?? .empty
    let stamp = now.truncatedToMilliseconds
    self.init(
      symbol: symbol,
      name: legacy.name ?? symbol,
      ladder: ladder,
      memo: legacy.memo ?? "",
      isFavorite: false,
      sortIndex: index,
      checklist: checklist,
      ladderHistory: Array(history.suffix(LadderRevision.maxCount)),
      createdAt: history.first?.date ?? stamp,
      updatedAt: stamp
    )
  }
}

// MARK: - LegacyStockMapper

public enum LegacyStockMapper {
  /// Skips `"Empty"`, keeps the first occurrence of each mapped symbol (trimmed, upper-cased), and assigns `sortIndex` by output position.
  /// `checklists` is keyed by that same mapped symbol (from the `checklist-<SYMBOL>` files).
  public static func items(
    from stocks: [LegacyStock],
    checklists: [String: [ChecklistItem]],
    template: [ChecklistItem],
    now: Date
  ) -> [WatchlistItem] {
    var seen = Set<String>()
    var result: [WatchlistItem] = []
    for stock in stocks {
      let key = mappedSymbol(stock.symbol)
      guard !seen.contains(key) else {
        continue
      }
      guard let item = WatchlistItem(legacy: stock, index: result.count, checklist: checklists[key] ?? template, now: now) else {
        continue
      }
      seen.insert(key)
      result.append(item)
    }
    return result
  }

  /// The symbol a legacy row maps to: trimmed and upper-cased. Use it for dedupe and checklist lookups.
  public static func mappedSymbol(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespaces).uppercased()
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh DomainTests`
Expected PASS: `** TEST SUCCEEDED **`. All Domain suites pass.

- [ ] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Domain/Legacy Wait/Packages/WaitKit/Tests/DomainTests
git commit -m "feat(domain): decode legacy Money-based stocks and map to WatchlistItem

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 4: Logging and Persistence

### Task 8: `Log` channels on `os.Logger`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Logging/Log.swift`
- Create: `Wait/Packages/WaitKit/Tests/LoggingTests/LogTests.swift`
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `LoggingTests` test target, and make sure the `Logging` product exists)

`LegacyLogger.swift` from plan 01 stays until the cutover (Task 29). Legacy code keeps calling `Logger.shared`, and new code uses `Log.<channel>`.

- [ ] **Step 1: Update `Package.swift`**
  - Add `.testTarget(name: "LoggingTests", dependencies: ["Logging"]),` to `targets:`.
  - If `products:` has no `Logging` library, add `.library(name: "Logging", targets: ["Logging"]),`.

- [ ] **Step 2: Write the failing test**

`Wait/Packages/WaitKit/Tests/LoggingTests/LogTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Logging
import Testing

@Suite struct LogTests {
  @Test func channelsShareTheSubsystem() {
    #expect(Log.subsystem == "com.chenkai.wait")
    #expect(Log.network.category == "network")
    #expect(Log.persistence.category == "persistence")
    #expect(Log.app.category == "app")
    Log.app.debug("LogTests smoke message")
  }
}
```

- [ ] **Step 3: Run the test and confirm it fails**

Run: `scripts/test-waitkit.sh LoggingTests`
Expected FAIL: `error: cannot find 'Log' in scope`.

- [ ] **Step 4: Implement.** The legacy shim in this module may define its own `Logger` type, so always write `os.Logger` with its module prefix.

`Wait/Packages/WaitKit/Sources/Logging/Log.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import os

// MARK: - LogChannel

/// A unified-logging category. Messages are logged with `.public` privacy, because this is a personal app and logs never leave the device.
public struct LogChannel: Sendable {
  // MARK: Lifecycle

  public init(category: String) {
    self.category = category
    logger = os.Logger(subsystem: Log.subsystem, category: category)
  }

  // MARK: Public

  public let category: String

  public func debug(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }

  public func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
  }

  public func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }

  // MARK: Private

  private let logger: os.Logger
}

// MARK: - Log

public enum Log {
  public static let subsystem = "com.chenkai.wait"

  public static let app = LogChannel(category: "app")
  public static let network = LogChannel(category: "network")
  public static let persistence = LogChannel(category: "persistence")
  public static let ui = LogChannel(category: "ui")
  public static let sync = LogChannel(category: "sync")
  public static let push = LogChannel(category: "push")
  public static let connectivity = LogChannel(category: "connectivity")
}
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `scripts/test-waitkit.sh LoggingTests`
Expected PASS: 1 test passes.

- [ ] **Step 6: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Logging/Log.swift Wait/Packages/WaitKit/Tests/LoggingTests
git commit -m "feat(logging): os.Logger channels for new targets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: App-group entitlements and `AppGroup`

**Files:**
- Modify: `Wait/Wait/Wait.entitlements` (Debug: add the app group)
- Create: `Wait/WaitWidget/WaitWidget.entitlements`
- Delete: `Wait/WaitWidgetExtensionRelease.entitlements`
- Modify: `Wait/project.yml` (entitlement paths)
- Modify: `Wait/Packages/WaitKit/Package.swift` (add package dependencies, the `Persistence` target and product, and `PersistenceTests`)
- Create: `Wait/Packages/WaitKit/Sources/Persistence/AppGroup.swift`
- Create: `Wait/Packages/WaitKit/Tests/PersistenceTests/AppGroupTests.swift`

- [ ] **Step 1: Entitlements.** Replace `Wait/Wait/Wait.entitlements` with this. It keeps the existing push and iCloud keys and adds the group.
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.chenkai.wait</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.chenkai.wait.contents</string>
	</array>
</dict>
</plist>
```
Leave `Wait/Wait/WaitRelease.entitlements` as it is; it already has the group. Create `Wait/WaitWidget/WaitWidget.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.chenkai.wait.contents</string>
	</array>
</dict>
</plist>
```
Run: `git rm Wait/WaitWidgetExtensionRelease.entitlements`

- [ ] **Step 2: Update `project.yml`.**
  - In **both** the `Wait` and `WaitWidgetExtension` targets, delete any `entitlements:` key. With that key, XcodeGen would regenerate the plist from YAML properties.
  - Delete any existing `CODE_SIGN_ENTITLEMENTS` lines.
  - Set the entitlements paths exactly as follows:
```yaml
  Wait:
    # …existing keys unchanged…
    settings:
      configs:
        Debug:
          CODE_SIGN_ENTITLEMENTS: Wait/Wait.entitlements
        Release:
          CODE_SIGN_ENTITLEMENTS: Wait/WaitRelease.entitlements
  WaitWidgetExtension:
    # …existing keys unchanged…
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: WaitWidget/WaitWidget.entitlements
```
  Merge these into the existing `settings:` blocks; don't create duplicate `settings:` keys. Then regenerate and check:

Run: `cd "$(git rev-parse --show-toplevel)/Wait" && xcodegen generate && xcodebuild -project Wait.xcodeproj -target WaitWidgetExtension -configuration Debug -showBuildSettings 2>/dev/null | grep CODE_SIGN_ENTITLEMENTS`
Expected: `CODE_SIGN_ENTITLEMENTS = WaitWidget/WaitWidget.entitlements`

Run: `R="$(git rev-parse --show-toplevel)"; test -f "$R/Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" && echo "Package.resolved present"; git -C "$R" status --short Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
Expected: `Package.resolved present`. The `git status` line may show ` M` once new packages resolve, but never ` D`, which would mean regeneration deleted the file (overview risk 21).

- [ ] **Step 3: Add the package dependencies and the `Persistence` target to `Package.swift`**
  - Append to `dependencies:`:
    ```swift
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
    ```
  - Append to `products:`: `.library(name: "Persistence", targets: ["Persistence"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "Persistence",
      dependencies: [
        "Domain",
        "Logging",
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "PersistenceTests",
      dependencies: [
        "Persistence",
        "Domain",
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```

  - Create `Wait/Packages/WaitKit/Sources/Persistence/AppGroup.swift` containing only the file header, so the package loads. Step 6 fills it in.

- [ ] **Step 4: Write the failing test**

`Wait/Packages/WaitKit/Tests/PersistenceTests/AppGroupTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Persistence
import Testing

@Suite struct AppGroupTests {
  @Test func identifierMatchesEntitlements() {
    #expect(AppGroup.identifier == "group.chenkai.wait.contents")
  }

  @Test func fallsBackToDocumentsWhenTheGroupIsUnavailable() {
    let url = AppGroup.containerURL(groupContainer: { _ in nil })
    #expect(url == URL.documentsDirectory)
  }

  @Test func usesTheGroupContainerWhenAvailable() {
    let group = URL(fileURLWithPath: "/tmp/group-container")
    #expect(AppGroup.containerURL(groupContainer: { _ in group }) == group)
  }

  @Test func fileNames() {
    #expect(AppGroup.fileURL(AppGroup.watchlistFileName).lastPathComponent == "watchlist.json")
    #expect(AppGroup.checklistTemplateFileName == "checklist-template.json")
    #expect(AppGroup.snapshotFileName == "snapshot.json")
    #expect(AppGroup.migrationMarkerFileName == "migration-v1.done")
  }
}
```

- [ ] **Step 5: Run the test and confirm it fails**

Run: `scripts/test-waitkit.sh PersistenceTests`
Expected FAIL: `error: cannot find 'AppGroup' in scope`.

- [ ] **Step 6: Replace the contents of `AppGroup.swift` with the implementation**

`Wait/Packages/WaitKit/Sources/Persistence/AppGroup.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - AppGroup

/// Files shared by the app and the widget (overview §9).
public enum AppGroup {
  // MARK: Public

  public static let identifier = "group.chenkai.wait.contents"

  public static let watchlistFileName = "watchlist.json"
  public static let checklistTemplateFileName = "checklist-template.json"
  public static let snapshotFileName = "snapshot.json"
  public static let migrationMarkerFileName = "migration-v1.done"

  /// The group container, or the app's Documents when the entitlement is missing (package tests, unsigned builds).
  public static func containerURL(
    groupContainer: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
  ) -> URL {
    groupContainer(identifier) ?? URL.documentsDirectory
  }

  public static func fileURL(_ name: String) -> URL {
    containerURL().appending(path: name)
  }
}
```

- [ ] **Step 7: Run the tests and confirm they pass, then build the app**

Run: `scripts/test-waitkit.sh PersistenceTests && scripts/build-app.sh`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**
```bash
git add Wait/project.yml Wait/Wait.xcodeproj Wait/Wait/Wait.entitlements Wait/WaitWidget/WaitWidget.entitlements Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Persistence Wait/Packages/WaitKit/Tests/PersistenceTests
git commit -m "feat(persistence): app group entitlements for app and widget, AppGroup paths

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: `@Shared` keys and watchlist mutation helpers

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Persistence/SharedKeys.swift`, `Wait/Packages/WaitKit/Sources/Persistence/Shared+Watchlist.swift`
- Create: `Wait/Packages/WaitKit/Tests/PersistenceTests/SharedWatchlistTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/PersistenceTests/SharedWatchlistTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DependenciesTestSupport
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
import Testing

@Suite struct SharedWatchlistTests {
  let t0 = Date(timeIntervalSince1970: 1_795_186_800)
  let later = Date(timeIntervalSince1970: 1_795_186_860.123_9)

  func item(_ symbol: String, _ sortIndex: Int, favorite: Bool = false) -> WatchlistItem {
    WatchlistItem(symbol: symbol, name: symbol, isFavorite: favorite, sortIndex: sortIndex, createdAt: t0, updatedAt: t0)
  }

  @Test func updateStampsMillisecondTruncatedNow() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0)]))
    items.update("AAPL", now: later) { $0.memo = "note" }
    #expect(items.wrappedValue[id: "AAPL"]?.memo == "note")
    #expect(items.wrappedValue[id: "AAPL"]?.updatedAt.millisecondsSince1970 == 1_795_186_860_123)
    #expect(items.wrappedValue[id: "AAPL"]?.updatedAt == later.truncatedToMilliseconds)
  }

  @Test func updateOfUnknownSymbolIsANoop() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0)]))
    items.update("MSFT", now: later) { $0.memo = "x" }
    #expect(items.wrappedValue.map(\.updatedAt) == [t0])
  }

  @Test func addAppendsWithNextSortIndexAndRejectsDuplicates() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 4)]))
    #expect(items.add(item("MSFT", 0), now: later))
    #expect(items.wrappedValue[id: "MSFT"]?.sortIndex == 5)
    #expect(items.wrappedValue[id: "MSFT"]?.updatedAt == later.truncatedToMilliseconds)
    #expect(!items.add(item("AAPL", 0), now: later))
    #expect(items.wrappedValue.count == 2)
  }

  @Test func removeDeletes() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0), item("MSFT", 1)]))
    items.remove("AAPL", now: later)
    #expect(items.wrappedValue.ids == ["MSFT"])
  }

  @Test func reorderReusesTheSectionSlotsAndTouchesOnlyMovedItems() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [
      item("A", 0), item("B", 1), item("C", 2), item("F", 3, favorite: true), item("D", 4),
    ]))
    // Others in order A, B, C, D. Move B (offset 1) to before D (offset 3), giving A, C, B, D.
    items.reorder(section: .others, from: IndexSet(integer: 1), to: 3, now: later)
    let value = items.wrappedValue
    #expect(value[id: "A"]?.sortIndex == 0)
    #expect(value[id: "C"]?.sortIndex == 1)
    #expect(value[id: "B"]?.sortIndex == 2)
    #expect(value[id: "D"]?.sortIndex == 4)
    #expect(value[id: "F"]?.sortIndex == 3)
    #expect(value[id: "A"]?.updatedAt == t0)
    #expect(value[id: "D"]?.updatedAt == t0)
    #expect(value[id: "F"]?.updatedAt == t0)
    #expect(value[id: "B"]?.updatedAt == later.truncatedToMilliseconds)
    #expect(value[id: "C"]?.updatedAt == later.truncatedToMilliseconds)
  }

  @Test func sharedItemUpdate() {
    let one = Shared(value: item("AAPL", 0))
    one.update(now: later) { $0.isFavorite = true }
    #expect(one.wrappedValue.isFavorite)
    #expect(one.wrappedValue.updatedAt == later.truncatedToMilliseconds)
  }

  @Test(.dependencies { $0.defaultFileStorage = .inMemory })
  func keysHaveDefaults() {
    @Shared(.watchlist) var watchlist
    @SharedReader(.checklistTemplate) var template
    #expect(watchlist.isEmpty)
    #expect(Array(template) == ChecklistTemplate.defaultItems)
  }
}
```
The `.dependencies` trait comes from `DependenciesTestSupport`, which is imported at the top of the file. It gives each test its own in-memory file storage.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh PersistenceTests/SharedWatchlistTests`
Expected FAIL: `error: value of type 'Shared<IdentifiedArray<String, WatchlistItem>>' has no member 'update'` and `type 'SharedReaderKey' has no member 'watchlist'`.

- [ ] **Step 3: Implement `SharedKeys.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Sharing

// Keys are declared on `SharedReaderKey`, as swift-sharing recommends. That makes them resolve for both `@Shared(.x)` and
// `@SharedReader(.x)`, because `SharedKey` refines `SharedReaderKey`. Declaring twins on `SharedKey` as well would make
// `@Shared(.watchlist)` ambiguous. Plan 05's `.syncState` follows the same pattern.

/// `@Shared(.watchlist)` lives in the app group, so the widget extension can read the same file.
public extension SharedReaderKey where Self == FileStorageKey<IdentifiedArrayOf<WatchlistItem>>.Default {
  static var watchlist: Self {
    Self[.fileStorage(AppGroup.fileURL(AppGroup.watchlistFileName)), default: []]
  }
}

/// `@Shared(.checklistTemplate)`: the prompts that seed every newly added stock.
public extension SharedReaderKey where Self == FileStorageKey<IdentifiedArrayOf<ChecklistItem>>.Default {
  static var checklistTemplate: Self {
    Self[
      .fileStorage(AppGroup.fileURL(AppGroup.checklistTemplateFileName)),
      default: IdentifiedArray(uniqueElements: ChecklistTemplate.defaultItems)
    ]
  }
}
```

- [ ] **Step 4: Implement `Shared+Watchlist.swift`.** These are the only mutation paths, and every one of them stamps `updatedAt` truncated to milliseconds. Plan 05 changes the bodies of `add` and `remove` to keep tombstones, but leaves their signatures alone.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Sharing

// MARK: - WatchlistSection

public enum WatchlistSection: Hashable, Sendable {
  case favorites
  case others
}

public extension Shared where Value == IdentifiedArrayOf<WatchlistItem> {
  func update(_ symbol: String, now: Date, _ body: (inout WatchlistItem) -> Void) {
    withLock { items in
      guard var item = items[id: symbol] else {
        return
      }
      body(&item)
      item.updatedAt = now.truncatedToMilliseconds
      items[id: symbol] = item
    }
  }

  /// Appends at the end of the list (`max(sortIndex) + 1`). Returns false if the symbol is already present.
  @discardableResult
  func add(_ item: WatchlistItem, now: Date) -> Bool {
    withLock { items in
      guard items[id: item.symbol] == nil else {
        return false
      }
      var item = item
      item.sortIndex = (items.map(\.sortIndex).max() ?? -1) + 1
      item.updatedAt = now.truncatedToMilliseconds
      items.append(item)
      return true
    }
  }

  func remove(_ symbol: String, now: Date) {
    _ = now // Plan 05 records a tombstone at `now`.
    withLock { items in
      _ = items.remove(id: symbol)
    }
  }

  /// SwiftUI `onMove` semantics inside one section. The section's existing `sortIndex` slots are reused, so the other section is untouched.
  func reorder(section: WatchlistSection, from source: IndexSet, to destination: Int, now: Date) {
    withLock { items in
      let sectionItems = items
        .filter { section == .favorites ? $0.isFavorite : !$0.isFavorite }
        .sorted { $0.sortIndex < $1.sortIndex }
      let slots = sectionItems.map(\.sortIndex)
      let moving = source.sorted().map { sectionItems[$0] }
      var reordered = sectionItems.enumerated().filter { !source.contains($0.offset) }.map(\.element)
      let insertAt = destination - source.filter { $0 < destination }.count
      reordered.insert(contentsOf: moving, at: max(0, min(insertAt, reordered.count)))
      let stamp = now.truncatedToMilliseconds
      for (slot, item) in zip(slots, reordered) where item.sortIndex != slot {
        items[id: item.symbol]?.sortIndex = slot
        items[id: item.symbol]?.updatedAt = stamp
      }
    }
  }
}

public extension Shared where Value == WatchlistItem {
  /// For features holding a single derived `Shared<WatchlistItem>`, such as details or checklist.
  func update(now: Date, _ body: (inout WatchlistItem) -> Void) {
    withLock { item in
      body(&item)
      item.updatedAt = now.truncatedToMilliseconds
    }
  }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh PersistenceTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Persistence Wait/Packages/WaitKit/Tests/PersistenceTests
git commit -m "feat(persistence): shared watchlist and template keys with stamped mutation helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: `SnapshotStore` and `SnapshotClient`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Persistence/SnapshotStore.swift`, `Wait/Packages/WaitKit/Sources/Persistence/SnapshotClient.swift`
- Create: `Wait/Packages/WaitKit/Tests/PersistenceTests/SnapshotStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/PersistenceTests/SnapshotStoreTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Persistence
import Testing

@Suite struct SnapshotStoreTests {
  func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString)/snapshot.json")
  }

  @Test func saveThenLoadRoundTrips() throws {
    let store = SnapshotStore.live(url: tempURL())
    let snapshot = WatchlistSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1_795_186_800),
      quotesAsOf: nil,
      rows: [.init(symbol: "AAPL", name: "Apple", price: Decimal(string: "189.98"), changePercent: 1.2, status: .watch, temperature: 45, ladder: .empty, isFavorite: true)]
    )
    try store.save(snapshot)
    #expect(store.load() == snapshot)
  }

  @Test func missingOrCorruptFileLoadsNil() throws {
    let url = tempURL()
    #expect(SnapshotStore.live(url: url).load() == nil)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(SnapshotStore.live(url: url).load() == nil)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh PersistenceTests/SnapshotStoreTests`
Expected FAIL: `error: cannot find 'SnapshotStore' in scope`.

- [ ] **Step 3: Implement `SnapshotStore.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotStore

/// Reads and writes `snapshot.json` atomically. The widget reads it; the app writes it through `SnapshotClient`.
public struct SnapshotStore: Sendable {
  // MARK: Lifecycle

  public init(load: @escaping @Sendable () -> WatchlistSnapshot?, save: @escaping @Sendable (WatchlistSnapshot) throws -> Void) {
    self.load = load
    self.save = save
  }

  // MARK: Public

  public var load: @Sendable () -> WatchlistSnapshot?
  public var save: @Sendable (WatchlistSnapshot) throws -> Void

  public static var appGroup: SnapshotStore {
    .live(url: AppGroup.fileURL(AppGroup.snapshotFileName))
  }

  public static func live(url: URL) -> SnapshotStore {
    SnapshotStore(
      load: {
        guard let data = try? Data(contentsOf: url) else {
          return nil
        }
        return try? JSONDecoder().decode(WatchlistSnapshot.self, from: data)
      },
      save: { snapshot in
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      }
    )
  }
}
```

- [ ] **Step 4: Implement `SnapshotClient.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation
import Logging
#if canImport(WidgetKit)
  import WidgetKit
#endif

// MARK: - SnapshotClient

/// Publishes the watchlist snapshot: it saves `snapshot.json` and reloads the widgets. Plan 03 also sends it to the watch, from `AppFeature`.
@DependencyClient
public struct SnapshotClient: Sendable {
  public var publish: @Sendable (_ snapshot: WatchlistSnapshot) async -> Void
}

// MARK: DependencyKey

extension SnapshotClient: DependencyKey {
  public static let liveValue = SnapshotClient(
    publish: { snapshot in
      do {
        try SnapshotStore.appGroup.save(snapshot)
      } catch {
        Log.persistence.error("Snapshot save failed: \(error)")
      }
      #if canImport(WidgetKit)
        await MainActor.run {
          WidgetCenter.shared.reloadAllTimelines()
        }
      #endif
    }
  )

  public static let testValue = SnapshotClient()
  public static let previewValue = SnapshotClient(publish: { _ in })
}

public extension DependencyValues {
  var snapshotClient: SnapshotClient {
    get { self[SnapshotClient.self] }
    set { self[SnapshotClient.self] = newValue }
  }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh PersistenceTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Persistence Wait/Packages/WaitKit/Tests/PersistenceTests
git commit -m "feat(persistence): snapshot store and snapshot client dependency

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: `LegacyMigration`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Persistence/LegacyMigration.swift`
- Create: `Wait/Packages/WaitKit/Tests/PersistenceTests/LegacyMigrationTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/PersistenceTests/LegacyMigrationTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Persistence
import Testing

@Suite struct LegacyMigrationTests {
  let now = Date(timeIntervalSince1970: 1_795_186_800)
  // Two malformed rows (a number, and an object without "symbol") must be skipped, not fail the migration.
  let legacyStocks = #"""
  [
    {"symbol":"AAPL","name":"Apple","expectedPrice":{"amount":150,"currencyCode":"USD"},"memo":"keep","expectedPriceHistory":[]},
    42,
    {"name":"no symbol"},
    {"symbol":"Empty","name":"Empty","expectedPrice":{"amount":0,"currencyCode":"USD"},"memo":"","expectedPriceHistory":[]},
    {"symbol":"MSFT","name":"Microsoft","expectedPrice":{"amount":300.5,"currencyCode":"USD"},"memo":"","expectedPriceHistory":[]}
  ]
  """#
  let aaplChecklist = #"[{"name":"Custom","isChecked":true,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}]"#
  let template = #"[{"name":"T1","isChecked":false,"id":"00000000-0000-0000-0000-0000000000AA"}]"#

  func dirs() throws -> (documents: URL, group: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
    let documents = root.appending(path: "Documents")
    let group = root.appending(path: "Group")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    return (documents, group)
  }

  func decodeWatchlist(_ group: URL) throws -> [WatchlistItem] {
    try JSONDecoder().decode([WatchlistItem].self, from: Data(contentsOf: group.appending(path: "watchlist.json")))
  }

  func markerExists(_ group: URL) -> Bool {
    FileManager.default.fileExists(atPath: group.appending(path: "migration-v1.done").path)
  }

  @Test func migratesStocksChecklistsAndTemplateSkippingMalformedRows() throws {
    let (documents, group) = try dirs()
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    try Data(aaplChecklist.utf8).write(to: documents.appending(path: "checklist-AAPL"))
    try Data(template.utf8).write(to: documents.appending(path: "checklist-items.json"))

    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)

    #expect(report == MigrationReport(didRun: true, migratedItems: 2, migratedTemplate: true))
    let items = try decodeWatchlist(group)
    #expect(items.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(items[0].memo == "keep")
    #expect(items[0].checklist.map(\.name) == ["Custom"])
    #expect(items[1].checklist.map(\.name) == ["T1"])
    #expect(items[1].ladder.buyHigh == Decimal(string: "300.5"))
    #expect(FileManager.default.fileExists(atPath: group.appending(path: "checklist-template.json").path))
    #expect(markerExists(group))
    #expect(FileManager.default.fileExists(atPath: documents.appending(path: "stocks").path)) // old files are kept
  }

  @Test func secondRunIsANoop() throws {
    let (documents, group) = try dirs()
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let migration = LegacyMigration(documents: documents, destination: group)
    _ = try migration.runIfNeeded(now: now)
    try Data("[]".utf8).write(to: documents.appending(path: "stocks"))
    let second = try migration.runIfNeeded(now: now)
    #expect(second == MigrationReport(didRun: false, migratedItems: 0, migratedTemplate: false))
    #expect(try decodeWatchlist(group).count == 2)
  }

  @Test func freshInstallWritesOnlyTheMarker() throws {
    let (documents, group) = try dirs()
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report == MigrationReport(didRun: true, migratedItems: 0, migratedTemplate: false))
    #expect(!FileManager.default.fileExists(atPath: group.appending(path: "watchlist.json").path))
    #expect(markerExists(group))
  }

  @Test func neverOverwritesANonEmptyWatchlist() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data(#"[{"symbol":"KEEP"}]"#.utf8).write(to: group.appending(path: "watchlist.json"))
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report.migratedItems == 0)
    #expect(try decodeWatchlist(group).map(\.symbol) == ["KEEP"])
  }

  @Test func anEmptyWatchlistFileCountsAsAbsent() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: group.appending(path: "watchlist.json"))
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report.migratedItems == 2)
    #expect(try decodeWatchlist(group).map(\.symbol) == ["AAPL", "MSFT"])
  }

  @Test func unreadableStocksThrowsAndLeavesNoMarker() throws {
    let (documents, group) = try dirs()
    // A directory named "stocks" exists but can't be read as data: not "missing", so the migration must retry later.
    try FileManager.default.createDirectory(at: documents.appending(path: "stocks"), withIntermediateDirectories: true)
    #expect(throws: (any Error).self) {
      try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    }
    #expect(!markerExists(group))
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh PersistenceTests/LegacyMigrationTests`
Expected FAIL: `error: cannot find 'LegacyMigration' in scope`.

- [ ] **Step 3: Implement**

`Wait/Packages/WaitKit/Sources/Persistence/LegacyMigration.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Logging

// MARK: - MigrationReport

public struct MigrationReport: Equatable, Sendable {
  public init(didRun: Bool, migratedItems: Int, migratedTemplate: Bool) {
    self.didRun = didRun
    self.migratedItems = migratedItems
    self.migratedTemplate = migratedTemplate
  }

  public var didRun: Bool
  public var migratedItems: Int
  public var migratedTemplate: Bool
}

// MARK: - LegacyMigration

/// One-time move of the legacy Documents files into the app group (overview §7.6).
/// - Inputs: `stocks`, `checklist-<SYMBOL>` and `checklist-items.json`.
/// - Outputs: `watchlist.json` and `checklist-template.json`, plus the `migration-v1.done` marker.
/// - Old files are kept.
/// - A destination watchlist that already has items is never overwritten. A missing, zero-byte or `[]` watchlist counts as absent.
/// - Malformed `stocks` rows are skipped and logged.
/// - If `stocks` exists but can't be read or isn't a JSON array, this throws without writing the marker, so the migration retries on the next launch.
public struct LegacyMigration: Sendable {
  // MARK: Lifecycle

  public init(documents: URL, destination: URL) {
    self.documents = documents
    self.destination = destination
  }

  // MARK: Public

  public static var live: LegacyMigration {
    LegacyMigration(documents: URL.documentsDirectory, destination: AppGroup.containerURL())
  }

  public let documents: URL
  public let destination: URL

  public func runIfNeeded(now: Date) throws -> MigrationReport {
    let fileManager = FileManager.default
    let marker = destination.appending(path: AppGroup.migrationMarkerFileName)
    guard !fileManager.fileExists(atPath: marker.path) else {
      return MigrationReport(didRun: false, migratedItems: 0, migratedTemplate: false)
    }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

    let decoder = JSONDecoder() // legacy files use the default `deferredToDate` strategy
    let encoder = JSONEncoder() // matches swift-sharing's default FileStorageKey coding
    var report = MigrationReport(didRun: true, migratedItems: 0, migratedTemplate: false)

    // The template and per-stock checklists are best-effort: an unreadable file falls back to the defaults.
    var template = ChecklistTemplate.defaultItems
    let templateURL = destination.appending(path: AppGroup.checklistTemplateFileName)
    if
      let data = try? Self.readIfPresent(documents.appending(path: "checklist-items.json")),
      let legacyTemplate = try? decoder.decode([ChecklistItem].self, from: data),
      !legacyTemplate.isEmpty
    {
      template = Self.uniqueByID(legacyTemplate)
      if !fileManager.fileExists(atPath: templateURL.path) {
        try encoder.encode(template).write(to: templateURL, options: .atomic)
        report.migratedTemplate = true
      }
    }

    let watchlistURL = destination.appending(path: AppGroup.watchlistFileName)
    if try Self.isAbsentOrEmpty(watchlistURL), let data = try Self.readIfPresent(documents.appending(path: "stocks")) {
      let rows = try decoder.decode([LossyLegacyStock].self, from: data)
      let stocks = rows.compactMap(\.stock)
      if stocks.count < rows.count {
        Log.persistence.error("Legacy migration skipped \(rows.count - stocks.count) malformed stock rows")
      }
      var checklists: [String: [ChecklistItem]] = [:]
      for stock in stocks {
        let url = documents.appending(path: "checklist-\(stock.symbol)")
        if let data = try? Self.readIfPresent(url), let items = try? decoder.decode([ChecklistItem].self, from: data) {
          checklists[LegacyStockMapper.mappedSymbol(stock.symbol)] = Self.uniqueByID(items)
        }
      }
      let items = LegacyStockMapper.items(from: stocks, checklists: checklists, template: template, now: now)
      try encoder.encode(items).write(to: watchlistURL, options: .atomic)
      report.migratedItems = items.count
    }

    try Data().write(to: marker, options: .atomic)
    return report
  }

  // MARK: Private

  /// Decodes one row, or nil for a malformed row, without failing the whole array.
  private struct LossyLegacyStock: Decodable {
    let stock: LegacyStock?

    init(from decoder: any Decoder) throws {
      stock = try? LegacyStock(from: decoder)
    }
  }

  /// Returns nil only when the file doesn't exist. Any other read error is rethrown.
  private static func readIfPresent(_ url: URL) throws -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
  }

  private static func isAbsentOrEmpty(_ url: URL) throws -> Bool {
    guard let data = try readIfPresent(url), !data.isEmpty else {
      return true
    }
    return (try? JSONSerialization.jsonObject(with: data) as? [Any])?.isEmpty == true
  }

  private static func uniqueByID(_ items: [ChecklistItem]) -> [ChecklistItem] {
    var seen = Set<UUID>()
    return items.filter { seen.insert($0.id).inserted }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh PersistenceTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/Persistence/LegacyMigration.swift Wait/Packages/WaitKit/Tests/PersistenceTests/LegacyMigrationTests.swift
git commit -m "feat(persistence): one-time legacy Documents to app group migration

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 5: MarketDataClient — interface, TTL and disk cache

### Task 13: `MarketDataClient` interface, errors and cache policy

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `MarketDataClient` target and product, and `MarketDataClientTests`)
- Create: `Wait/Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift`, `MarketDataError.swift`, `CachePolicy.swift`
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/MarketDataErrorTests.swift`, `Wait/Packages/WaitKit/Tests/MarketDataClientTests/TestSupport.swift`

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "MarketDataClient", targets: ["MarketDataClient"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "MarketDataClient",
      dependencies: [
        "Domain",
        "Logging",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "MarketDataClientTests",
      dependencies: [
        "MarketDataClient",
        "Domain",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift` containing only the file header, so the package loads. Step 6 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/TestSupport.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import MarketDataClient

/// `2026-11-20T15:00:00Z`, a Friday at 10:00 ET when the market is open.
let fridayOpen = Date(timeIntervalSince1970: 1_795_186_800)

func dec(_ string: String) -> Decimal {
  Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

// MARK: - MutableNow

final class MutableNow: @unchecked Sendable {
  // MARK: Lifecycle

  init(_ date: Date) {
    value = date
  }

  // MARK: Internal

  var date: Date {
    lock.withLock { value }
  }

  func advance(_ seconds: TimeInterval) {
    lock.withLock { value += seconds }
  }

  // MARK: Private

  private let lock = NSLock()
  private var value: Date
}

// MARK: - FakeUpstream

/// A scripted upstream `MarketDataClient` that records every call.
final class FakeUpstream: @unchecked Sendable {
  // MARK: Lifecycle

  /// `batchLimit` imitates a free tier: a request for more symbols returns the first `batchLimit` quotes in a `PartialQuotesError`.
  init(delay: Duration = .zero, batchLimit: Int? = nil) {
    self.delay = delay
    self.batchLimit = batchLimit
  }

  // MARK: Internal

  let delay: Duration
  let batchLimit: Int?

  var quoteCalls: [[String]] {
    lock.withLock { recordedQuoteCalls }
  }

  var seriesCalls: Int {
    lock.withLock { recordedSeriesCalls }
  }

  var client: MarketDataClient {
    MarketDataClient(
      quotes: { symbols, _ in
        let error = self.lock.withLock {
          self.recordedQuoteCalls.append(symbols)
          return self.scriptedError
        }
        if self.delay > .zero {
          try await Task.sleep(for: self.delay)
        }
        if let error {
          throw error
        }
        if let limit = self.batchLimit, symbols.count > limit {
          throw PartialQuotesError(quotes: symbols.prefix(limit).map { Quote(symbol: $0, price: 100, asOf: fridayOpen) }, retryAfter: .seconds(60))
        }
        return symbols.map { Quote(symbol: $0, price: 100, asOf: fridayOpen) }
      },
      series: { symbol, range, _ in
        let error = self.lock.withLock {
          self.recordedSeriesCalls += 1
          return self.scriptedError
        }
        if self.delay > .zero {
          try await Task.sleep(for: self.delay)
        }
        if let error {
          throw error
        }
        return PriceSeries(symbol: symbol, range: range, points: [PricePoint(date: fridayOpen, close: 1)], asOf: fridayOpen)
      },
      search: { _ in [] },
      profile: { symbol in CompanyProfile(symbol: symbol, asOf: fridayOpen) }
    )
  }

  func fail(with error: MarketDataError?) {
    lock.withLock { scriptedError = error }
  }

  // MARK: Private

  private let lock = NSLock()
  private var recordedQuoteCalls: [[String]] = []
  private var recordedSeriesCalls = 0
  private var scriptedError: MarketDataError?
}
```

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/MarketDataErrorTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Domain
import Foundation
import MarketDataClient
import Testing

@Suite struct MarketDataErrorTests {
  @Test func mapsArbitraryErrors() throws {
    #expect(try MarketDataError(MarketDataError.notFound) == .notFound)
    if case .network = try MarketDataError(URLError(.notConnectedToInternet)) {} else {
      Issue.record("URLError should map to .network")
    }
    let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
    if case .decoding = try MarketDataError(decoding) {} else {
      Issue.record("DecodingError should map to .decoding")
    }
    #expect(try MarketDataError(PartialQuotesError(quotes: [], retryAfter: .seconds(30))) == .rateLimited(retryAfter: .seconds(30)))
  }

  @Test func cancellationIsRethrownNotWrapped() {
    #expect(throws: CancellationError.self) { try MarketDataError(CancellationError()) }
    #expect(throws: CancellationError.self) { try MarketDataError(URLError(.cancelled)) }
  }

  @Test func userMessages() {
    #expect(MarketDataError.rateLimited(retryAfter: .seconds(60)).userMessage == "Quotes delayed — rate limited")
    #expect(MarketDataError.notCached.userMessage == "No cached data yet")
  }

  @Test func dependencyCanBeOverridden() async throws {
    let quotes = try await withDependencies {
      $0.marketData.quotes = { symbols, _ in symbols.map { Quote(symbol: $0, price: 1, asOf: fridayOpen) } }
    } operation: {
      @Dependency(\.marketData) var marketData
      return try await marketData.quotes(["AAPL"], .useCache)
    }
    #expect(quotes.map(\.symbol) == ["AAPL"])
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests`
Expected FAIL: `error: cannot find type 'MarketDataClient' in scope` and `cannot find 'MarketDataError' in scope`.

- [ ] **Step 4: Implement `CachePolicy.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - CachePolicy

/// How a call may use `CachingMarketDataClient` (overview §6.3).
public enum CachePolicy: Equatable, Sendable {
  /// Return fresh cache. Otherwise fetch, falling back to a stale entry (≤ 7 days old) on failure.
  case useCache
  /// Always fetch, with the same stale fallback.
  case reload
  /// Return any cached entry, or throw `.notCached`. Never touches the network.
  case cacheOnly
}
```

- [ ] **Step 5: Implement `MarketDataError.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - PartialQuotesError

/// An upstream `quotes` call got some quotes before it was rate limited. `CachingMarketDataClient` keeps the quotes and still starts the cooldown.
public struct PartialQuotesError: Error, Sendable {
  public init(quotes: [Quote], retryAfter: Duration?) {
    self.quotes = quotes
    self.retryAfter = retryAfter
  }

  public let quotes: [Quote]
  public let retryAfter: Duration?
}

// MARK: - MarketDataError

public enum MarketDataError: Error, Equatable, Sendable {
  case rateLimited(retryAfter: Duration?)
  case notFound
  case notCached
  case network(String)
  case decoding(String)
  case unavailable

  // MARK: Lifecycle

  /// Maps any error. Cancellation is never wrapped: `CancellationError` and `URLError(.cancelled)` are rethrown as `CancellationError`,
  /// so a cancelled effect or fetch stays cancelled instead of showing up as a failure. Call it as `try MarketDataError(error)`.
  public init(_ error: any Error) throws(CancellationError) {
    switch error {
      case is CancellationError:
        throw CancellationError()
      case let error as URLError where error.code == .cancelled:
        throw CancellationError()
      case let error as MarketDataError:
        self = error
      case let error as PartialQuotesError:
        self = .rateLimited(retryAfter: error.retryAfter)
      case is DecodingError:
        self = .decoding(String(describing: error))
      case let error as URLError:
        self = .network(error.localizedDescription)
      default:
        self = .network(error.localizedDescription)
    }
  }

  // MARK: Public

  public var userMessage: String {
    switch self {
      case .rateLimited: "Quotes delayed — rate limited"
      case .notFound: "Symbol not found"
      case .notCached: "No cached data yet"
      case .network: "Couldn't reach the data provider"
      case .decoding: "Unexpected data from the provider"
      case .unavailable: "Not available yet"
    }
  }
}
```

- [ ] **Step 6: Replace the contents of `MarketDataClient.swift` with the implementation.** Task 17 adds `liveValue`. Until then the client is a `TestDependencyKey`, and no app code uses it.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation

// MARK: - MarketDataClient

/// Everything the app needs from market data. Inject it through `@Dependency(\.marketData)`.
@DependencyClient
public struct MarketDataClient: Sendable {
  public var quotes: @Sendable (_ symbols: [String], _ policy: CachePolicy) async throws -> [Quote]
  public var series: @Sendable (_ symbol: String, _ range: ChartRange, _ policy: CachePolicy) async throws -> PriceSeries
  public var search: @Sendable (_ query: String) async throws -> [SymbolSearchResult]
  public var profile: @Sendable (_ symbol: String) async throws -> CompanyProfile
}

// MARK: TestDependencyKey

extension MarketDataClient: TestDependencyKey {
  public static let testValue = MarketDataClient()

  public static let previewValue = MarketDataClient(
    quotes: { symbols, _ in
      symbols.map { Quote(symbol: $0, price: Decimal(string: "123.45")!, previousClose: Decimal(string: "120")!, changePercent: 2.88, asOf: Date()) }
    },
    series: { symbol, range, _ in
      let start = Date().addingTimeInterval(-86400 * 30)
      let points = (0 ..< 30).map { PricePoint(date: start.addingTimeInterval(Double($0) * 86400), close: Decimal(100 + ($0 % 7) * 3)) }
      return PriceSeries(symbol: symbol, range: range, points: points, asOf: Date())
    },
    search: { query in
      [SymbolSearchResult(symbol: query.uppercased(), name: "\(query.uppercased()) Inc", exchange: "NASDAQ", type: "Common Stock")]
    },
    profile: { _ in throw MarketDataError.unavailable }
  )
}

public extension DependencyValues {
  var marketData: MarketDataClient {
    get { self[MarketDataClient.self] }
    set { self[MarketDataClient.self] = newValue }
  }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests`
Expected PASS: 4 tests pass.

- [ ] **Step 8: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/MarketDataClient Wait/Packages/WaitKit/Tests/MarketDataClientTests
git commit -m "feat(marketdata): MarketDataClient dependency, errors and cache policies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: `CacheTTL`, aware of market hours

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/MarketDataClient/CacheTTL.swift`
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/CacheTTLTests.swift`

- [ ] **Step 1: Write the failing tests.** The instants are from overview §6.3 and were cross-checked in Python.

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/CacheTTLTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import MarketDataClient
import Testing

@Suite struct CacheTTLTests {
  let open = Date(timeIntervalSince1970: 1_795_186_800) // Fri 2026-11-20 10:00 ET
  let postClose = Date(timeIntervalSince1970: 1_795_209_000) // Fri 16:10 ET
  let evening = Date(timeIntervalSince1970: 1_795_212_000) // Fri 17:00 ET
  let saturday = Date(timeIntervalSince1970: 1_795_273_200) // Sat 10:00 ET
  let mondayOpen = Date(timeIntervalSince1970: 1_795_444_200) // Mon 2026-11-23 09:30 ET

  @Test func quotes() {
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: open) == open + 60)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: postClose) == postClose + 300)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: evening) == mondayOpen)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: saturday) == mondayOpen)
  }

  @Test func intradaySeries() {
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: open) == open + 300)
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: evening) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneWeek), fetchedAt: open) == open + 900)
    #expect(CacheTTL.expiry(for: .series(.oneWeek), fetchedAt: saturday) == mondayOpen)
  }

  @Test func dailySeriesExpireTwoHoursAfterTheNextClose() {
    #expect(CacheTTL.expiry(for: .series(.oneYear), fetchedAt: open) == Date(timeIntervalSince1970: 1_795_215_600)) // Fri 18:00 ET
    #expect(CacheTTL.expiry(for: .series(.fiveYears), fetchedAt: evening) == Date(timeIntervalSince1970: 1_795_474_800)) // Mon 18:00 ET
    #expect(CacheTTL.expiry(for: .series(.oneMonth), fetchedAt: open) == Date(timeIntervalSince1970: 1_795_215_600))
  }

  @Test func weekdayPreOpenWaitsForTheOpen() {
    let preOpen = Date(timeIntervalSince1970: 1_795_438_800) // Mon 2026-11-23 08:00 ET
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: preOpen) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: preOpen) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneYear), fetchedAt: preOpen) == Date(timeIntervalSince1970: 1_795_474_800)) // Mon 18:00 ET
  }

  @Test func searchAndProfile() {
    #expect(CacheTTL.expiry(for: .search, fetchedAt: open) == open + 86400)
    #expect(CacheTTL.expiry(for: .profile, fetchedAt: open) == open + 7 * 86400)
    #expect(CacheTTL.maxStaleAge == 7 * 86400)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests/CacheTTLTests`
Expected FAIL: `error: cannot find 'CacheTTL' in scope`.

- [ ] **Step 3: Implement**

`Wait/Packages/WaitKit/Sources/MarketDataClient/CacheTTL.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - MarketDataKind

public enum MarketDataKind: Hashable, Sendable {
  case quote
  case series(ChartRange)
  case search
  case profile
}

// MARK: - CacheTTL

/// Device cache expiry, depending on market hours (overview §6.3).
public enum CacheTTL: Sendable {
  /// How old a stale entry may be and still serve as a fallback.
  public static let maxStaleAge: TimeInterval = 7 * 24 * 60 * 60

  public static func expiry(for kind: MarketDataKind, fetchedAt date: Date) -> Date {
    let isOpen = MarketCalendar.isOpen(at: date)
    switch kind {
      case .quote:
        if isOpen {
          return date + 60
        }
        if MarketCalendar.isWithinPostClose(date, minutes: 30) {
          return date + 5 * 60
        }
        return MarketCalendar.nextOpen(after: date)
      case .series(.oneDay):
        return isOpen ? date + 5 * 60 : MarketCalendar.nextOpen(after: date)
      case .series(.oneWeek):
        return isOpen ? date + 15 * 60 : MarketCalendar.nextOpen(after: date)
      case .series:
        return MarketCalendar.nextClose(after: date) + 2 * 60 * 60
      case .search:
        return date + 24 * 60 * 60
      case .profile:
        return date + 7 * 24 * 60 * 60
    }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests/CacheTTLTests`
Expected PASS: 5 tests pass.

- [ ] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/MarketDataClient/CacheTTL.swift Wait/Packages/WaitKit/Tests/MarketDataClientTests/CacheTTLTests.swift
git commit -m "feat(marketdata): market-hours aware cache TTLs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: `DiskCache`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/MarketDataClient/DiskCache.swift`
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/DiskCacheTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/DiskCacheTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import MarketDataClient
import Testing

@Suite struct DiskCacheTests {
  func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "marketdata-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  @Test func writeThenReadFromANewInstance() {
    let directory = tempDirectory()
    let entry = CacheEntry(data: Data("hello".utf8), fetchedAt: fridayOpen, expiresAt: fridayOpen + 60)
    DiskCache.files(in: directory).write("quote:AAPL", entry)
    #expect(DiskCache.files(in: directory).read("quote:AAPL") == entry)
    #expect(DiskCache.files(in: directory).read("quote:MSFT") == nil)
  }

  @Test func corruptFileReadsNil() throws {
    let directory = tempDirectory()
    let cache = DiskCache.files(in: directory)
    cache.write("k", CacheEntry(data: Data(), fetchedAt: fridayOpen, expiresAt: fridayOpen))
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    try Data("garbage".utf8).write(to: file)
    #expect(cache.read("k") == nil)
  }

  @Test func disabledNeverStores() {
    DiskCache.disabled.write("k", CacheEntry(data: Data(), fetchedAt: fridayOpen, expiresAt: fridayOpen))
    #expect(DiskCache.disabled.read("k") == nil)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests/DiskCacheTests`
Expected FAIL: `error: cannot find 'CacheEntry' in scope`.

- [ ] **Step 3: Implement**

`Wait/Packages/WaitKit/Sources/MarketDataClient/DiskCache.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import CryptoKit
import Foundation
import Logging

// MARK: - CacheEntry

public struct CacheEntry: Codable, Equatable, Sendable {
  public init(data: Data, fetchedAt: Date, expiresAt: Date) {
    self.data = data
    self.fetchedAt = fetchedAt
    self.expiresAt = expiresAt
  }

  public let data: Data
  public let fetchedAt: Date
  public let expiresAt: Date
}

// MARK: - DiskCache

/// One JSON file per key under `Library/Caches/marketdata/`. File names are `sha256(key).json`. It's a best-effort cache, so I/O errors are logged and otherwise ignored.
public struct DiskCache: Sendable {
  // MARK: Lifecycle

  public init(read: @escaping @Sendable (String) -> CacheEntry?, write: @escaping @Sendable (String, CacheEntry) -> Void) {
    self.read = read
    self.write = write
  }

  // MARK: Public

  public static let disabled = DiskCache(read: { _ in nil }, write: { _, _ in })

  public static var live: DiskCache {
    .files(in: URL.cachesDirectory.appending(path: "marketdata", directoryHint: .isDirectory))
  }

  public var read: @Sendable (String) -> CacheEntry?
  public var write: @Sendable (String, CacheEntry) -> Void

  /// A cache rooted at `directory` (named differently from the `live` property to keep call sites unambiguous).
  public static func files(in directory: URL) -> DiskCache {
    DiskCache(
      read: { key in
        guard let data = try? Data(contentsOf: fileURL(directory: directory, key: key)) else {
          return nil
        }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
      },
      write: { key, entry in
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try JSONEncoder().encode(entry).write(to: fileURL(directory: directory, key: key), options: .atomic)
        } catch {
          Log.network.error("Disk cache write failed for \(key): \(error)")
        }
      }
    )
  }

  // MARK: Private

  private static func fileURL(directory: URL, key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appending(path: "\(digest).json")
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests/DiskCacheTests`
Expected PASS: 3 tests pass.

- [ ] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/MarketDataClient/DiskCache.swift Wait/Packages/WaitKit/Tests/MarketDataClientTests/DiskCacheTests.swift
git commit -m "feat(marketdata): sha256-keyed disk cache for market data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 6: MarketDataClient — caching decorator

### Task 16: Caching decorator (`CachingMarketDataClient`)

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/MarketDataClient/CachingMarketDataClient.swift`
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/CachingMarketDataClientTests.swift`

- [ ] **Step 1: Write the failing tests.** These cover the 8 behaviors in overview §6.3, plus rotation of long watchlists under a per-call symbol limit.

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/CachingMarketDataClientTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import MarketDataClient
import Testing

@Suite struct CachingMarketDataClientTests {
  func make(_ upstream: FakeUpstream, now: MutableNow, disk: DiskCache = .disabled) -> MarketDataClient {
    .cached(upstream.client, disk: disk, now: { now.date })
  }

  func isRateLimited(_ error: (any Error)?) -> Bool {
    if case .rateLimited = error as? MarketDataError { true } else { false }
  }

  @Test func freshHitMakesNoUpstreamCall() async throws {
    let upstream = FakeUpstream()
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    _ = try await client.quotes(["AAPL"], .useCache)
    now.advance(30)
    let quotes = try await client.quotes(["aapl"], .useCache)
    #expect(upstream.quoteCalls == [["AAPL"]])
    #expect(quotes.map(\.isStale) == [false])
  }

  @Test func expiredEntryFetchesAgain() async throws {
    let upstream = FakeUpstream()
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    _ = try await client.quotes(["AAPL"], .useCache)
    now.advance(61)
    _ = try await client.quotes(["AAPL"], .useCache)
    #expect(upstream.quoteCalls.count == 2)
  }

  @Test func failedFetchFallsBackToStale() async throws {
    let upstream = FakeUpstream()
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    _ = try await client.quotes(["AAPL", "MSFT"], .useCache)
    upstream.fail(with: .network("offline"))
    now.advance(61)
    let quotes = try await client.quotes(["AAPL", "MSFT"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(quotes.allSatisfy(\.isStale))
  }

  @Test func reloadBypassesAFreshEntry() async throws {
    let upstream = FakeUpstream()
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    _ = try await client.series("AAPL", .oneYear, .useCache)
    _ = try await client.series("AAPL", .oneYear, .reload)
    #expect(upstream.seriesCalls == 2)
  }

  @Test func cacheOnlyWithoutAnEntryThrowsNotCached() async {
    let upstream = FakeUpstream()
    let client = make(upstream, now: MutableNow(fridayOpen))
    await #expect(throws: MarketDataError.notCached) {
      try await client.quotes(["AAPL"], .cacheOnly)
    }
    await #expect(throws: MarketDataError.notCached) {
      try await client.series("AAPL", .oneDay, .cacheOnly)
    }
    #expect(upstream.quoteCalls.isEmpty)
  }

  @Test func concurrentCallsAreCoalesced() async throws {
    let upstream = FakeUpstream(delay: .milliseconds(100))
    let client = make(upstream, now: MutableNow(fridayOpen))
    async let first = client.series("AAPL", .oneYear, .useCache)
    async let second = client.series("AAPL", .oneYear, .useCache)
    let (a, b) = try await (first, second)
    #expect(a == b)
    #expect(upstream.seriesCalls == 1)
  }

  @Test func cooldownSkipsUpstreamUntilItExpires() async throws {
    let upstream = FakeUpstream()
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    upstream.fail(with: .rateLimited(retryAfter: .seconds(120)))
    let first = await #expect(throws: MarketDataError.self) { try await client.quotes(["AAPL"], .useCache) }
    #expect(isRateLimited(first))
    now.advance(60)
    let second = await #expect(throws: MarketDataError.self) { try await client.quotes(["AAPL"], .reload) }
    #expect(isRateLimited(second))
    #expect(upstream.quoteCalls.count == 1)
    now.advance(61)
    upstream.fail(with: nil)
    _ = try await client.quotes(["AAPL"], .useCache)
    #expect(upstream.quoteCalls.count == 2)
  }

  @Test func longWatchlistsRotateInsteadOfStarving() async throws {
    let upstream = FakeUpstream(batchLimit: 8)
    let now = MutableNow(fridayOpen)
    let client = make(upstream, now: now)
    let symbols = (0 ..< 10).map { "S\($0)" }
    let first = try await client.quotes(symbols, .useCache) // partial result, no throw; the cooldown starts
    #expect(first.map(\.symbol) == Array(symbols.prefix(8)))
    now.advance(61) // past the 60 s cooldown and the 60 s quote TTL
    let second = try await client.quotes(symbols, .useCache)
    #expect(upstream.quoteCalls.count == 2)
    #expect(upstream.quoteCalls[1].prefix(2) == ["S8", "S9"]) // never-cached symbols are fetched first
    #expect(Set(second.map(\.symbol)) == Set(symbols))
    #expect(second.filter(\.isStale).map(\.symbol) == ["S6", "S7"])
  }

  @Test func diskEntrySurvivesANewInstance() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "md-\(UUID().uuidString)", directoryHint: .isDirectory)
    let now = MutableNow(fridayOpen)
    _ = try await make(FakeUpstream(), now: now, disk: .files(in: directory)).quotes(["AAPL"], .useCache)
    let offline = FakeUpstream()
    offline.fail(with: .network("offline"))
    let quotes = try await make(offline, now: now, disk: .files(in: directory)).quotes(["AAPL"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL"])
    #expect(quotes.map(\.isStale) == [false])
    #expect(offline.quoteCalls.isEmpty)
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests/CachingMarketDataClientTests`
Expected FAIL: `error: type 'MarketDataClient' has no member 'cached'`.

- [ ] **Step 3: Implement**

`Wait/Packages/WaitKit/Sources/MarketDataClient/CachingMarketDataClient.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Logging

public extension MarketDataClient {
  /// Wraps `upstream` with the device cache: TTLs, disk persistence, in-flight coalescing, a stale fallback and a 429 cooldown.
  static func cached(
    _ upstream: MarketDataClient,
    disk: DiskCache,
    ttl: @escaping @Sendable (MarketDataKind, Date) -> Date = { CacheTTL.expiry(for: $0, fetchedAt: $1) },
    now: @escaping @Sendable () -> Date
  ) -> MarketDataClient {
    let store = CachingMarketDataStore(upstream: upstream, disk: disk, ttl: ttl, now: now)
    return MarketDataClient(
      quotes: { symbols, policy in try await store.quotes(symbols, policy: policy) },
      series: { symbol, range, policy in try await store.series(symbol, range: range, policy: policy) },
      search: { query in try await store.search(query) },
      profile: { symbol in try await store.profile(symbol) }
    )
  }
}

// MARK: - CachingMarketDataStore

actor CachingMarketDataStore {
  // MARK: Lifecycle

  init(
    upstream: MarketDataClient,
    disk: DiskCache,
    ttl: @escaping @Sendable (MarketDataKind, Date) -> Date,
    now: @escaping @Sendable () -> Date
  ) {
    self.upstream = upstream
    self.disk = disk
    self.ttl = ttl
    self.now = now
  }

  // MARK: Internal

  func quotes(_ symbols: [String], policy: CachePolicy) async throws -> [Quote] {
    var seen = Set<String>()
    let requested = symbols.map { $0.uppercased() }.filter { seen.insert($0).inserted }
    guard !requested.isEmpty else {
      return []
    }
    let now = now()
    let cooling = isCoolingDown(at: now)
    var result: [String: Quote] = [:]
    var toFetch: [String] = []
    var lastFetched: [String: Date] = [:]

    for symbol in requested {
      let hit = lookup(Quote.self, key: Self.quoteKey(symbol))
      lastFetched[symbol] = hit?.entry.fetchedAt
      if policy == .cacheOnly {
        if let hit {
          result[symbol] = hit.value.with(isStale: hit.entry.expiresAt <= now)
        }
      } else if cooling {
        if let hit, isUsableAsStale(hit.entry, now: now) {
          result[symbol] = hit.value.with(isStale: hit.entry.expiresAt <= now)
        }
      } else if policy == .useCache, let hit, hit.entry.expiresAt > now {
        result[symbol] = hit.value.with(isStale: false)
      } else {
        toFetch.append(symbol)
      }
    }

    if policy == .cacheOnly {
      guard !result.isEmpty else {
        throw MarketDataError.notCached
      }
      return requested.compactMap { result[$0] }
    }
    if cooling {
      guard !result.isEmpty else {
        throw MarketDataError.rateLimited(retryAfter: remainingCooldown(at: now))
      }
      return requested.compactMap { result[$0] }
    }

    if !toFetch.isEmpty {
      // Never-cached symbols first, then the oldest. A rate-limited upstream (8 symbols/min on Twelve Data) then
      // rotates through a long watchlist instead of refetching the same first symbols forever.
      let batch = toFetch.enumerated()
        .sorted { ((lastFetched[$0.element] ?? .distantPast), $0.offset) < ((lastFetched[$1.element] ?? .distantPast), $1.offset) }
        .map(\.element)
      do {
        let upstream = upstream
        let data = try await coalesced(key: "quotes:" + batch.joined(separator: ",")) {
          try JSONEncoder().encode(try await upstream.quotes(batch, policy))
        }
        try storeFresh(JSONDecoder().decode([Quote].self, from: data), into: &result, fetchedAt: now)
      } catch let partial as PartialQuotesError {
        storeFresh(partial.quotes, into: &result, fetchedAt: now)
        noteFailure(.rateLimited(retryAfter: partial.retryAfter), at: now)
        fillStale(batch, into: &result, now: now)
      } catch {
        let mapped = try MarketDataError(error)
        noteFailure(mapped, at: now)
        fillStale(batch, into: &result, now: now)
        guard !result.isEmpty else {
          throw mapped
        }
      }
    }
    return requested.compactMap { result[$0] }
  }

  func series(_ symbol: String, range: ChartRange, policy: CachePolicy) async throws -> PriceSeries {
    let upstream = upstream
    let symbol = symbol.uppercased()
    return try await single(
      key: "series:\(symbol):\(range.rawValue)",
      kind: .series(range),
      policy: policy,
      markStale: { $0.with(isStale: $1) },
      fetch: { try await upstream.series(symbol, range, policy) }
    )
  }

  func search(_ query: String) async throws -> [SymbolSearchResult] {
    let upstream = upstream
    let normalized = query.trimmingCharacters(in: .whitespaces).lowercased()
    return try await single(
      key: "search:\(normalized)",
      kind: .search,
      policy: .useCache,
      markStale: { value, _ in value },
      fetch: { try await upstream.search(normalized) }
    )
  }

  func profile(_ symbol: String) async throws -> CompanyProfile {
    let upstream = upstream
    let symbol = symbol.uppercased()
    return try await single(
      key: "profile:\(symbol)",
      kind: .profile,
      policy: .useCache,
      markStale: { value, _ in value },
      fetch: { try await upstream.profile(symbol) }
    )
  }

  // MARK: Private

  private let upstream: MarketDataClient
  private let disk: DiskCache
  private let ttl: @Sendable (MarketDataKind, Date) -> Date
  private let now: @Sendable () -> Date
  private var memory: [String: CacheEntry] = [:]
  private var inFlight: [String: Task<Data, any Error>] = [:]
  private var cooldownUntil: Date?

  private static func quoteKey(_ symbol: String) -> String {
    "quote:\(symbol)"
  }

  private func storeFresh(_ quotes: [Quote], into result: inout [String: Quote], fetchedAt now: Date) {
    for quote in quotes {
      let fresh = quote.with(isStale: false)
      let symbol = fresh.symbol.uppercased()
      store(fresh, key: Self.quoteKey(symbol), kind: .quote, fetchedAt: now)
      result[symbol] = fresh
    }
  }

  private func fillStale(_ symbols: [String], into result: inout [String: Quote], now: Date) {
    for symbol in symbols where result[symbol] == nil {
      if let hit = lookup(Quote.self, key: Self.quoteKey(symbol)), isUsableAsStale(hit.entry, now: now) {
        result[symbol] = hit.value.with(isStale: hit.entry.expiresAt <= now)
      }
    }
  }

  private func single<T: Codable & Sendable>(
    key: String,
    kind: MarketDataKind,
    policy: CachePolicy,
    markStale: (T, Bool) -> T,
    fetch: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let now = now()
    let hit = lookup(T.self, key: key)
    if policy == .cacheOnly {
      guard let hit else {
        throw MarketDataError.notCached
      }
      return markStale(hit.value, hit.entry.expiresAt <= now)
    }
    if isCoolingDown(at: now) {
      guard let hit, isUsableAsStale(hit.entry, now: now) else {
        throw MarketDataError.rateLimited(retryAfter: remainingCooldown(at: now))
      }
      return markStale(hit.value, hit.entry.expiresAt <= now)
    }
    if policy == .useCache, let hit, hit.entry.expiresAt > now {
      return markStale(hit.value, false)
    }
    do {
      let data = try await coalesced(key: key) { try JSONEncoder().encode(try await fetch()) }
      let value = try JSONDecoder().decode(T.self, from: data)
      store(data: data, key: key, kind: kind, fetchedAt: now)
      return markStale(value, false)
    } catch {
      let mapped = try MarketDataError(error)
      noteFailure(mapped, at: now)
      if let hit, isUsableAsStale(hit.entry, now: now) {
        return markStale(hit.value, hit.entry.expiresAt <= now)
      }
      throw mapped
    }
  }

  private func coalesced(key: String, _ work: @escaping @Sendable () async throws -> Data) async throws -> Data {
    if let running = inFlight[key] {
      return try await running.value
    }
    let task = Task<Data, any Error> { try await work() }
    inFlight[key] = task
    defer { inFlight[key] = nil }
    return try await task.value
  }

  private func lookup<T: Decodable>(_: T.Type, key: String) -> (value: T, entry: CacheEntry)? {
    let entry: CacheEntry
    if let cached = memory[key] {
      entry = cached
    } else if let fromDisk = disk.read(key) {
      memory[key] = fromDisk
      entry = fromDisk
    } else {
      return nil
    }
    guard let value = try? JSONDecoder().decode(T.self, from: entry.data) else {
      return nil
    }
    return (value, entry)
  }

  private func store(_ value: some Encodable, key: String, kind: MarketDataKind, fetchedAt: Date) {
    guard let data = try? JSONEncoder().encode(value) else {
      return
    }
    store(data: data, key: key, kind: kind, fetchedAt: fetchedAt)
  }

  private func store(data: Data, key: String, kind: MarketDataKind, fetchedAt: Date) {
    let entry = CacheEntry(data: data, fetchedAt: fetchedAt, expiresAt: ttl(kind, fetchedAt))
    memory[key] = entry
    disk.write(key, entry)
  }

  private func isUsableAsStale(_ entry: CacheEntry, now: Date) -> Bool {
    now.timeIntervalSince(entry.fetchedAt) <= CacheTTL.maxStaleAge
  }

  private func isCoolingDown(at now: Date) -> Bool {
    guard let cooldownUntil else {
      return false
    }
    return now < cooldownUntil
  }

  private func remainingCooldown(at now: Date) -> Duration? {
    cooldownUntil.map { .seconds(max(0, $0.timeIntervalSince(now))) }
  }

  private func noteFailure(_ error: MarketDataError, at now: Date) {
    guard case let .rateLimited(retryAfter) = error else {
      return
    }
    let seconds = retryAfter.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? 60
    cooldownUntil = now.addingTimeInterval(seconds)
    Log.network.info("Market data cooldown for \(Int(seconds))s")
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests`
Expected PASS: `** TEST SUCCEEDED **`, with all 9 caching tests passing.

- [ ] **Step 5: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/MarketDataClient/CachingMarketDataClient.swift Wait/Packages/WaitKit/Tests/MarketDataClientTests/CachingMarketDataClientTests.swift
git commit -m "feat(marketdata): caching decorator with coalescing, stale fallback and 429 cooldown

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 7: MarketDataClient — Twelve Data stopgap

### Task 17: Twelve Data stopgap adapter and `liveValue`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/MarketDataClient/TwelveData/TwelveDataMarketData.swift`, `Wait/Packages/WaitKit/Sources/MarketDataClient/TwelveData/TwelveDataDTOs.swift`
- Modify: `Wait/Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift` (add `liveValue`)
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/Fixtures/twelvedata-quote-batch.json`, `twelvedata-quote-single.json`, `twelvedata-rate-limited.json`, `twelvedata-time-series-1day.json`, `twelvedata-time-series-5min.json`, `twelvedata-search.json`
- Create: `Wait/Packages/WaitKit/Tests/MarketDataClientTests/TwelveDataMarketDataTests.swift`
- Modify: `Wait/Packages/WaitKit/Package.swift` (`MarketDataClientTests` gains a resource)

This adapter exists only until plan 04 replaces it with `.backend`. It runs under the free-tier limits: 8 credits per minute, one credit per symbol, and errors reported per symbol.

- [ ] **Step 1: Add the fixture resource.** In `Package.swift`, change the `MarketDataClientTests` target to:
```swift
.testTarget(
  name: "MarketDataClientTests",
  dependencies: ["MarketDataClient", "Domain", .dependencies, .dependenciesTestSupport],
  resources: [.copy("Fixtures")]
),
```

- [ ] **Step 2: Create the fixtures.** All of them are in `Wait/Packages/WaitKit/Tests/MarketDataClientTests/Fixtures/`.

`twelvedata-quote-batch.json` (`XXXX` is an error for one symbol, and `BAD` is garbage that must not fail the batch):
```json
{
  "AAPL": {
    "symbol": "AAPL", "name": "Apple Inc", "exchange": "NASDAQ", "mic_code": "XNGS", "currency": "USD",
    "datetime": "2026-11-20", "timestamp": 1795208400,
    "open": "188.10000", "high": "190.50000", "low": "187.20000", "close": "189.98000", "volume": "51234567",
    "previous_close": "187.66000", "change": "2.32000", "percent_change": "1.23628", "average_volume": "50000000",
    "is_market_open": false,
    "fifty_two_week": { "low": "164.08000", "high": "199.62000", "range": "164.080000 - 199.620000" }
  },
  "XXXX": { "code": 400, "message": "**symbol** not found: XXXX. Please specify it correctly according to API Documentation.", "status": "error" },
  "BAD": 42
}
```

`twelvedata-quote-single.json`:
```json
{
  "symbol": "MSFT", "name": "Microsoft Corp", "exchange": "NASDAQ", "currency": "USD",
  "datetime": "2026-11-20", "timestamp": 1795208400,
  "open": "410.00000", "high": "415.00000", "low": "409.00000", "close": "414.25000", "volume": "20000000",
  "previous_close": "411.00000", "change": "3.25000", "percent_change": "0.79075", "is_market_open": false,
  "fifty_two_week": { "low": "350.00000", "high": "450.00000" }
}
```

`twelvedata-rate-limited.json`. Twelve Data returns this with **HTTP 200**:
```json
{ "code": 429, "message": "You have run out of API credits for the current minute. 9 API credits were used, with the current limit being 8.", "status": "error" }
```

`twelvedata-time-series-1day.json` (newest first, as the API returns it):
```json
{
  "meta": { "symbol": "AAPL", "interval": "1day", "currency": "USD", "exchange_timezone": "UTC", "exchange": "NASDAQ", "type": "Common Stock" },
  "values": [
    { "datetime": "2026-11-20", "open": "188.1", "high": "190.5", "low": "187.2", "close": "189.98", "volume": "51234567" },
    { "datetime": "2026-11-19", "open": "186.0", "high": "188.0", "low": "185.0", "close": "187.66", "volume": "40000000" }
  ],
  "status": "ok"
}
```

`twelvedata-time-series-5min.json` (spans two sessions):
```json
{
  "meta": { "symbol": "AAPL", "interval": "5min", "currency": "USD", "exchange_timezone": "UTC", "exchange": "NASDAQ", "type": "Common Stock" },
  "values": [
    { "datetime": "2026-11-20 20:55:00", "open": "189.9", "high": "190.0", "low": "189.8", "close": "189.98", "volume": "100" },
    { "datetime": "2026-11-20 20:50:00", "open": "189.4", "high": "189.6", "low": "189.3", "close": "189.50", "volume": "100" },
    { "datetime": "2026-11-19 20:55:00", "open": "187.6", "high": "187.7", "low": "187.5", "close": "187.66", "volume": "100" }
  ],
  "status": "ok"
}
```

`twelvedata-search.json`:
```json
{
  "data": [
    { "symbol": "AAPL", "instrument_name": "Apple Inc", "exchange": "NASDAQ", "mic_code": "XNGS", "instrument_type": "Common Stock", "country": "United States", "currency": "USD" },
    { "symbol": "AAPL", "instrument_name": "Apple Inc", "exchange": "BMV", "mic_code": "XMEX", "instrument_type": "Common Stock", "country": "Mexico", "currency": "MXN" },
    { "symbol": "APLE", "instrument_name": "Apple Hospitality REIT Inc", "exchange": "NYSE", "mic_code": "XNYS", "instrument_type": "REIT", "country": "United States", "currency": "USD" },
    { "symbol": "AAPU", "instrument_name": "Direxion Daily AAPL Bull 2X Shares", "exchange": "NASDAQ", "mic_code": "XNMS", "instrument_type": "ETF", "country": "United States", "currency": "USD" }
  ],
  "status": "ok"
}
```

- [ ] **Step 3: Write the failing tests**

`Wait/Packages/WaitKit/Tests/MarketDataClientTests/TwelveDataMarketDataTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import MarketDataClient
import Testing

// MARK: - RecordingHTTP

actor RecordingHTTP {
  // MARK: Lifecycle

  init(_ responder: @escaping @Sendable (URL) -> (Data, Int)) {
    self.responder = responder
  }

  // MARK: Internal

  private(set) var urls: [URL] = []

  func get(_ url: URL) -> (Data, HTTPURLResponse) {
    urls.append(url)
    let (data, status) = responder(url)
    return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }

  // MARK: Private

  private let responder: @Sendable (URL) -> (Data, Int)
}

func fixture(_ name: String) -> Data {
  try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
}

/// A batch body with a minimal valid quote for each symbol.
func batchJSON(_ symbols: [String]) -> Data {
  let entries = symbols.map { #""\#($0)": {"close": "1.00", "timestamp": 1795208400}"# }
  return Data(("{" + entries.joined(separator: ",") + "}").utf8)
}

func query(_ url: URL) -> [String: String] {
  Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

// MARK: - TwelveDataMarketDataTests

@Suite struct TwelveDataMarketDataTests {
  func client(_ http: RecordingHTTP) -> MarketDataClient {
    .twelveData(apiKey: "test-key", get: { url in await http.get(url) })
  }

  @Test func batchQuotesSkipErroredAndGarbageSymbols() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-quote-batch"), 200) }
    let quotes = try await client(http).quotes(["AAPL", "XXXX", "BAD"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL"])
    let aapl = try #require(quotes.first)
    #expect(aapl.price == dec("189.98"))
    #expect(aapl.previousClose == dec("187.66"))
    #expect(abs((aapl.changePercent ?? 0) - 1.23628) < 0.00001)
    #expect(aapl.volume == 51_234_567)
    #expect(aapl.fiftyTwoWeekHigh == dec("199.62"))
    #expect(aapl.asOf == Date(timeIntervalSince1970: 1_795_208_400))
  }

  @Test func singleSymbolUsesTheSingleObjectShape() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-quote-single"), 200) }
    let quotes = try await client(http).quotes(["MSFT"], .useCache)
    #expect(quotes.map(\.price) == [dec("414.25")])
  }

  @Test func quotesAreChunkedByEight() async throws {
    let http = RecordingHTTP { _ in (Data("{}".utf8), 200) }
    let symbols = (1 ... 10).map { "S\($0)" }
    _ = try await client(http).quotes(symbols, .useCache)
    let urls = await http.urls
    #expect(urls.count == 2)
    #expect(query(urls[0])["symbol"]?.split(separator: ",").count == 8)
    #expect(query(urls[1])["symbol"] == "S9,S10")
  }

  @Test func midListRateLimitThrowsThePartialQuotes() async throws {
    let http = RecordingHTTP { url in
      let symbols = (query(url)["symbol"] ?? "").split(separator: ",").map(String.init)
      return symbols.count == 8 ? (batchJSON(symbols), 200) : (fixture("twelvedata-rate-limited"), 200)
    }
    let symbols = (1 ... 10).map { "S\($0)" }
    let error = await #expect(throws: PartialQuotesError.self) {
      try await client(http).quotes(symbols, .useCache)
    }
    #expect(error?.quotes.map(\.symbol) == Array(symbols.prefix(8)))
    #expect(error?.retryAfter == .seconds(60))
  }

  @Test func rateLimitedBodyWithHTTP200Throws() async {
    let http = RecordingHTTP { _ in (fixture("twelvedata-rate-limited"), 200) }
    await #expect(throws: MarketDataError.rateLimited(retryAfter: .seconds(60))) {
      try await client(http).quotes(["AAPL"], .useCache)
    }
  }

  @Test func requestsCarryTheKeyAndUTC() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-1day"), 200) }
    _ = try await client(http).series("AAPL", .oneYear, .useCache)
    let url = try #require(await http.urls.first)
    #expect(url.path == "/time_series")
    #expect(query(url) == ["apikey": "test-key", "interval": "1day", "outputsize": "252", "symbol": "AAPL", "timezone": "UTC"])
  }

  @Test func dailySeriesParsesMonthsCorrectlyAndSortsOldestFirst() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-1day"), 200) }
    let series = try await client(http).series("AAPL", .oneYear, .useCache)
    #expect(series.points.map(\.date) == [Date(timeIntervalSince1970: 1_795_089_600), Date(timeIntervalSince1970: 1_795_176_000)])
    #expect(series.points.map(\.close) == [dec("187.66"), dec("189.98")])
  }

  @Test func oneDayKeepsOnlyTheLastSession() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-5min"), 200) }
    let series = try await client(http).series("AAPL", .oneDay, .useCache)
    #expect(series.points.map(\.date) == [Date(timeIntervalSince1970: 1_795_207_800), Date(timeIntervalSince1970: 1_795_208_100)])
    #expect(query(try #require(await http.urls.first))["interval"] == "5min")
  }

  @Test func searchKeepsUSListedEquityTypes() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-search"), 200) }
    let results = try await client(http).search("app")
    #expect(results.map(\.symbol) == ["AAPL", "APLE", "AAPU"]) // Mexico listing dropped; REIT and ETF kept
    #expect(results.first?.name == "Apple Inc")
  }

  @Test func profileIsUnavailable() async {
    let http = RecordingHTTP { _ in (Data(), 200) }
    await #expect(throws: MarketDataError.unavailable) {
      try await client(http).profile("AAPL")
    }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh MarketDataClientTests/TwelveDataMarketDataTests`
Expected FAIL: `error: type 'MarketDataClient' has no member 'twelveData'`.

- [ ] **Step 5: Implement `TwelveDataDTOs.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - TDError

struct TDError: Decodable {
  let code: Int
  let message: String
  let status: String

  var marketDataError: MarketDataError {
    switch code {
      case 429: .rateLimited(retryAfter: .seconds(60))
      case 404: .notFound
      case 400 where message.localizedCaseInsensitiveContains("not found"): .notFound
      default: .network(message)
    }
  }
}

// MARK: - TDQuote

struct TDQuote: Decodable {
  struct Range: Decodable {
    let low: String?
    let high: String?
  }

  enum CodingKeys: String, CodingKey {
    case timestamp, open, high, low, close, volume, change, code
    case previousClose = "previous_close"
    case percentChange = "percent_change"
    case fiftyTwoWeek = "fifty_two_week"
  }

  let timestamp: Int?
  let open: String?
  let high: String?
  let low: String?
  let close: String?
  let volume: String?
  let change: String?
  let code: Int?
  let previousClose: String?
  let percentChange: String?
  let fiftyTwoWeek: Range?

  func quote(symbol: String) -> Quote? {
    guard code == nil, let price = close.flatMap(DecimalCoding.parse) else {
      return nil
    }
    return Quote(
      symbol: symbol.uppercased(),
      price: price,
      previousClose: previousClose.flatMap(DecimalCoding.parse),
      open: open.flatMap(DecimalCoding.parse),
      high: high.flatMap(DecimalCoding.parse),
      low: low.flatMap(DecimalCoding.parse),
      change: change.flatMap(DecimalCoding.parse),
      changePercent: percentChange.flatMap(Double.init),
      volume: volume.flatMap(Int.init),
      fiftyTwoWeekHigh: fiftyTwoWeek?.high.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: fiftyTwoWeek?.low.flatMap(DecimalCoding.parse),
      asOf: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    )
  }
}

// MARK: - LossyTDQuote

struct LossyTDQuote: Decodable {
  let value: TDQuote?

  init(from decoder: any Decoder) throws {
    value = try? TDQuote(from: decoder)
  }
}

// MARK: - TDTimeSeries

struct TDTimeSeries: Decodable {
  struct Bar: Decodable {
    let datetime: String
    let close: String
  }

  let values: [Bar]?
}

// MARK: - TDSearch

struct TDSearch: Decodable {
  struct Item: Decodable {
    enum CodingKeys: String, CodingKey {
      case symbol, exchange, country
      case instrumentName = "instrument_name"
      case instrumentType = "instrument_type"
    }

    let symbol: String
    let exchange: String?
    let country: String?
    let instrumentName: String
    let instrumentType: String?
  }

  let data: [Item]
}

// MARK: - TwelveDataDecoding

enum TwelveDataDecoding {
  static let searchableTypes: Set<String> = ["Common Stock", "ETF", "REIT", "Depositary Receipt"]

  static func quotes(from data: Data, requested: [String]) throws -> [Quote] {
    let decoder = JSONDecoder()
    if requested.count == 1 {
      return try decoder.decode(TDQuote.self, from: data).quote(symbol: requested[0]).map { [$0] } ?? []
    }
    // Lossy per symbol: one garbage entry (wrong type, missing fields) mustn't fail the whole batch.
    let batch = try decoder.decode([String: LossyTDQuote].self, from: data)
    return requested.compactMap { symbol in (batch[symbol] ?? batch[symbol.uppercased()])?.value?.quote(symbol: symbol) }
  }

  /// `timezone=UTC` is always requested. Date-only bars are anchored at 12:00 UTC so US time zones show the same calendar day.
  static func points(from data: Data) throws -> [PricePoint] {
    let series = try JSONDecoder().decode(TDTimeSeries.self, from: data)
    let dateTime = DateFormatter()
    dateTime.locale = Locale(identifier: "en_US_POSIX")
    dateTime.timeZone = TimeZone(identifier: "UTC")
    dateTime.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.timeZone = TimeZone(identifier: "UTC")
    dateOnly.dateFormat = "yyyy-MM-dd"
    return (series.values ?? [])
      .compactMap { bar -> PricePoint? in
        let date = dateTime.date(from: bar.datetime) ?? dateOnly.date(from: bar.datetime).map { $0.addingTimeInterval(12 * 3600) }
        guard let date, let close = DecimalCoding.parse(bar.close) else {
          return nil
        }
        return PricePoint(date: date, close: close)
      }
      .sorted { $0.date < $1.date }
  }

  /// Keeps only the points on the same New York calendar day as the newest point.
  static func lastSession(_ points: [PricePoint]) -> [PricePoint] {
    guard let last = points.last else {
      return []
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = MarketCalendar.timeZone
    return points.filter { calendar.isDate($0.date, inSameDayAs: last.date) }
  }

  static func search(from data: Data) throws -> [SymbolSearchResult] {
    let response = try JSONDecoder().decode(TDSearch.self, from: data)
    var seen = Set<String>()
    return response.data
      .filter { $0.country == "United States" && Self.searchableTypes.contains($0.instrumentType ?? "") }
      .filter { seen.insert($0.symbol).inserted }
      .map { SymbolSearchResult(symbol: $0.symbol, name: $0.instrumentName, exchange: $0.exchange, type: $0.instrumentType) }
  }
}
```

- [ ] **Step 6: Implement `TwelveDataMarketData.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Logging

/// GET a URL and return the body plus the HTTP response. Tests inject a fake.
public typealias HTTPGet = @Sendable (URL) async throws -> (Data, HTTPURLResponse)

public extension URLSession {
  var httpGet: HTTPGet {
    { [self] url in
      let (data, response) = try await data(from: url)
      guard let http = response as? HTTPURLResponse else {
        throw MarketDataError.network("Non-HTTP response")
      }
      return (data, http)
    }
  }
}

public extension MarketDataClient {
  /// The stopgap adapter until plan 04. Always wrap it with `.cached(...)`.
  static func twelveData(
    apiKey: String,
    baseURL: URL = URL(string: "https://api.twelvedata.com")!,
    get: @escaping HTTPGet = URLSession.shared.httpGet
  ) -> MarketDataClient {
    let api = TwelveDataAPI(apiKey: apiKey, baseURL: baseURL, get: get)
    return MarketDataClient(
      quotes: { symbols, _ in try await api.quotes(symbols) },
      series: { symbol, range, _ in try await api.series(symbol, range: range) },
      search: { query in try await api.search(query) },
      profile: { _ in throw MarketDataError.unavailable }
    )
  }
}

// MARK: - TwelveDataAPI

struct TwelveDataAPI: Sendable {
  // MARK: Internal

  static let batchSize = 8

  let apiKey: String
  let baseURL: URL
  let get: HTTPGet

  static func parameters(for range: ChartRange) -> (interval: String, outputSize: Int) {
    switch range {
      case .oneDay: ("5min", 80)
      case .oneWeek: ("30min", 65)
      case .oneMonth: ("1day", 22)
      case .oneYear: ("1day", 252)
      case .fiveYears: ("1week", 260)
    }
  }

  /// One request per 8 symbols (1 credit per symbol). A 429 on the first chunk throws `.rateLimited`.
  /// A 429 after some chunks succeeded throws `PartialQuotesError`, so the caching decorator keeps those quotes and still cools down.
  func quotes(_ symbols: [String]) async throws -> [Quote] {
    var result: [Quote] = []
    for start in stride(from: 0, to: symbols.count, by: Self.batchSize) {
      let chunk = Array(symbols[start ..< min(start + Self.batchSize, symbols.count)])
      do {
        let data = try await fetch("quote", ["symbol": chunk.joined(separator: ","), "timezone": "UTC"])
        result += try TwelveDataDecoding.quotes(from: data, requested: chunk)
      } catch let error as MarketDataError {
        if case let .rateLimited(retryAfter) = error, !result.isEmpty {
          Log.network.info("Twelve Data rate limited after \(result.count) quotes")
          throw PartialQuotesError(quotes: result, retryAfter: retryAfter)
        }
        throw error
      }
    }
    return result
  }

  func series(_ symbol: String, range: ChartRange) async throws -> PriceSeries {
    let parameters = Self.parameters(for: range)
    let data = try await fetch("time_series", [
      "symbol": symbol,
      "interval": parameters.interval,
      "outputsize": String(parameters.outputSize),
      "timezone": "UTC",
    ])
    var points = try TwelveDataDecoding.points(from: data)
    if range == .oneDay {
      points = TwelveDataDecoding.lastSession(points)
    }
    return PriceSeries(symbol: symbol.uppercased(), range: range, points: points, asOf: points.last?.date ?? Date())
  }

  func search(_ query: String) async throws -> [SymbolSearchResult] {
    let data = try await fetch("symbol_search", ["symbol": query, "outputsize": "30"])
    return try TwelveDataDecoding.search(from: data)
  }

  // MARK: Private

  private func url(_ path: String, _ parameters: [String: String]) -> URL {
    var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
    components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
      + [URLQueryItem(name: "apikey", value: apiKey)]
    return components.url!
  }

  private func fetch(_ path: String, _ parameters: [String: String]) async throws -> Data {
    let (data, response) = try await get(url(path, parameters))
    if response.statusCode == 429 {
      throw MarketDataError.rateLimited(retryAfter: .seconds(60))
    }
    guard (200 ..< 300).contains(response.statusCode) else {
      throw MarketDataError.network("HTTP \(response.statusCode)")
    }
    // Twelve Data reports errors (including 429) as HTTP 200 with a top-level {code, message, status: "error"}.
    if let error = try? JSONDecoder().decode(TDError.self, from: data), error.status == "error" {
      throw error.marketDataError
    }
    return data
  }
}
```

- [ ] **Step 7: Add `liveValue`.** Append to `Wait/Packages/WaitKit/Sources/MarketDataClient/MarketDataClient.swift`. In plan 04 this is the one line to change, to `.cached(.backend(…))`.
```swift
// MARK: DependencyKey

extension MarketDataClient: DependencyKey {
  /// Plan 02: Twelve Data stopgap. The key comes from Info.plist `TwelveDataAPIKey`, which is `$(TWELVE_DATA_API_KEY)` from `Secrets.xcconfig`.
  public static let liveValue = MarketDataClient.cached(
    .twelveData(apiKey: Bundle.main.object(forInfoDictionaryKey: "TwelveDataAPIKey") as? String ?? ""),
    disk: .live,
    now: { Date() }
  )
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh MarketDataClientTests`
Expected PASS: `** TEST SUCCEEDED **`. Every suite passes, including the 10 Twelve Data tests.

- [ ] **Step 9: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/MarketDataClient Wait/Packages/WaitKit/Tests/MarketDataClientTests
git commit -m "feat(marketdata): Twelve Data stopgap adapter (chunked, UTC, 429-in-body) and liveValue

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 8: Design system and checklist

### Task 18: Design tokens, `StatusPill`, `TemperatureBadge`; remove the color shadows

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/DesignSystem/Palette.swift`, `Spacing.swift`, `StatusPill.swift`, `TemperatureBadge.swift`, `LadderStatus+Style.swift`
- Modify: the legacy color files that plan 01 moved into `Sources/DesignSystem/` (`Colors.swift`, `UIColor+CodeName.swift`, `UIColor+Theme.swift`)
- Modify: `Wait/Packages/WaitKit/Package.swift` (`DesignSystem` gains the `Domain` dependency; add `DesignSystemTests`)
- Create: `Wait/Packages/WaitKit/Tests/DesignSystemTests/DesignSystemTests.swift`

- [ ] **Step 1: Update `Package.swift`**
  - In the existing `.target(name: "DesignSystem", …)`, add `"Domain"` to `dependencies:` (create `dependencies: ["Domain"]` if the target has none). Keep its `swiftSettings`; it stays Swift 5 until the cutover.
  - Append to `targets:`: `.testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "Domain"]),`

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/DesignSystemTests/DesignSystemTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI
import Testing

@Suite struct DesignSystemTests {
  @Test func everyStatusHasASymbol() {
    for status in LadderStatus.allCases {
      #expect(!status.symbolName.isEmpty)
    }
    #expect(Set(LadderStatus.allCases.map(\.symbolName)).count == LadderStatus.allCases.count)
  }

  @Test func temperatureBadgeLabel() {
    #expect(TemperatureBadge.label(for: Temperature(value: 21.4)) == "21°")
    #expect(TemperatureBadge.label(for: nil) == "—")
  }

  @Test func changeColorUsesTheSign() {
    #expect(Palette.change(-0.5) == Palette.stockDown)
    #expect(Palette.change(0.5) == Palette.stockUp)
    #expect(Palette.change(nil) == Color.secondary)
  }

  @Test func spacingScale() {
    #expect(Spacing.xs < Spacing.s)
    #expect(Spacing.s < Spacing.l)
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh DesignSystemTests`
Expected FAIL: `error: value of type 'LadderStatus' has no member 'symbolName'`, and `cannot find 'TemperatureBadge' in scope`.

- [ ] **Step 4: Remove the shadows of SwiftUI's colors**

Run: `grep -rn "static let primary\|static let orange" Wait/Packages/WaitKit/Sources/DesignSystem`
Expected: three hits:
- `UIColor+Theme.swift`: `static let primary = Color.mint`
- `Colors.swift`: `static let orange = Color(.orange)`
- `UIColor+CodeName.swift`: `static let orange = UIColor(hex: "#F69000")`

Delete those three lines, plus the `// App Theme` comment above `primary`. Once they are gone, `.primary` is SwiftUI's primary label color again and `.orange` is the system orange. Before this change, the legacy `StockCard` text rendered mint.

- [ ] **Step 5: Implement the tokens**

`Wait/Packages/WaitKit/Sources/DesignSystem/Palette.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Palette

/// Semantic colors with light and dark variants. watchOS always uses the dark variant.
public enum Palette {
  public static let accent = Color.mint
  public static let stockUp = Color(light: 0x00BF83, dark: 0x34D399)
  public static let stockDown = Color(light: 0xDE3745, dark: 0xF87171)
  public static let warning = Color(light: 0xD9A400, dark: 0xFACC15)

  /// Green when the change is ≥ 0, red when it's < 0, secondary when unknown.
  public static func change(_ percent: Double?) -> Color {
    guard let percent else {
      return .secondary
    }
    return percent < 0 ? stockDown : stockUp
  }
}

extension Color {
  init(light: UInt32, dark: UInt32) {
    #if os(iOS)
      self.init(uiColor: UIColor { traits in
        UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
      })
    #else
      self.init(rgb: dark)
    #endif
  }

  init(rgb: UInt32) {
    self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
  }
}

#if os(iOS)
  extension UIColor {
    convenience init(rgb: UInt32) {
      self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
  }
#endif
```

`Wait/Packages/WaitKit/Sources/DesignSystem/Spacing.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import CoreGraphics

/// 4-pt spacing scale. It replaces the legacy `Size` enum, which is deleted at the cutover.
public enum Spacing {
  public static let xxs: CGFloat = 2
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let xl: CGFloat = 24
  public static let xxl: CGFloat = 32
}
```

`Wait/Packages/WaitKit/Sources/DesignSystem/LadderStatus+Style.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

public extension LadderStatus {
  var tint: Color {
    switch self {
      case .deepBuy: Palette.stockUp
      case .buyZone: Palette.stockUp.opacity(0.85)
      case .watch: .gray
      case .atOrAboveFair: Palette.warning
      case .trim: .orange
      case .sell: Palette.stockDown
      case .noAnchors: .secondary
    }
  }

  var symbolName: String {
    switch self {
      case .deepBuy: "arrow.down.circle.fill"
      case .buyZone: "checkmark.circle.fill"
      case .watch: "eye"
      case .atOrAboveFair: "equal.circle"
      case .trim: "scissors"
      case .sell: "arrow.up.circle.fill"
      case .noAnchors: "questionmark.circle"
    }
  }
}

public extension TemperatureBand {
  var tint: Color {
    switch self {
      case .freezing: .blue
      case .cold: .teal
      case .neutral: .gray
      case .warm: .orange
      case .hot: .red
    }
  }
}
```

`Wait/Packages/WaitKit/Sources/DesignSystem/StatusPill.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

// MARK: - StatusPill

/// The ladder status as a tinted capsule. A nil status renders as "No Anchors".
public struct StatusPill: View {
  // MARK: Lifecycle

  public init(status: LadderStatus?, compact: Bool = false) {
    self.status = status ?? .noAnchors
    self.compact = compact
  }

  // MARK: Public

  public var body: some View {
    Group {
      if compact {
        Image(systemName: status.symbolName)
      } else {
        Label(status.title, systemImage: status.symbolName)
      }
    }
    .font(.caption.weight(.semibold))
    .padding(.horizontal, compact ? Spacing.xs : Spacing.s)
    .padding(.vertical, Spacing.xxs)
    .foregroundStyle(status.tint)
    .background(status.tint.opacity(0.15), in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.title)
  }

  // MARK: Private

  private let status: LadderStatus
  private let compact: Bool
}

#Preview {
  VStack(alignment: .leading) {
    ForEach(LadderStatus.allCases, id: \.self) { StatusPill(status: $0) }
    StatusPill(status: .buyZone, compact: true)
  }
  .padding()
}
```

`Wait/Packages/WaitKit/Sources/DesignSystem/TemperatureBadge.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

// MARK: - TemperatureBadge

/// The 0–100 ladder temperature, for example "27°", tinted by band.
public struct TemperatureBadge: View {
  // MARK: Lifecycle

  public init(temperature: Temperature?) {
    self.temperature = temperature
  }

  // MARK: Public

  public var body: some View {
    let tint = temperature?.band.tint ?? .secondary
    Text(Self.label(for: temperature))
      .font(.caption.monospacedDigit().weight(.semibold))
      .padding(.horizontal, Spacing.s)
      .padding(.vertical, Spacing.xxs)
      .foregroundStyle(tint)
      .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
      .accessibilityLabel(temperature.map { "Temperature \(Int($0.value.rounded())), \($0.band.title)" } ?? "No temperature")
  }

  public static func label(for temperature: Temperature?) -> String {
    temperature?.formatted ?? "—"
  }

  // MARK: Private

  private let temperature: Temperature?
}

#Preview {
  HStack {
    TemperatureBadge(temperature: Temperature(value: 8))
    TemperatureBadge(temperature: Temperature(value: 35))
    TemperatureBadge(temperature: Temperature(value: 55))
    TemperatureBadge(temperature: Temperature(value: 72))
    TemperatureBadge(temperature: Temperature(value: 91))
    TemperatureBadge(temperature: nil)
  }
  .padding()
}
```

- [ ] **Step 6: Run the tests and confirm they pass, then build the app**

Run: `scripts/test-waitkit.sh DesignSystemTests && scripts/build-app.sh`
Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`. Legacy code still compiles without the shadows.

- [ ] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/DesignSystem Wait/Packages/WaitKit/Tests/DesignSystemTests
git commit -m "feat(designsystem): semantic palette, spacing, status pill, temperature badge; drop Color.primary/orange shadows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 19: `ChecklistFeature` and `ChecklistTemplateFeature`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `ChecklistFeature` target and product, and `ChecklistFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistFeature.swift`, `ChecklistView.swift`, `ChecklistTemplateFeature.swift`, `ChecklistTemplateView.swift`
- Create: `Wait/Packages/WaitKit/Tests/ChecklistFeatureTests/ChecklistFeatureTests.swift`

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "ChecklistFeature", targets: ["ChecklistFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "ChecklistFeature",
      dependencies: [
        "Domain",
        "Persistence",
        "DesignSystem",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "ChecklistFeatureTests",
      dependencies: [
        "ChecklistFeature",
        "Domain",
        "Persistence",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistFeature.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/ChecklistFeatureTests/ChecklistFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import Persistence
import Testing

let now = Date(timeIntervalSince1970: 1_795_186_800)

func checklistItem() -> WatchlistItem {
  WatchlistItem(
    symbol: "AAPL",
    name: "Apple",
    checklist: [ChecklistItem(id: UUID(0), name: "A"), ChecklistItem(id: UUID(1), name: "B")],
    createdAt: .distantPast,
    updatedAt: .distantPast
  )
}

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct ChecklistFeatureTests {
  @Test func toggleStampsAndUpdatesTheTitle() async {
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: checklistItem()))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    #expect(store.state.title == "0 / 2")
    await store.send(.toggled(UUID(0))) {
      $0.$item.withLock {
        $0.checklist[0].isChecked = true
        $0.updatedAt = now
      }
    }
    #expect(store.state.title == "1 / 2")
    await store.send(.toggled(UUID(1))) {
      $0.$item.withLock { $0.checklist[1].isChecked = true }
    }
    #expect(store.state.title == "All Done")
  }

  @Test func unknownItemIsIgnored() async {
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: checklistItem()))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    await store.send(.toggled(UUID(9)))
  }

  @Test func resetUnchecksEverything() async {
    var item = checklistItem()
    item.checklist[0].isChecked = true
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: item))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    await store.send(.resetTapped) {
      $0.$item.withLock {
        $0.checklist[0].isChecked = false
        $0.updatedAt = now
      }
    }
  }

  @Test func templateAddRenameAndPrune() async {
    @Shared(.checklistTemplate) var template
    $template.withLock { $0 = [] }
    let store = TestStore(initialState: ChecklistTemplateFeature.State()) {
      ChecklistTemplateFeature()
    } withDependencies: {
      $0.uuid = .incrementing
    }
    await store.send(.addTapped) {
      $0.$items.withLock { _ = $0.insert(ChecklistItem(id: UUID(0), name: ""), at: 0) }
    }
    await store.send(.addTapped) {
      $0.$items.withLock { _ = $0.insert(ChecklistItem(id: UUID(1), name: ""), at: 0) }
    }
    await store.send(.nameChanged(UUID(0), "Wait 30 minutes")) {
      $0.$items.withLock { $0[id: UUID(0)]?.name = "Wait 30 minutes" }
    }
    await store.send(.onDisappear) {
      $0.$items.withLock { _ = $0.remove(id: UUID(1)) }
    }
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh ChecklistFeatureTests`
Expected FAIL: `error: cannot find 'ChecklistFeature' in scope`.

- [ ] **Step 4: Implement the reducers** (replace the header-only `ChecklistFeature.swift`)

`Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence

// MARK: - ChecklistFeature

/// The per-stock checklist. It mutates the shared `WatchlistItem`, so the list and details screens update too.
@Reducer
public struct ChecklistFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: Shared<WatchlistItem>) {
      _item = item
    }

    // MARK: Public

    @Shared public var item: WatchlistItem

    public var id: String {
      item.symbol
    }

    public var title: String {
      let total = item.checklist.count
      let done = item.checkedCount
      return total > 0 && done == total ? "All Done" : "\(done) / \(total)"
    }
  }

  public enum Action: Equatable {
    case toggled(ChecklistItem.ID)
    case resetTapped
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case let .toggled(id):
          guard state.item.checklist.contains(where: { $0.id == id }) else {
            return .none
          }
          state.$item.update(now: now) { item in
            if let index = item.checklist.firstIndex(where: { $0.id == id }) {
              item.checklist[index].isChecked.toggle()
            }
          }
          return .none

        case .resetTapped:
          state.$item.update(now: now) { item in
            for index in item.checklist.indices {
              item.checklist[index].isChecked = false
            }
          }
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.date.now) private var now
}
```

`Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistTemplateFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence

// MARK: - ChecklistTemplateFeature

/// Edits the template that seeds each newly added stock's checklist. It replaces the legacy `ChecklistEditFeature`.
@Reducer
public struct ChecklistTemplateFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    public init() {}

    @Shared(.checklistTemplate) public var items
  }

  public enum Action: Equatable {
    case addTapped
    case nameChanged(ChecklistItem.ID, String)
    case deleted(IndexSet)
    case moved(IndexSet, Int)
    case onDisappear
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .addTapped:
          let item = ChecklistItem(id: uuid(), name: "")
          state.$items.withLock { _ = $0.insert(item, at: 0) }
          return .none

        case let .nameChanged(id, name):
          state.$items.withLock { $0[id: id]?.name = name }
          return .none

        case let .deleted(offsets):
          state.$items.withLock { $0.remove(atOffsets: offsets) }
          return .none

        case let .moved(source, destination):
          state.$items.withLock { $0.move(fromOffsets: source, toOffset: destination) }
          return .none

        case .onDisappear:
          state.$items.withLock { items in
            items.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          }
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.uuid) private var uuid
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh ChecklistFeatureTests`
Expected PASS: 4 tests pass.

- [ ] **Step 6: Add the views.** Load `swiftui-expert:swiftui-expert-skill` first.

`Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - ChecklistView

public struct ChecklistView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      Section {
        ForEach(store.item.checklist) { entry in
          Button {
            store.send(.toggled(entry.id))
          } label: {
            HStack(spacing: Spacing.m) {
              Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isChecked ? Palette.accent : .secondary)
                .imageScale(.large)
              Text(entry.name)
                .foregroundStyle(entry.isChecked ? .secondary : .primary)
                .strikethrough(entry.isChecked)
                .multilineTextAlignment(.leading)
            }
          }
          .accessibilityAddTraits(entry.isChecked ? .isSelected : [])
        }
      } header: {
        Text(store.title)
      }
    }
    .navigationTitle("\(store.item.symbol) Checklist")
    .toolbar {
      Button("Reset") {
        store.send(.resetTapped)
      }
      .disabled(store.item.checkedCount == 0)
    }
  }

  // MARK: Private

  private let store: StoreOf<ChecklistFeature>
}
```

`Wait/Packages/WaitKit/Sources/ChecklistFeature/ChecklistTemplateView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - ChecklistTemplateView

public struct ChecklistTemplateView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistTemplateFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      Section {
        ForEach(store.items) { item in
          TextField(
            "Prompt",
            text: Binding(get: { item.name }, set: { store.send(.nameChanged(item.id, $0)) }),
            axis: .vertical
          )
        }
        .onDelete { store.send(.deleted($0)) }
        .onMove { store.send(.moved($0, $1)) }
      } footer: {
        Text("New stocks start with these prompts. Empty prompts are removed when you leave this screen.")
      }
    }
    .navigationTitle("Checklist Template")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { EditButton() }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.send(.addTapped)
        } label: {
          Label("Add prompt", systemImage: "plus")
        }
      }
    }
    .onDisappear { store.send(.onDisappear) }
  }

  // MARK: Private

  private let store: StoreOf<ChecklistTemplateFeature>
}

#Preview {
  NavigationStack {
    ChecklistTemplateView(store: Store(initialState: ChecklistTemplateFeature.State()) { ChecklistTemplateFeature() })
  }
}
```

- [ ] **Step 7: Build the package scheme so the views compile**

Run: `scripts/test-waitkit.sh ChecklistFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`. The views compile as part of the target.

- [ ] **Step 8: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/ChecklistFeature Wait/Packages/WaitKit/Tests/ChecklistFeatureTests
git commit -m "feat(checklist): TCA checklist and template features on shared watchlist state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 9: Stock chart

### Task 20: `StockChartFeature` and `ChartGeometry`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `StockChartFeature` target and product, and `StockChartFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/StockChartFeature/ChartGeometry.swift`, `Wait/Packages/WaitKit/Sources/StockChartFeature/StockChartFeature.swift`
- Create: `Wait/Packages/WaitKit/Tests/StockChartFeatureTests/ChartGeometryTests.swift`, `Wait/Packages/WaitKit/Tests/StockChartFeatureTests/StockChartFeatureTests.swift`

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "StockChartFeature", targets: ["StockChartFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "StockChartFeature",
      dependencies: [
        "Domain",
        "MarketDataClient",
        "DesignSystem",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "StockChartFeatureTests",
      dependencies: [
        "StockChartFeature",
        "Domain",
        "MarketDataClient",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/StockChartFeature/ChartGeometry.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/StockChartFeatureTests/ChartGeometryTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import StockChartFeature
import Testing

func points(_ closes: [String]) -> [PricePoint] {
  closes.enumerated().map { PricePoint(date: Date(timeIntervalSince1970: Double($0.offset) * 86400), close: Decimal(string: $0.element)!) }
}

@Suite struct ChartGeometryTests {
  @Test func emptyPointsHaveNoDomain() {
    // The legacy chart trapped here (Int.max) when it had no data.
    #expect(ChartGeometry.yDomain(points: [], rungs: [10]) == nil)
  }

  @Test func subDollarDomainIsTight() throws {
    let domain = try #require(ChartGeometry.yDomain(points: points(["0.5"]), rungs: []))
    #expect(abs(domain.lowerBound - 0.499) < 1e-9)
    #expect(abs(domain.upperBound - 0.501) < 1e-9)
  }

  @Test func nearbyRungsExtendTheDomainAndFarOnesDont() throws {
    let near = try #require(ChartGeometry.yDomain(points: points(["10", "12"]), rungs: [13]))
    #expect(abs(near.lowerBound - 9.7) < 1e-9)
    #expect(abs(near.upperBound - 13.3) < 1e-9)
    let far = try #require(ChartGeometry.yDomain(points: points(["10", "12"]), rungs: [30]))
    #expect(abs(far.lowerBound - 9.8) < 1e-9)
    #expect(abs(far.upperBound - 12.2) < 1e-9)
  }

  @Test func lowerBoundNeverGoesNegative() throws {
    let domain = try #require(ChartGeometry.yDomain(points: points(["1", "100"]), rungs: []))
    #expect(domain.lowerBound == 0)
  }

  @Test func nearestIndexClamps() {
    #expect(ChartGeometry.nearestIndex(7, count: 2) == 1)
    #expect(ChartGeometry.nearestIndex(-3, count: 2) == 0)
    #expect(ChartGeometry.nearestIndex(nil, count: 2) == nil)
    #expect(ChartGeometry.nearestIndex(0, count: 0) == nil)
  }

  @Test func trendAndChange() {
    #expect(ChartGeometry.trend(points(["10", "12"])) == .up)
    #expect(ChartGeometry.trend(points(["12", "10"])) == .down)
    #expect(ChartGeometry.changePercent(points(["10", "12"])) == 20)
    #expect(ChartGeometry.changePercent([]) == nil)
  }

  @Test func axisLabelIndices() {
    #expect(ChartGeometry.axisLabelIndices(count: 10) == [0, 3, 6, 9])
    #expect(ChartGeometry.axisLabelIndices(count: 3) == [0, 1, 2])
    #expect(ChartGeometry.axisLabelIndices(count: 0) == [])
  }
}
```

`Wait/Packages/WaitKit/Tests/StockChartFeatureTests/StockChartFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import StockChartFeature
import Testing

let chartDate = Date(timeIntervalSince1970: 1_795_186_800)
let oneYear = PriceSeries(symbol: "AAPL", range: .oneYear, points: points(["10", "12"]), asOf: chartDate)

@MainActor
@Suite struct StockChartFeatureTests {
  @Test func taskFetchesOnlyTheSelectedRange() async {
    let calls = LockIsolated<[String]>([])
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, range, policy in
        calls.withValue { $0.append("\(range.rawValue):\(policy)") }
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return oneYear
      }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
    #expect(calls.value == ["1Y:cacheOnly", "1Y:useCache"])
  }

  @Test func cachedSeriesShowsWhileStillLoading() async {
    let stale = oneYear.with(isStale: true)
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in policy == .cacheOnly ? stale : oneYear }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.cachedSeriesLoaded) { $0.series[.oneYear] = stale } // still loading
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
  }

  @Test func reselectingALoadedRangeMakesNoCall() async {
    var state = StockChartFeature.State(symbol: "AAPL")
    state.series[.oneYear] = oneYear
    let month = PriceSeries(symbol: "AAPL", range: .oneMonth, points: [], asOf: chartDate)
    let store = TestStore(initialState: state) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return month
      }
    }
    await store.send(.rangeSelected(.oneMonth)) {
      $0.range = .oneMonth
      $0.loading = [.oneMonth]
    }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneMonth] = month
    }
    await store.send(.rangeSelected(.oneYear)) { $0.range = .oneYear }
  }

  @Test func failureThenRetryReloads() async {
    let attempts = LockIsolated(0)
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        attempts.withValue { $0 += 1 }
        if attempts.value == 1 { throw MarketDataError.network("down") }
        #expect(policy == .reload)
        return oneYear
      }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.seriesFailed) {
      $0.loading = []
      $0.failed[.oneYear] = .network("down")
    }
    await store.send(.retryTapped) {
      $0.loading = [.oneYear]
      $0.failed = [:]
    }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
  }

  @Test func selectionSnapsToAValidIndex() async {
    var state = StockChartFeature.State(symbol: "AAPL")
    state.series[.oneYear] = oneYear
    let store = TestStore(initialState: state) { StockChartFeature() }
    await store.send(.selectionChanged(7)) { $0.selectedIndex = 1 }
    #expect(store.state.selectedPoint?.close == 12)
    await store.send(.selectionChanged(nil)) { $0.selectedIndex = nil }
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh StockChartFeatureTests`
Expected FAIL: `error: cannot find 'ChartGeometry' in scope` and `cannot find 'StockChartFeature' in scope`.

- [ ] **Step 4: Replace the contents of `ChartGeometry.swift` with the implementation**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - ChartTrend

public enum ChartTrend: Equatable, Sendable {
  case up
  case down
}

// MARK: - ChartGeometry

/// Pure chart math, kept separate from the view so it can be tested. The x-axis is ordinal: the point index, labeled with dates (overview D11).
public enum ChartGeometry {
  /// Nil for no points. Rungs within the closes −15%…+15% widen the domain. Padding is 10% of max(span, 2% of high, 0.0001). The lower bound is ≥ 0.
  public static func yDomain(points: [PricePoint], rungs: [Decimal]) -> ClosedRange<Double>? {
    let closes = points.map(\.close.doubleValue)
    guard let minClose = closes.min(), let maxClose = closes.max() else {
      return nil
    }
    let window = (minClose * 0.85) ... (maxClose * 1.15)
    var low = minClose
    var high = maxClose
    for rung in rungs.map(\.doubleValue) where window.contains(rung) {
      low = min(low, rung)
      high = max(high, rung)
    }
    let pad = max(high - low, high * 0.02, 0.0001) * 0.1
    return max(0, low - pad) ... (high + pad)
  }

  public static func nearestIndex(_ raw: Int?, count: Int) -> Int? {
    guard let raw, count > 0 else {
      return nil
    }
    return min(max(raw, 0), count - 1)
  }

  public static func trend(_ points: [PricePoint]) -> ChartTrend {
    guard let first = points.first, let last = points.last else {
      return .up
    }
    return last.close >= first.close ? .up : .down
  }

  /// Percent change from the first point to the last.
  public static func changePercent(_ points: [PricePoint]) -> Double? {
    guard let first = points.first, let last = points.last, first.close > 0 else {
      return nil
    }
    return ((last.close - first.close) / first.close * 100).doubleValue
  }

  public static func axisLabelIndices(count: Int, desired: Int = 4) -> [Int] {
    guard count > 0 else {
      return []
    }
    guard count > desired else {
      return Array(0 ..< count)
    }
    let step = Double(count - 1) / Double(desired - 1)
    return (0 ..< desired).map { Int((Double($0) * step).rounded()) }
  }
}
```

- [ ] **Step 5: Implement `StockChartFeature.swift`**
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient

// MARK: - StockChartFeature

/// Loads one range at a time: 1Y on appear, other ranges only when selected. The legacy screen fetched all five ranges on every visit.
@Reducer
public struct StockChartFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(symbol: String, range: ChartRange = .oneYear) {
      self.symbol = symbol
      self.range = range
    }

    // MARK: Public

    public let symbol: String
    public var range: ChartRange
    public var series: [ChartRange: PriceSeries] = [:]
    public var loading: Set<ChartRange> = []
    public var failed: [ChartRange: MarketDataError] = [:]
    public var selectedIndex: Int?

    public var points: [PricePoint] {
      series[range]?.points ?? []
    }

    public var selectedPoint: PricePoint? {
      guard let selectedIndex, points.indices.contains(selectedIndex) else {
        return nil
      }
      return points[selectedIndex]
    }
  }

  public enum Action {
    case task
    case rangeSelected(ChartRange)
    case retryTapped
    case selectionChanged(Int?)
    /// Cache-first result. It fills the chart but keeps `loading`, because the fresh request is still running.
    case cachedSeriesLoaded(ChartRange, PriceSeries)
    case seriesLoaded(ChartRange, PriceSeries)
    case seriesFailed(ChartRange, MarketDataError)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .task:
          return load(&state, range: state.range, policy: .useCache)

        case let .rangeSelected(range):
          state.range = range
          state.selectedIndex = nil
          guard state.series[range] == nil else {
            return .none
          }
          return load(&state, range: range, policy: .useCache)

        case .retryTapped:
          return load(&state, range: state.range, policy: .reload)

        case let .selectionChanged(raw):
          state.selectedIndex = ChartGeometry.nearestIndex(raw, count: state.points.count)
          return .none

        case let .cachedSeriesLoaded(range, series):
          state.series[range] = series
          return .none

        case let .seriesLoaded(range, series):
          state.loading.remove(range)
          state.failed[range] = nil
          state.series[range] = series
          return .none

        case let .seriesFailed(range, error):
          state.loading.remove(range)
          state.failed[range] = error
          return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID: Hashable {
    case load(ChartRange)
  }

  @Dependency(\.marketData) private var marketData

  /// For `.useCache`, cached data goes out first (`.cachedSeriesLoaded`), then the possibly network-backed result.
  private func load(_ state: inout State, range: ChartRange, policy: CachePolicy) -> Effect<Action> {
    guard !state.loading.contains(range) else {
      return .none
    }
    state.loading.insert(range)
    state.failed[range] = nil
    let symbol = state.symbol
    return .run { [marketData] send in
      if policy == .useCache, let cached = try? await marketData.series(symbol, range, .cacheOnly) {
        await send(.cachedSeriesLoaded(range, cached))
      }
      do {
        try await send(.seriesLoaded(range, marketData.series(symbol, range, policy)))
      } catch {
        try await send(.seriesFailed(range, MarketDataError(error))) // rethrows cancellation
      }
    }
    .cancellable(id: CancelID.load(range), cancelInFlight: true)
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh StockChartFeatureTests`
Expected PASS: 12 tests pass.

- [ ] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/StockChartFeature Wait/Packages/WaitKit/Tests/StockChartFeatureTests
git commit -m "feat(chart): StockChartFeature loads one range at a time; ChartGeometry fixes empty/sub-dollar domains

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 21: `StockChartView` (Swift Charts on iOS 17)

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/StockChartFeature/StockChartView.swift`

Load `swiftui-expert:swiftui-expert-skill`. The view takes the ladder as a parameter, because the rungs belong to the item, not to the chart state.

- [ ] **Step 1: Implement**

`Wait/Packages/WaitKit/Sources/StockChartFeature/StockChartView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - StockChartView

/// Contents:
/// - An ordinal x-axis labeled with dates.
/// - An area gradient under the line.
/// - Dashed ladder rungs. Derived rungs use a dot pattern.
/// - `chartXSelection` scrubbing.
/// - A segmented range picker.
public struct StockChartView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<StockChartFeature>, ladder: PriceLadder) {
    self.store = store
    self.ladder = ladder
  }

  // MARK: Public

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      header
      chart
        .frame(height: 220)
      Picker("Range", selection: Binding(get: { store.range }, set: { store.send(.rangeSelected($0)) })) {
        ForEach(ChartRange.allCases, id: \.self) { range in
          Text(range.title).tag(range)
        }
      }
      .pickerStyle(.segmented)
    }
    .task { await store.send(.task).finish() }
  }

  // MARK: Private

  private let store: StoreOf<StockChartFeature>
  private let ladder: PriceLadder

  @ViewBuilder private var header: some View {
    let points = store.points
    if let shown = store.selectedPoint ?? points.last {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(shown.close, format: .currency(code: "USD"))
          .font(.title2.monospacedDigit().weight(.semibold))
          .contentTransition(.numericText())
        HStack(spacing: Spacing.s) {
          if let change = ChartGeometry.changePercent(points) {
            Text(change / 100, format: .percent.precision(.fractionLength(2)))
              .foregroundStyle(Palette.change(change))
          }
          Text(store.selectedPoint.map { label(for: $0.date) } ?? store.range.title)
            .foregroundStyle(.secondary)
          if let delay = store.series[store.range]?.delayedMinutes {
            Text("Delayed \(delay) min").foregroundStyle(.secondary)
          }
          if store.series[store.range]?.isStale == true {
            Label("Cached", systemImage: "clock.arrow.circlepath").foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }
    } else {
      Text(store.symbol).font(.title2.weight(.semibold)).redacted(reason: .placeholder)
    }
  }

  @ViewBuilder private var chart: some View {
    let points = store.points
    let rungs = ladder.rungs
    if let domain = ChartGeometry.yDomain(points: points, rungs: rungs.map(\.price)) {
      let color = ChartGeometry.trend(points) == .up ? Palette.stockUp : Palette.stockDown
      Chart {
        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
          AreaMark(
            x: .value("Index", index),
            yStart: .value("Base", domain.lowerBound),
            yEnd: .value("Close", point.close.doubleValue)
          )
          .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
          .interpolationMethod(.monotone)

          LineMark(x: .value("Index", index), y: .value("Close", point.close.doubleValue))
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
        }

        ForEach(rungs.filter { domain.contains($0.price.doubleValue) }, id: \.rung) { rung in
          RuleMark(y: .value(rung.rung.title, rung.price.doubleValue))
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: rung.isDerived ? [2, 4] : [4, 4]))
            .annotation(position: .top, alignment: .leading) {
              Text(rung.isDerived ? "\(rung.rung.title) (derived)" : rung.rung.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }

        if let index = store.selectedIndex, let point = store.selectedPoint {
          RuleMark(x: .value("Selected", index))
            .foregroundStyle(.secondary.opacity(0.5))
          PointMark(x: .value("Selected", index), y: .value("Close", point.close.doubleValue))
            .foregroundStyle(color)
        }
      }
      .chartYScale(domain: domain)
      .chartXScale(domain: 0 ... max(points.count - 1, 1))
      .chartXAxis {
        AxisMarks(values: ChartGeometry.axisLabelIndices(count: points.count)) { value in
          AxisGridLine()
          AxisValueLabel {
            if let index = value.as(Int.self), points.indices.contains(index) {
              Text(label(for: points[index].date))
            }
          }
        }
      }
      .chartYAxis { AxisMarks(position: .trailing) }
      .chartXSelection(value: Binding(get: { store.selectedIndex }, set: { store.send(.selectionChanged($0)) }))
      .accessibilityLabel("\(store.symbol) price chart, \(store.range.title)")
    } else if store.loading.contains(store.range) {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ContentUnavailableView {
        Label("No chart data", systemImage: "chart.xyaxis.line")
      } description: {
        Text(store.failed[store.range]?.userMessage ?? "Nothing to show yet.")
      } actions: {
        Button("Retry") { store.send(.retryTapped) }
      }
    }
  }

  private func label(for date: Date) -> String {
    switch store.range {
      case .oneDay: date.formatted(.dateTime.hour().minute())
      case .oneWeek: date.formatted(.dateTime.weekday(.abbreviated).day())
      case .oneMonth: date.formatted(.dateTime.month(.abbreviated).day())
      case .oneYear: date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
      case .fiveYears: date.formatted(.dateTime.year())
    }
  }
}

#Preview {
  StockChartView(
    store: Store(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData = .previewValue
    },
    ladder: (try? PriceLadder(buyHigh: 106, fair: 118)) ?? .empty
  )
  .padding()
}
```

- [ ] **Step 2: Build the package so the view compiles**

Run: `scripts/test-waitkit.sh StockChartFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Check the preview by hand.** Open `StockChartView.swift` in Xcode and confirm:
  - The canvas shows a line with a gradient, "Buy high" and "Fair" dashed rules, and a segmented 1D–5Y picker.
  - Dragging across the chart moves the selection rule and updates the header price.

  If you're running without Xcode UI, skip this step; it's checked again in Task 29.

- [ ] **Step 4: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/StockChartFeature/StockChartView.swift
git commit -m "feat(chart): Swift Charts view with area gradient, ladder rungs and chartXSelection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 10: Ladder and notes editors

### Task 22: `LadderEditorFeature` and `NotesEditorFeature`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `StockDetailsFeature` target and product, and `StockDetailsFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/StockDetailsFeature/LadderEditorFeature.swift`, `LadderEditorView.swift`, `NotesEditorFeature.swift`, `NotesEditorView.swift`
- Create: `Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests/EditorFeatureTests.swift`

- [ ] **Step 1: Update `Package.swift`.** Plan 01 renamed the legacy module to `LegacyStockDetails`, so the name `StockDetailsFeature` is free.
  - Append to `products:`: `.library(name: "StockDetailsFeature", targets: ["StockDetailsFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "StockDetailsFeature",
      dependencies: [
        "Domain",
        "Persistence",
        "MarketDataClient",
        "StockChartFeature",
        "DesignSystem",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "StockDetailsFeatureTests",
      dependencies: [
        "StockDetailsFeature",
        "Domain",
        "MarketDataClient",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/StockDetailsFeature/LadderEditorFeature.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests/EditorFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import StockDetailsFeature
import Testing

let us = Locale(identifier: "en_US")

func dec(_ string: String) -> Decimal {
  Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@MainActor
@Suite struct EditorFeatureTests {
  @Test func invalidNumberBlocksSaving() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "abc"
    #expect(state.parsed == .failure(.invalidNumber(.buyHigh)))
    #expect(!state.canSave)
  }

  @Test func outOfOrderAnchors() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyLow = "120"
    state.buyHigh = "100"
    #expect(state.parsed == .failure(.ladder(.outOfOrder(lower: .buyLow, upper: .buyHigh))))
  }

  @Test func allFieldsEmptyClearsTheTargets() throws {
    // Product decision: an empty ladder is allowed and saves as "no targets" (status NO_ANCHORS).
    let state = LadderEditorFeature.State(symbol: "AAPL", ladder: try PriceLadder(buyHigh: 10), currentPrice: nil, locale: us)
    var cleared = state
    cleared.buyHigh = ""
    #expect(cleared.parsed == .success(.empty))
    #expect(cleared.canSave)
  }

  @Test func derivedFairHint() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "175"
    #expect(state.derivedFairHint == 250)
    state.trim = "300"
    #expect(state.derivedFairHint == nil)
  }

  @Test func prefillsFromAnExistingLadder() throws {
    let state = LadderEditorFeature.State(symbol: "AAPL", ladder: try PriceLadder(buyLow: 12, buyHigh: dec("16.5")), currentPrice: nil, locale: us)
    #expect(state.buyLow == "12")
    #expect(state.buyHigh == "16.5")
    #expect(state.fair.isEmpty)
  }

  @Test func saveEmitsTheLadderAndDismisses() async throws {
    let dismissed = LockIsolated(false)
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "175"
    let store = TestStore(initialState: state) {
      LadderEditorFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect { dismissed.setValue(true) }
    }
    await store.send(\.binding.buyLow, "150") { $0.buyLow = "150" }
    await store.send(.saveTapped)
    await store.receive(\.delegate.saved, try PriceLadder(buyLow: 150, buyHigh: 175))
    await store.finish()
    #expect(dismissed.value)
  }

  @Test func notesSaveEmitsTextAndDismisses() async {
    let dismissed = LockIsolated(false)
    let store = TestStore(initialState: NotesEditorFeature.State(text: "old")) {
      NotesEditorFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect { dismissed.setValue(true) }
    }
    await store.send(\.binding.text, "line 1\nline 2") { $0.text = "line 1\nline 2" }
    await store.send(.saveTapped)
    await store.receive(\.delegate.saved, "line 1\nline 2")
    await store.finish()
    #expect(dismissed.value)
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests`
Expected FAIL: `error: cannot find 'LadderEditorFeature' in scope`.

- [ ] **Step 4: Implement the reducers** (replace the header-only `LadderEditorFeature.swift`)

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/LadderEditorFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation

// MARK: - LadderInputError

public enum LadderInputError: Error, Equatable, Sendable {
  case invalidNumber(PriceLadder.Rung)
  case ladder(LadderValidationError)

  // MARK: Public

  public var message: String {
    switch self {
      case let .invalidNumber(rung): "\(rung.title) isn't a valid price."
      case let .ladder(.nonPositive(rung)): "\(rung.title) must be greater than 0."
      case let .ladder(.outOfOrder(lower, upper)): "\(upper.title) must be at least \(lower.title)."
    }
  }
}

// MARK: - LadderEditorFeature

/// Edits the five anchors as locale-aware decimal text. It replaces `StockExpectedPriceInputView`, which only accepted whole dollars.
/// Leaving every field empty is valid: it saves `PriceLadder.empty`, which clears the targets.
@Reducer
public struct LadderEditorFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(symbol: String, ladder: PriceLadder, currentPrice: Decimal?, locale: Locale = .autoupdatingCurrent) {
      self.symbol = symbol
      self.currentPrice = currentPrice
      self.locale = locale
      buyLow = PriceInput.format(ladder.buyLow, locale: locale)
      buyHigh = PriceInput.format(ladder.buyHigh, locale: locale)
      fair = PriceInput.format(ladder.fair, locale: locale)
      trim = PriceInput.format(ladder.trim, locale: locale)
      sell = PriceInput.format(ladder.sell, locale: locale)
    }

    // MARK: Public

    public let symbol: String
    public let currentPrice: Decimal?
    public let locale: Locale
    public var buyLow: String
    public var buyHigh: String
    public var fair: String
    public var trim: String
    public var sell: String

    public var parsed: Result<PriceLadder, LadderInputError> {
      var values: [PriceLadder.Rung: Decimal] = [:]
      let fields: [(PriceLadder.Rung, String)] = [(.buyLow, buyLow), (.buyHigh, buyHigh), (.fair, fair), (.trim, trim), (.sell, sell)]
      for (rung, text) in fields {
        guard let parsed = PriceInput.parse(text, locale: locale) else {
          return .failure(.invalidNumber(rung))
        }
        if let value = parsed {
          values[rung] = value
        }
      }
      // Swift 6 infers `any Error` for a plain do/catch, so state the typed-throws clause explicitly.
      do throws(LadderValidationError) {
        return try .success(PriceLadder(
          buyLow: values[.buyLow],
          buyHigh: values[.buyHigh],
          fair: values[.fair],
          trim: values[.trim],
          sell: values[.sell]
        ))
      } catch {
        return .failure(.ladder(error))
      }
    }

    public var derivedFairHint: Decimal? {
      guard case let .success(ladder) = parsed else {
        return nil
      }
      return ladder.derivedFair
    }

    public var canSave: Bool {
      if case .success = parsed { true } else { false }
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case saveTapped
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case saved(PriceLadder)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .binding, .delegate:
          return .none

        case .saveTapped:
          guard case let .success(ladder) = state.parsed else {
            return .none
          }
          return .run { [dismiss] send in
            await send(.delegate(.saved(ladder)))
            await dismiss()
          }

        case .cancelTapped:
          return .run { [dismiss] _ in await dismiss() }
      }
    }
  }

  // MARK: Private

  @Dependency(\.dismiss) private var dismiss
}
```

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/NotesEditorFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation

// MARK: - NotesEditorFeature

/// Edits the multi-line memo. It only ever emits the text, so saving a note can never touch the ladder (and saving a ladder can never touch the note).
@Reducer
public struct NotesEditorFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    public init(text: String) {
      self.text = text
    }

    public var text: String
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case saveTapped
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case saved(String)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .binding, .delegate:
          return .none

        case .saveTapped:
          let text = state.text
          return .run { [dismiss] send in
            await send(.delegate(.saved(text)))
            await dismiss()
          }

        case .cancelTapped:
          return .run { [dismiss] _ in await dismiss() }
      }
    }
  }

  // MARK: Private

  @Dependency(\.dismiss) private var dismiss
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests`
Expected PASS: 7 tests pass.

- [ ] **Step 6: Add the views** (`swiftui-expert:swiftui-expert-skill`)

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/LadderEditorView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - LadderEditorView

public struct LadderEditorView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<LadderEditorFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    Form {
      if let price = store.currentPrice {
        Section {
          LabeledContent("Current price") {
            Text(price, format: .currency(code: "USD"))
          }
        }
      }
      Section {
        row(.buyLow, text: $store.buyLow)
        row(.buyHigh, text: $store.buyHigh)
        row(.fair, text: $store.fair)
        row(.trim, text: $store.trim)
        row(.sell, text: $store.sell)
      } header: {
        Text("Price ladder")
      } footer: {
        footer
      }
    }
    .navigationTitle(store.symbol)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { store.send(.cancelTapped) }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { store.send(.saveTapped) }
          .disabled(!store.canSave)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<LadderEditorFeature>

  @ViewBuilder private var footer: some View {
    switch store.parsed {
      case let .success(ladder) where ladder.isEmpty:
        Text("All fields are empty. Saving clears this stock's targets.")
      case .success:
        if let hint = store.derivedFairHint {
          Text("Fair is derived as buy high ÷ 0.7 = \(hint.formatted(.currency(code: "USD"))).")
        } else {
          Text("Each price must be at least the one above it. Leave a field empty to skip it.")
        }
      case let .failure(error):
        Text(error.message).foregroundStyle(Palette.stockDown)
    }
  }

  private func row(_ rung: PriceLadder.Rung, text: Binding<String>) -> some View {
    LabeledContent(rung.title) {
      HStack(spacing: Spacing.xxs) {
        Text("$").foregroundStyle(.secondary)
        TextField("—", text: text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel(rung.title)
      }
    }
  }
}

#Preview {
  NavigationStack {
    LadderEditorView(store: Store(initialState: LadderEditorFeature.State(symbol: "AAPL", ladder: (try? PriceLadder(buyHigh: Decimal(string: "175"))) ?? .empty, currentPrice: Decimal(string: "189.98"))) {
      LadderEditorFeature()
    })
  }
}
```

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/NotesEditorView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - NotesEditorView

public struct NotesEditorView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<NotesEditorFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    Form {
      TextField("Write some notes…", text: $store.text, axis: .vertical)
        .lineLimit(6 ...)
    }
    .navigationTitle("Notes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { store.send(.cancelTapped) }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { store.send(.saveTapped) }
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<NotesEditorFeature>
}
```

- [ ] **Step 7: Compile**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/StockDetailsFeature Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests
git commit -m "feat(details): ladder and notes editor features with decimal input

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 11: Stock details

### Task 23: `StockDetailsFeature`, details view, stats and ladder history

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsFeature.swift`, `StockDetailsView.swift`, `StatsSection.swift`, `LadderHistoryView.swift`
- Create: `Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsFeatureTests.swift`

- [ ] **Step 1: Write the failing tests.** Two of them are regressions for legacy bugs. The legacy price editor rebuilt `Stock` without `memo`, so saving a price erased the note. The legacy star called `StockCache.removeStock`, so un-starring deleted the stock.

`Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests/StockDetailsFeatureTests.swift`:
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

let detailsNow = Date(timeIntervalSince1970: 1_795_186_800)

func detailsItem() -> WatchlistItem {
  WatchlistItem(symbol: "AAPL", name: "Apple", ladder: try! PriceLadder(buyHigh: 150), memo: "Keep me", createdAt: .distantPast, updatedAt: .distantPast)
}

@MainActor
@Suite struct StockDetailsFeatureTests {
  func makeStore(quotes: (@Sendable ([String], CachePolicy) async throws -> [Quote])? = nil) -> TestStoreOf<StockDetailsFeature> {
    TestStore(initialState: StockDetailsFeature.State(item: Shared(value: detailsItem()))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.date.now = detailsNow
      if let quotes {
        $0.marketData.quotes = quotes
      }
    }
  }

  @Test func savingALadderKeepsTheMemo() async throws {
    let store = makeStore()
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    let newLadder = try PriceLadder(buyHigh: 140, fair: 200)
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(newLadder)))))) {
      $0.$item.withLock {
        $0.ladder = newLadder
        $0.ladderHistory = [LadderRevision(date: detailsNow, ladder: newLadder)]
        $0.updatedAt = detailsNow
      }
    }
    #expect(store.state.item.memo == "Keep me")
  }

  @Test func savingAnUnchangedLadderDoesNothing() async throws {
    let store = makeStore()
    // Present first: `ifLet` reports an issue for a presented action when the destination is nil.
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(try PriceLadder(buyHigh: 150)))))))
  }

  @Test func editingInThePresentedEditorSavesDismissesAndKeepsTheMemo() async throws {
    let store = makeStore()
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    await store.send(.destination(.presented(.ladderEditor(.binding(.set(\.buyHigh, "140")))))) {
      $0.destination?.modify(\.ladderEditor) { $0.buyHigh = "140" }
    }
    await store.send(.destination(.presented(.ladderEditor(.saveTapped))))
    let ladder = try PriceLadder(buyHigh: 140)
    await store.receive(\.destination.presented.ladderEditor.delegate.saved, ladder) {
      $0.$item.withLock {
        $0.ladder = ladder
        $0.ladderHistory = [LadderRevision(date: detailsNow, ladder: ladder)]
        $0.updatedAt = detailsNow
      }
    }
    await store.receive(\.destination.dismiss) { $0.destination = nil }
    #expect(store.state.item.memo == "Keep me")
  }

  @Test func failedRefreshKeepsTheCachedQuote() async {
    let cached = Quote(symbol: "AAPL", price: 140, asOf: detailsNow, isStale: true)
    let store = makeStore { _, policy in
      if policy == .cacheOnly { return [cached] }
      throw MarketDataError.network("offline")
    }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = cached }
    await store.receive(\.quoteFailed)
    #expect(store.state.quote == cached)
  }

  @Test func starTogglesFavoriteAndNeverRemoves() async {
    let store = makeStore()
    await store.send(.favoriteTapped) {
      $0.$item.withLock {
        $0.isFavorite = true
        $0.updatedAt = detailsNow
      }
    }
    await store.send(.favoriteTapped) {
      $0.$item.withLock { $0.isFavorite = false }
    }
  }

  @Test func notesSaveOnlyTouchesTheMemo() async throws {
    let store = makeStore()
    await store.send(.editNotesTapped) {
      $0.destination = .notesEditor(NotesEditorFeature.State(text: "Keep me"))
    }
    await store.send(.destination(.presented(.notesEditor(.delegate(.saved("New\nnote")))))) {
      $0.$item.withLock {
        $0.memo = "New\nnote"
        $0.updatedAt = detailsNow
      }
    }
    #expect(store.state.item.ladder == (try PriceLadder(buyHigh: 150)))
  }

  @Test func deleteAsksForConfirmationThenDelegates() async {
    let store = makeStore()
    await store.send(.deleteTapped) {
      $0.alert = .confirmDelete(symbol: "AAPL")
    }
    await store.send(.alert(.presented(.confirmDelete))) {
      $0.alert = nil
    }
    await store.receive(\.delegate.deleteConfirmed, "AAPL")
  }

  @Test func checklistTapDelegates() async {
    let store = makeStore()
    await store.send(.checklistTapped)
    await store.receive(\.delegate.openChecklist, "AAPL")
  }

  @Test func taskLoadsTheQuoteAndDerivesTheStatus() async {
    let quote = Quote(symbol: "AAPL", price: 140, asOf: detailsNow)
    let store = makeStore { _, policy in
      if policy == .cacheOnly { throw MarketDataError.notCached }
      return [quote]
    }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = quote }
    #expect(store.state.status == .buyZone)
    #expect(store.state.temperature != nil)
  }

  @Test func historyTapShowsTheSheet() async {
    let store = makeStore()
    await store.send(.historyTapped) { $0.isShowingLadderHistory = true }
    await store.send(\.binding.isShowingLadderHistory, false) { $0.isShowingLadderHistory = false }
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests/StockDetailsFeatureTests`
Expected FAIL: `error: cannot find 'StockDetailsFeature' in scope`.

- [ ] **Step 3: Implement the reducer**

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockChartFeature

// MARK: - StockDetailsFeature

@Reducer
public struct StockDetailsFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Destination {
    case ladderEditor(LadderEditorFeature)
    case notesEditor(NotesEditorFeature)
  }

  @ObservableState
  public struct State: Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: Shared<WatchlistItem>, quote: Quote? = nil) {
      _item = item
      self.quote = quote
      chart = StockChartFeature.State(symbol: item.wrappedValue.symbol)
    }

    // MARK: Public

    @Shared public var item: WatchlistItem
    public var quote: Quote?
    public var chart: StockChartFeature.State
    public var isShowingLadderHistory = false
    @Presents public var destination: Destination.State?
    @Presents public var alert: AlertState<Action.Alert>?

    public var id: String {
      item.symbol
    }

    public var status: LadderStatus? {
      quote.map { item.ladder.status(at: $0.price) }
    }

    public var temperature: Temperature? {
      quote.flatMap { item.ladder.temperature(at: $0.price) }
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case quoteLoaded(Quote)
    case quoteFailed(MarketDataError)
    case chart(StockChartFeature.Action)
    case editLadderTapped
    case editNotesTapped
    case historyTapped
    case checklistTapped
    case favoriteTapped
    case deleteTapped
    case destination(PresentationAction<Destination.Action>)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)

    public enum Alert: Equatable, Sendable {
      case confirmDelete
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case openChecklist(symbol: String)
      case deleteConfirmed(symbol: String)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Scope(state: \.chart, action: \.chart) {
      StockChartFeature()
    }
    Reduce { state, action in
      switch action {
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
          }

        case let .quoteLoaded(quote):
          state.quote = quote
          return .none

        case .quoteFailed:
          return .none

        case .editLadderTapped:
          state.destination = .ladderEditor(LadderEditorFeature.State(symbol: state.item.symbol, ladder: state.item.ladder, currentPrice: state.quote?.price))
          return .none

        case .editNotesTapped:
          state.destination = .notesEditor(NotesEditorFeature.State(text: state.item.memo))
          return .none

        case .historyTapped:
          state.isShowingLadderHistory = true
          return .none

        case .checklistTapped:
          return .send(.delegate(.openChecklist(symbol: state.item.symbol)))

        case .favoriteTapped:
          state.$item.update(now: now) { $0.isFavorite.toggle() }
          return .none

        case .deleteTapped:
          state.alert = .confirmDelete(symbol: state.item.symbol)
          return .none

        case .alert(.presented(.confirmDelete)):
          return .send(.delegate(.deleteConfirmed(symbol: state.item.symbol)))

        case let .destination(.presented(.ladderEditor(.delegate(.saved(ladder))))):
          guard ladder != state.item.ladder else {
            return .none
          }
          let stamp = now
          state.$item.update(now: stamp) { item in
            item.ladder = ladder
            item.ladderHistory.append(LadderRevision(date: stamp.truncatedToMilliseconds, ladder: ladder))
            if item.ladderHistory.count > LadderRevision.maxCount {
              item.ladderHistory.removeFirst(item.ladderHistory.count - LadderRevision.maxCount)
            }
          }
          return .none

        case let .destination(.presented(.notesEditor(.delegate(.saved(text))))):
          state.$item.update(now: now) { $0.memo = text }
          return .none

        case .binding, .chart, .destination, .alert, .delegate:
          return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
    .ifLet(\.$alert, action: \.alert)
  }

  // MARK: Private

  @Dependency(\.date.now) private var now
  @Dependency(\.marketData) private var marketData
}

// MARK: - StockDetailsFeature.Destination.State + Equatable

extension StockDetailsFeature.Destination.State: Equatable {}

public extension AlertState where Action == StockDetailsFeature.Action.Alert {
  static func confirmDelete(symbol: String) -> Self {
    AlertState {
      TextState("Remove \(symbol)?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete) {
        TextState("Remove")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Its ladder, notes and checklist will be deleted.")
    }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests`
Expected PASS: 17 tests pass, counting the editor tests.

- [ ] **Step 5: Add the views** (`swiftui-expert:swiftui-expert-skill`)

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/StatsSection.swift`. Plan 04 adds a `profile` parameter for fundamentals.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - StatsSection

/// Quote-derived stats. The legacy screen showed Alpha Vantage OVERVIEW fundamentals, which are now Premium; plan 04 brings fundamentals back from the backend.
struct StatsSection: View {
  // MARK: Internal

  let quote: Quote?

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
          price("52W High", quote?.fiftyTwoWeekHigh)
          price("52W Low", quote?.fiftyTwoWeekLow)
        }
        GridRow {
          stat("Volume", quote?.volume.map { $0.formatted(.number.notation(.compactName)) })
          stat("Change", quote?.changePercent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) })
        }
      }
    }
  }

  // MARK: Private

  private func price(_ title: String, _ value: Decimal?) -> some View {
    stat(title, value.map { $0.formatted(.currency(code: "USD")) })
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

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/LadderHistoryView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import DesignSystem
import Domain
import SwiftUI

// MARK: - LadderHistoryView

struct LadderHistoryView: View {
  // MARK: Internal

  let history: [LadderRevision]

  var body: some View {
    List {
      let charted = history.filter { $0.ladder.buyHigh != nil }
      if charted.count > 1 {
        Section {
          Chart(Array(charted.enumerated()), id: \.offset) { _, revision in
            LineMark(x: .value("Date", revision.date), y: .value("Buy high", revision.ladder.buyHigh?.doubleValue ?? 0))
              .interpolationMethod(.stepEnd)
            PointMark(x: .value("Date", revision.date), y: .value("Buy high", revision.ladder.buyHigh?.doubleValue ?? 0))
          }
          .frame(height: 160)
        } header: {
          Text("Buy high over time")
        }
      }
      Section {
        ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, revision in
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(revision.date, format: .dateTime.year().month().day()).font(.subheadline.weight(.semibold))
            Text(summary(revision.ladder)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .overlay {
      if history.isEmpty {
        ContentUnavailableView("No history yet", systemImage: "clock")
      }
    }
    .navigationTitle("Ladder History")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }

  // MARK: Private

  @Environment(\.dismiss) private var dismiss

  private func summary(_ ladder: PriceLadder) -> String {
    ladder.rungs
      .filter { !$0.isDerived }
      .map { "\($0.rung.title) \($0.price.formatted(.currency(code: "USD")))" }
      .joined(separator: " · ")
  }
}
```

`Wait/Packages/WaitKit/Sources/StockDetailsFeature/StockDetailsView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import StockChartFeature
import SwiftUI

// MARK: - StockDetailsView

public struct StockDetailsView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<StockDetailsFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.l) {
        header
        card { StockChartView(store: store.scope(state: \.chart, action: \.chart), ladder: store.item.ladder) }
        card { ladderCard }
        card { StatsSection(quote: store.quote) }
        card { checklistRow }
        card { notesCard }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(store.item.symbol)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.send(.favoriteTapped)
        } label: {
          Label(store.item.isFavorite ? "Unfavorite" : "Favorite", systemImage: store.item.isFavorite ? "star.fill" : "star")
        }
        .tint(store.item.isFavorite ? Palette.warning : nil)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(role: .destructive) {
            store.send(.deleteTapped)
          } label: {
            Label("Remove from Watchlist", systemImage: "trash")
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
      }
    }
    .task { await store.send(.task).finish() }
    .sheet(item: $store.scope(state: \.destination?.ladderEditor, action: \.destination.ladderEditor)) { editor in
      NavigationStack { LadderEditorView(store: editor) }
        .presentationDetents([.medium, .large])
    }
    .sheet(item: $store.scope(state: \.destination?.notesEditor, action: \.destination.notesEditor)) { notes in
      NavigationStack { NotesEditorView(store: notes) }
    }
    .sheet(isPresented: $store.isShowingLadderHistory) {
      NavigationStack { LadderHistoryView(history: store.item.ladderHistory) }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  // MARK: Private

  @Bindable private var store: StoreOf<StockDetailsFeature>

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(store.item.name).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        if let quote = store.quote {
          Text(quote.price, format: .currency(code: "USD")).font(.largeTitle.weight(.bold).monospacedDigit())
          if let change = quote.changePercent {
            Text(change / 100, format: .percent.precision(.fractionLength(2))).foregroundStyle(Palette.change(change))
          }
        } else {
          Text("—").font(.largeTitle.weight(.bold))
        }
      }
      HStack(spacing: Spacing.s) {
        StatusPill(status: store.status)
        TemperatureBadge(temperature: store.temperature)
        if store.quote?.isStale == true {
          Label("Cached", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var ladderCard: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      HStack {
        Text("Ladder").font(.headline)
        Spacer()
        Button("History") { store.send(.historyTapped) }
          .disabled(store.item.ladderHistory.isEmpty)
        Button("Edit") { store.send(.editLadderTapped) }
      }
      if store.item.ladder.isEmpty {
        Text("Set a buy price to see the temperature.").foregroundStyle(.secondary)
      } else {
        ThermometerBar(value: store.temperature?.value)
        ForEach(store.item.ladder.rungs, id: \.rung) { rung in
          HStack {
            Text(rung.isDerived ? "\(rung.rung.title) (derived)" : rung.rung.title)
            Spacer()
            Text(rung.price, format: .currency(code: "USD")).monospacedDigit()
            if let price = store.quote?.price, price > 0 {
              Text(((rung.price - price) / price).doubleValue, format: .percent.precision(.fractionLength(1)))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
            }
          }
          .font(.subheadline)
        }
      }
    }
  }

  private var checklistRow: some View {
    Button {
      store.send(.checklistTapped)
    } label: {
      HStack {
        Label("Checklist", systemImage: "checklist")
        Spacer()
        Text("\(store.item.checkedCount) / \(store.item.checklist.count)").foregroundStyle(.secondary)
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
    }
    .buttonStyle(.plain)
  }

  private var notesCard: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      HStack {
        Text("Notes").font(.headline)
        Spacer()
        Button("Edit") { store.send(.editNotesTapped) }
      }
      Text(store.item.memo.isEmpty ? "No notes yet." : store.item.memo)
        .foregroundStyle(store.item.memo.isEmpty ? .secondary : .primary)
    }
  }

  private func card(@ViewBuilder _ content: () -> some View) -> some View {
    content()
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}

// MARK: - ThermometerBar

/// The 0–100 temperature as a gradient track with a marker.
struct ThermometerBar: View {
  let value: Double?

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(LinearGradient(colors: [.blue, .teal, .gray, .orange, .red], startPoint: .leading, endPoint: .trailing))
          .frame(height: 8)
        if let value {
          Circle()
            .fill(.background)
            .overlay(Circle().stroke(.primary, lineWidth: 2))
            .frame(width: 16, height: 16)
            .offset(x: max(0, min(1, value / 100)) * (proxy.size.width - 16))
        }
      }
      .frame(maxHeight: .infinity)
    }
    .frame(height: 16)
    .accessibilityElement()
    .accessibilityLabel(value.map { "Temperature \(Int($0.rounded())) of 100" } ?? "No temperature")
  }
}

#Preview {
  NavigationStack {
    StockDetailsView(store: Store(initialState: StockDetailsFeature.State(item: Shared(value: WatchlistItem(
      symbol: "AAPL",
      name: "Apple Inc",
      ladder: (try? PriceLadder(buyLow: 100, buyHigh: 115, fair: 140, trim: 180)) ?? .empty,
      memo: "Long term hold.\nRevisit after earnings.",
      checklist: ChecklistTemplate.defaultItems,
      createdAt: .now,
      updatedAt: .now
    )))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.marketData = .previewValue
    })
  }
}
```

- [ ] **Step 6: Compile and check the preview.** Run the tests (which also compiles the views), then open the preview.

Run: `scripts/test-waitkit.sh StockDetailsFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`.

The preview should show:
- The header with the price, a status pill and a temperature badge.
- The chart card.
- A ladder card with a thermometer and four rungs, each with its % distance.
- Stats, a "0 / 17" checklist row, and multi-line notes.

- [ ] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/StockDetailsFeature Wait/Packages/WaitKit/Tests/StockDetailsFeatureTests
git commit -m "feat(details): StockDetailsFeature with ladder card, stats, history; memo/star regressions fixed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 12: Add stock

### Task 24: `AddStockFeature` (search, then ladder)

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `WatchlistFeature` target and product, and `WatchlistFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/WatchlistFeature/AddStockFeature.swift`, `Wait/Packages/WaitKit/Sources/WatchlistFeature/AddStockView.swift`
- Create: `Wait/Packages/WaitKit/Tests/WatchlistFeatureTests/AddStockFeatureTests.swift`

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "WatchlistFeature", targets: ["WatchlistFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "WatchlistFeature",
      dependencies: [
        "Domain",
        "Persistence",
        "MarketDataClient",
        "StockDetailsFeature",
        "ChecklistFeature",
        "DesignSystem",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "WatchlistFeatureTests",
      dependencies: [
        "WatchlistFeature",
        "ChecklistFeature",
        "Domain",
        "MarketDataClient",
        "Persistence",
        "StockDetailsFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/WatchlistFeature/AddStockFeature.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/WatchlistFeatureTests/AddStockFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let addNow = Date(timeIntervalSince1970: 1_795_186_800)
let aapl = SymbolSearchResult(symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", type: "Common Stock")
let msft = SymbolSearchResult(symbol: "MSFT", name: "Microsoft", exchange: "NASDAQ", type: "Common Stock")

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AddStockFeatureTests {
  @Test func debounceSendsExactlyOneSearch() async {
    let clock = TestClock()
    let queries = LockIsolated<[String]>([])
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.marketData.search = { query in
        queries.withValue { $0.append(query) }
        return [aapl]
      }
    }
    await store.send(\.binding.query, "ap") {
      $0.query = "ap"
      $0.isSearching = true
    }
    await store.send(\.binding.query, "app") { $0.query = "app" }
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.searchLoaded) {
      $0.isSearching = false
      $0.results = [aapl]
    }
    #expect(queries.value == ["app"])
  }

  @Test func clearingTheQueryClearsResultsWithoutSearching() async {
    var state = AddStockFeature.State()
    state.query = "app"
    state.results = [aapl]
    let store = TestStore(initialState: state) { AddStockFeature() }
    await store.send(\.binding.query, "") {
      $0.query = ""
      $0.results = []
    }
  }

  @Test func alreadyAddedSymbolShowsANotice() async {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock { $0 = [WatchlistItem(symbol: "AAPL", name: "Apple", createdAt: .distantPast, updatedAt: .distantPast)] }
    let store = TestStore(initialState: AddStockFeature.State()) { AddStockFeature() }
    await store.send(.resultTapped(aapl)) {
      $0.errorMessage = "AAPL is already on your watchlist."
    }
  }

  @Test func savingTheLadderEmitsAnItemSeededFromTheTemplate() async throws {
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.date.now = addNow
      $0.uuid = .incrementing
    }
    await store.send(.resultTapped(msft)) {
      $0.pending = msft
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "MSFT", ladder: .empty, currentPrice: nil))
    }
    let ladder = try PriceLadder(buyHigh: 300)
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(ladder))))))
    let expected = WatchlistItem(
      symbol: "MSFT",
      name: "Microsoft",
      ladder: ladder,
      checklist: ChecklistTemplate.defaultItems.enumerated().map { ChecklistItem(id: UUID($0.offset), name: $0.element.name) },
      ladderHistory: [LadderRevision(date: addNow, ladder: ladder)],
      createdAt: addNow,
      updatedAt: addNow
    )
    await store.receive(\.delegate.added, expected)
  }

  @Test func searchFailureShowsAMessage() async {
    let clock = TestClock()
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.marketData.search = { _ in throw MarketDataError.rateLimited(retryAfter: nil) }
    }
    await store.send(\.binding.query, "x") {
      $0.query = "x"
      $0.isSearching = true
    }
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.searchFailed) {
      $0.isSearching = false
      $0.errorMessage = "Quotes delayed — rate limited"
    }
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests`
Expected FAIL: `error: cannot find 'AddStockFeature' in scope`.

- [ ] **Step 4: Implement** (replace the header-only `AddStockFeature.swift`)

`Wait/Packages/WaitKit/Sources/WatchlistFeature/AddStockFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature

// MARK: - AddStockFeature

/// Search is debounced 300 ms with the injected clock (the legacy code used `asyncAfter` for 1 s). Tapping a result opens the ladder editor, and saving emits `.delegate(.added)`.
@Reducer
public struct AddStockFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Destination {
    case ladderEditor(LadderEditorFeature)
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var query = ""
    public var results: [SymbolSearchResult] = []
    public var isSearching = false
    public var errorMessage: String?
    public var pending: SymbolSearchResult?
    @Presents public var destination: Destination.State?

    // MARK: Internal

    @SharedReader(.watchlist) var existing
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case searchLoaded(query: String, [SymbolSearchResult])
    case searchFailed(MarketDataError)
    case resultTapped(SymbolSearchResult)
    case cancelTapped
    case destination(PresentationAction<Destination.Action>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case added(WatchlistItem)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
      .onChange(of: \.query) { _, query in
        Reduce { state, _ in
          let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
          state.errorMessage = nil
          guard !trimmed.isEmpty else {
            state.results = []
            state.isSearching = false
            return .cancel(id: CancelID.search)
          }
          state.isSearching = true
          return .run { [clock, marketData] send in
            try await clock.sleep(for: .milliseconds(300))
            do {
              try await send(.searchLoaded(query: trimmed, marketData.search(trimmed)))
            } catch is CancellationError {
              return
            } catch {
              try await send(.searchFailed(MarketDataError(error)))
            }
          }
          .cancellable(id: CancelID.search, cancelInFlight: true)
        }
      }
    Reduce { state, action in
      switch action {
        case let .searchLoaded(query, results):
          guard query == state.query.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .none
          }
          state.isSearching = false
          state.results = results
          return .none

        case let .searchFailed(error):
          state.isSearching = false
          state.errorMessage = error.userMessage
          return .none

        case let .resultTapped(result):
          let symbol = result.symbol.uppercased()
          guard state.existing[id: symbol] == nil else {
            state.errorMessage = "\(symbol) is already on your watchlist."
            return .none
          }
          state.errorMessage = nil
          state.pending = result
          state.destination = .ladderEditor(LadderEditorFeature.State(symbol: symbol, ladder: .empty, currentPrice: nil))
          return .none

        case .cancelTapped:
          return .run { [dismiss] _ in await dismiss() }

        case let .destination(.presented(.ladderEditor(.delegate(.saved(ladder))))):
          guard let result = state.pending else {
            return .none
          }
          @SharedReader(.checklistTemplate) var template
          let stamp = now.truncatedToMilliseconds
          let item = WatchlistItem(
            symbol: result.symbol.uppercased(),
            name: result.name,
            ladder: ladder,
            checklist: template.map { ChecklistItem(id: uuid(), name: $0.name) },
            ladderHistory: ladder.isEmpty ? [] : [LadderRevision(date: stamp, ladder: ladder)],
            createdAt: stamp,
            updatedAt: stamp
          )
          return .send(.delegate(.added(item)))

        case .binding, .destination, .delegate:
          return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
  }

  // MARK: Private

  private enum CancelID {
    case search
  }

  @Dependency(\.continuousClock) private var clock
  @Dependency(\.date.now) private var now
  @Dependency(\.dismiss) private var dismiss
  @Dependency(\.marketData) private var marketData
  @Dependency(\.uuid) private var uuid
}

// MARK: - AddStockFeature.Destination.State + Equatable

extension AddStockFeature.Destination.State: Equatable {}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests`
Expected PASS: 5 tests pass.

- [ ] **Step 6: Add the view** (`swiftui-expert:swiftui-expert-skill`)

`Wait/Packages/WaitKit/Sources/WatchlistFeature/AddStockView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import StockDetailsFeature
import SwiftUI

// MARK: - AddStockView

public struct AddStockView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<AddStockFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack {
      List {
        if let message = store.errorMessage {
          Section {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
          }
        }
        ForEach(store.results) { result in
          Button {
            store.send(.resultTapped(result))
          } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text(result.symbol).font(.headline)
              Text(result.name).font(.subheadline).foregroundStyle(.secondary)
              if let exchange = result.exchange {
                Text(exchange).font(.caption).foregroundStyle(.tertiary)
              }
            }
            .foregroundStyle(.primary)
          }
        }
      }
      .overlay {
        if store.isSearching, store.results.isEmpty {
          ProgressView()
        } else if !store.query.isEmpty, !store.isSearching, store.results.isEmpty, store.errorMessage == nil {
          ContentUnavailableView.search(text: store.query)
        }
      }
      .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Symbol or company")
      .autocorrectionDisabled()
      .textInputAutocapitalization(.characters)
      .navigationTitle("Add Stock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.cancelTapped) }
        }
      }
      .navigationDestination(item: $store.scope(state: \.destination?.ladderEditor, action: \.destination.ladderEditor)) { editor in
        LadderEditorView(store: editor)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<AddStockFeature>
}
```

- [ ] **Step 7: Compile**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/WatchlistFeature Wait/Packages/WaitKit/Tests/WatchlistFeatureTests
git commit -m "feat(watchlist): AddStockFeature with clock-debounced search and ladder editor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Chunk 13: Watchlist and settings

### Task 25: `WatchlistFeature`, list view and rows

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistFeature.swift`, `Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistView.swift`, `Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistRow.swift`
- Create: `Wait/Packages/WaitKit/Tests/WatchlistFeatureTests/WatchlistFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

`Wait/Packages/WaitKit/Tests/WatchlistFeatureTests/WatchlistFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let listNow = Date(timeIntervalSince1970: 1_795_186_800)

func listItem(_ symbol: String, _ sortIndex: Int, favorite: Bool = false) -> WatchlistItem {
  WatchlistItem(symbol: symbol, name: symbol, ladder: try! PriceLadder(buyHigh: 100), isFavorite: favorite, sortIndex: sortIndex, createdAt: .distantPast, updatedAt: .distantPast)
}

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct WatchlistFeatureTests {
  func seed(_ items: [WatchlistItem]) {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock { $0 = IdentifiedArray(uniqueElements: items) }
  }

  @Test func loadsCachedThenFreshQuotes() async {
    seed([listItem("AAPL", 0)])
    let stale = Quote(symbol: "AAPL", price: 100, asOf: listNow, isStale: true)
    let fresh = Quote(symbol: "AAPL", price: 101, asOf: listNow)
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in policy == .cacheOnly ? [stale] : [fresh] }
    }
    await store.send(.task)
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": stale]
      $0.quotesStatus = .delayed("Showing cached prices")
    }
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": fresh]
      $0.quotesStatus = .idle
    }
  }

  @Test func rateLimitKeepsExistingQuotes() async {
    seed([listItem("AAPL", 0)])
    var state = WatchlistFeature.State()
    state.quotes = ["AAPL": Quote(symbol: "AAPL", price: 99, asOf: listNow)]
    let store = TestStore(initialState: state) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in
        throw policy == .cacheOnly ? MarketDataError.notCached : MarketDataError.rateLimited(retryAfter: .seconds(60))
      }
    }
    await store.send(.task)
    await store.receive(\.quotesFailed) {
      $0.quotesStatus = .delayed("Quotes delayed — rate limited")
    }
  }

  @Test func swipeDeleteRemovesTheItem() async {
    seed([listItem("AAPL", 0), listItem("MSFT", 1)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.deleteSwiped(symbol: "AAPL")) {
      $0.$items.withLock { _ = $0.remove(id: "AAPL") }
    }
  }

  @Test func favoriteSwipeTogglesAndStamps() async {
    seed([listItem("AAPL", 0)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.favoriteSwiped(symbol: "AAPL")) {
      $0.$items.withLock {
        $0[id: "AAPL"]?.isFavorite = true
        $0[id: "AAPL"]?.updatedAt = listNow
      }
    }
    #expect(store.state.favorites.map(\.symbol) == ["AAPL"])
    #expect(store.state.others.isEmpty)
  }

  @Test func reorderOnlyTouchesTheSection() async {
    seed([listItem("A", 0), listItem("B", 1), listItem("F", 2, favorite: true)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.moved(.others, from: IndexSet(integer: 1), to: 0)) {
      $0.$items.withLock {
        $0[id: "B"]?.sortIndex = 0
        $0[id: "B"]?.updatedAt = listNow
        $0[id: "A"]?.sortIndex = 1
        $0[id: "A"]?.updatedAt = listNow
      }
    }
  }

  @Test func rowTapPushesDetailsAndDetailsDelegatesNavigate() async {
    seed([listItem("AAPL", 0)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.rowTapped(symbol: "AAPL")) {
      $0.path.append(.details(StockDetailsFeature.State(item: Shared($0.$items[id: "AAPL"])!)))
    }
    await store.send(.path(.element(id: 0, action: .details(.delegate(.openChecklist(symbol: "AAPL")))))) {
      $0.path.append(.checklist(ChecklistFeature.State(item: Shared($0.$items[id: "AAPL"])!)))
    }
    await store.send(.path(.element(id: 0, action: .details(.delegate(.deleteConfirmed(symbol: "AAPL")))))) {
      $0.path.pop(from: 0)
      $0.$items.withLock { _ = $0.remove(id: "AAPL") }
    }
  }

  @Test func unknownSymbolDoesNotPush() {
    var state = WatchlistFeature.State()
    #expect(state.showDetails(symbol: "NOPE") == false)
    #expect(state.path.isEmpty)
  }

  @Test func addedStockIsAppendedAndTheSheetDismissed() async {
    seed([listItem("AAPL", 0)])
    var state = WatchlistFeature.State()
    state.destination = .addStock(AddStockFeature.State())
    let added = WatchlistItem(symbol: "MSFT", name: "Microsoft", createdAt: listNow, updatedAt: listNow)
    let quote = Quote(symbol: "MSFT", price: 300, asOf: listNow)
    let store = TestStore(initialState: state) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
      $0.marketData.quotes = { _, _ in [quote] }
    }
    await store.send(.destination(.presented(.addStock(.delegate(.added(added)))))) {
      var expected = added
      expected.sortIndex = 1
      $0.$items.withLock { $0.append(expected) }
      $0.destination = nil
    }
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["MSFT": quote]
    }
  }

  @Test func pullToRefreshRequestsSyncAndReloads() async {
    seed([listItem("AAPL", 0)])
    let fresh = Quote(symbol: "AAPL", price: 101, asOf: listNow)
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in
        #expect(policy == .reload)
        return [fresh]
      }
    }
    await store.send(.refreshPulled) { $0.quotesStatus = .refreshing }
    await store.receive(\.delegate.refreshRequested)
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": fresh]
      $0.quotesStatus = .idle
    }
  }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests/WatchlistFeatureTests`
Expected FAIL: `error: cannot find 'WatchlistFeature' in scope`.

- [ ] **Step 3: Implement the reducer**

`Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature

// MARK: - WatchlistFeature

/// The home screen: Favorites and Watchlist sections, pull-to-refresh, swipe to favorite or delete, and reordering.
/// Quotes are loaded `.cacheOnly`, then `.useCache`, so the list renders instantly and refetches only after the TTL.
@Reducer
public struct WatchlistFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Path {
    case details(StockDetailsFeature)
    case checklist(ChecklistFeature)
  }

  @Reducer
  public enum Destination {
    case addStock(AddStockFeature)
  }

  public enum QuotesStatus: Equatable, Sendable {
    case idle
    case refreshing
    case delayed(String)
  }

  /// What the widget/watch snapshot depends on. `AppFeature` publishes on every change (debounced).
  public struct SnapshotInputs: Equatable, Sendable {
    public var items: [WatchlistItem]
    public var quotes: [String: Quote]
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    @Shared(.watchlist) public var items
    public var quotes: [String: Quote] = [:]
    public var quotesStatus: QuotesStatus = .idle
    public var path = StackState<Path.State>()
    @Presents public var destination: Destination.State?

    public var favorites: [WatchlistItem] {
      items.filter(\.isFavorite).sorted { $0.sortIndex < $1.sortIndex }
    }

    public var others: [WatchlistItem] {
      items.filter { !$0.isFavorite }.sorted { $0.sortIndex < $1.sortIndex }
    }

    public var snapshotInputs: SnapshotInputs {
      SnapshotInputs(items: Array(items), quotes: quotes)
    }

    /// Pushes details for `symbol`, for row taps and deep links. Returns false for an unknown symbol.
    @discardableResult
    public mutating func showDetails(symbol: String) -> Bool {
      let symbol = symbol.uppercased()
      guard let item = Shared($items[id: symbol]) else {
        return false
      }
      path.append(.details(StockDetailsFeature.State(item: item, quote: quotes[symbol])))
      return true
    }
  }

  public enum Action {
    case task
    case sceneBecameActive
    case refreshPulled
    case quotesLoaded([Quote])
    case quotesFailed(MarketDataError)
    case addTapped
    case rowTapped(symbol: String)
    case deleteSwiped(symbol: String)
    case favoriteSwiped(symbol: String)
    case moved(WatchlistSection, from: IndexSet, to: Int)
    case path(StackActionOf<Path>)
    case destination(PresentationAction<Destination.Action>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      /// Pull-to-refresh. `AppFeature` ignores this in plan 02 and starts a sync in plan 05.
      case refreshRequested
    }
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .task:
          return loadQuotes(symbols: state.items.map(\.symbol), policies: [.cacheOnly, .useCache], id: .all)

        case .sceneBecameActive:
          return loadQuotes(symbols: state.items.map(\.symbol), policies: [.useCache], id: .all)

        case .refreshPulled:
          state.quotesStatus = .refreshing
          return .merge(
            .send(.delegate(.refreshRequested)),
            loadQuotes(symbols: state.items.map(\.symbol), policies: [.reload], id: .all)
          )

        case let .quotesLoaded(quotes):
          for quote in quotes {
            state.quotes[quote.symbol] = quote
          }
          state.quotesStatus = quotes.contains(where: \.isStale) ? .delayed("Showing cached prices") : .idle
          return .none

        case let .quotesFailed(error):
          state.quotesStatus = .delayed(error.userMessage)
          return .none

        case .addTapped:
          state.destination = .addStock(AddStockFeature.State())
          return .none

        case let .rowTapped(symbol):
          state.showDetails(symbol: symbol)
          return .none

        case let .deleteSwiped(symbol):
          state.$items.remove(symbol, now: now)
          state.quotes[symbol] = nil
          return .none

        case let .favoriteSwiped(symbol):
          state.$items.update(symbol, now: now) { $0.isFavorite.toggle() }
          return .none

        case let .moved(section, source, destination):
          state.$items.reorder(section: section, from: source, to: destination, now: now)
          return .none

        case let .path(.element(_, .details(.delegate(.openChecklist(symbol))))):
          guard let item = Shared(state.$items[id: symbol]) else {
            return .none
          }
          state.path.append(.checklist(ChecklistFeature.State(item: item)))
          return .none

        case let .path(.element(id, .details(.delegate(.deleteConfirmed(symbol))))):
          // Pop first, so the details screen never renders a removed item.
          state.path.pop(from: id)
          state.$items.remove(symbol, now: now)
          state.quotes[symbol] = nil
          return .none

        case let .destination(.presented(.addStock(.delegate(.added(item))))):
          state.$items.add(item, now: now)
          state.destination = nil
          return loadQuotes(symbols: [item.symbol], policies: [.useCache], id: .single(item.symbol))

        case .path, .destination, .delegate:
          return .none
      }
    }
    .forEach(\.path, action: \.path)
    .ifLet(\.$destination, action: \.destination)
  }

  // MARK: Private

  private enum CancelID: Hashable {
    case all
    case single(String)
  }

  @Dependency(\.date.now) private var now
  @Dependency(\.marketData) private var marketData

  /// `.notCached` from a `.cacheOnly` attempt is silent. Any other error reports `.quotesFailed`, and existing quotes are kept.
  private func loadQuotes(symbols: [String], policies: [CachePolicy], id: CancelID) -> Effect<Action> {
    guard !symbols.isEmpty else {
      return .none
    }
    return .run { [marketData] send in
      for policy in policies {
        do {
          try await send(.quotesLoaded(marketData.quotes(symbols, policy)))
        } catch {
          let mapped = try MarketDataError(error) // rethrows cancellation
          if mapped != .notCached {
            await send(.quotesFailed(mapped))
          }
        }
      }
    }
    .cancellable(id: id, cancelInFlight: true)
  }
}

// MARK: - WatchlistFeature.Path.State + Equatable

extension WatchlistFeature.Path.State: Equatable {}

// MARK: - WatchlistFeature.Destination.State + Equatable

extension WatchlistFeature.Destination.State: Equatable {}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests`
Expected PASS: 14 tests pass.

- [ ] **Step 5: Add the views** (`swiftui-expert:swiftui-expert-skill`)

`Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistRow.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchlistRow

struct WatchlistRow: View {
  // MARK: Internal

  let item: WatchlistItem
  let quote: Quote?

  var body: some View {
    HStack(spacing: Spacing.m) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xs) {
          Text(item.symbol).font(.headline)
          if item.isFavorite {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.warning)
          }
        }
        Text(item.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: Spacing.s)
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        if let quote {
          Text(quote.price, format: .currency(code: "USD")).font(.body.monospacedDigit())
          if let change = quote.changePercent {
            Text(change / 100, format: .percent.precision(.fractionLength(2)))
              .font(.caption.monospacedDigit())
              .foregroundStyle(Palette.change(change))
          }
        } else {
          Text("—").foregroundStyle(.secondary)
        }
      }
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        StatusPill(status: status, compact: true)
        TemperatureBadge(temperature: temperature)
      }
    }
    .foregroundStyle(.primary)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  // MARK: Private

  private var status: LadderStatus? {
    quote.map { item.ladder.status(at: $0.price) }
  }

  private var temperature: Temperature? {
    quote.flatMap { item.ladder.temperature(at: $0.price) }
  }
}
```

`Wait/Packages/WaitKit/Sources/WatchlistFeature/WatchlistView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DesignSystem
import Domain
import Persistence
import StockDetailsFeature
import SwiftUI

// MARK: - WatchlistView

public struct WatchlistView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<WatchlistFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      list
        .navigationTitle("Wait")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { EditButton() }
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              store.send(.addTapped)
            } label: {
              Label("Add stock", systemImage: "plus")
            }
          }
        }
        .sheet(item: $store.scope(state: \.destination?.addStock, action: \.destination.addStock)) { addStore in
          AddStockView(store: addStore)
        }
        .task { await store.send(.task).finish() }
    } destination: { store in
      switch store.case {
        case let .details(detailsStore):
          StockDetailsView(store: detailsStore)
        case let .checklist(checklistStore):
          ChecklistView(store: checklistStore)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<WatchlistFeature>

  private var list: some View {
    List {
      if case let .delayed(message) = store.quotesStatus {
        Section {
          Label(message, systemImage: "clock.badge.exclamationmark").font(.footnote).foregroundStyle(.secondary)
        }
      }
      if !store.favorites.isEmpty {
        Section("Favorites") { rows(store.favorites, section: .favorites) }
      }
      if !store.others.isEmpty {
        Section("Watchlist") { rows(store.others, section: .others) }
      }
    }
    .listStyle(.insetGrouped)
    .refreshable { await store.send(.refreshPulled).finish() }
    .overlay {
      if store.items.isEmpty {
        ContentUnavailableView {
          Label("No stocks yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
          Text("Add a stock and set the price you'd be happy to buy at.")
        } actions: {
          Button("Add Stock") { store.send(.addTapped) }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private func rows(_ items: [WatchlistItem], section: WatchlistSection) -> some View {
    ForEach(items) { item in
      Button {
        store.send(.rowTapped(symbol: item.symbol))
      } label: {
        WatchlistRow(item: item, quote: store.quotes[item.symbol])
      }
      .swipeActions(edge: .leading) {
        Button {
          store.send(.favoriteSwiped(symbol: item.symbol))
        } label: {
          Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
        }
        .tint(Palette.warning)
      }
      .swipeActions(edge: .trailing) {
        Button(role: .destructive) {
          store.send(.deleteSwiped(symbol: item.symbol))
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
    .onMove { store.send(.moved(section, from: $0, to: $1)) }
  }
}

#Preview {
  WatchlistView(store: Store(initialState: WatchlistFeature.State()) {
    WatchlistFeature()
  } withDependencies: {
    $0.marketData = .previewValue
  })
}
```

- [ ] **Step 6: Compile**

Run: `scripts/test-waitkit.sh WatchlistFeatureTests`
Expected PASS: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**
```bash
git add Wait/Packages/WaitKit/Sources/WatchlistFeature Wait/Packages/WaitKit/Tests/WatchlistFeatureTests
git commit -m "feat(watchlist): WatchlistFeature with favorites, swipes, reorder, refresh and stack navigation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 26: `SettingsFeature`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `SettingsFeature` target and product, and `SettingsFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`, `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`
- Create: `Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsFeatureTests.swift`

The legacy `SettingsTab.SettingsView` (body `Text("haha")`) stays compiled until the cutover. The new type has the same name but lives in a different module, and no file imports both.

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "SettingsFeature", targets: ["SettingsFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "SettingsFeature",
      dependencies: [
        "ChecklistFeature",
        "DesignSystem",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "SettingsFeatureTests",
      dependencies: [
        "SettingsFeature",
        "ChecklistFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing test**

`Wait/Packages/WaitKit/Tests/SettingsFeatureTests/SettingsFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import SettingsFeature
import Testing

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SettingsFeatureTests {
  @Test func templateRowPushesTheEditor() async {
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "2.0 (1)")) { SettingsFeature() }
    await store.send(.checklistTemplateTapped) {
      $0.path.append(.checklistTemplate(ChecklistTemplateFeature.State()))
    }
  }

  @Test func appVersionFormatting() {
    #expect(SettingsFeature.State.versionString(info: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "7"]) == "2.0 (7)")
    #expect(SettingsFeature.State.versionString(info: nil) == "? (?)")
  }
}
```

- [ ] **Step 3: Run the test and confirm it fails**

Run: `scripts/test-waitkit.sh SettingsFeatureTests`
Expected FAIL: `error: cannot find 'SettingsFeature' in scope`.

- [ ] **Step 4: Implement**

`Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsFeature.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import Foundation

// MARK: - SettingsFeature

/// Plan 02 scope: the checklist template editor and the app version. Plans 04/05/06 add account, sync and alerts sections (overview §12.3).
@Reducer
public struct SettingsFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Path {
    case checklistTemplate(ChecklistTemplateFeature)
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(appVersion: String = State.versionString(info: Bundle.main.infoDictionary)) {
      self.appVersion = appVersion
    }

    // MARK: Public

    public var path = StackState<Path.State>()
    public var appVersion: String

    public static func versionString(info: [String: Any]?) -> String {
      let version = info?["CFBundleShortVersionString"] as? String ?? "?"
      let build = info?["CFBundleVersion"] as? String ?? "?"
      return "\(version) (\(build))"
    }
  }

  public enum Action {
    case checklistTemplateTapped
    case path(StackActionOf<Path>)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .checklistTemplateTapped:
          state.path.append(.checklistTemplate(ChecklistTemplateFeature.State()))
          return .none

        case .path:
          return .none
      }
    }
    .forEach(\.path, action: \.path)
  }
}

// MARK: - SettingsFeature.Path.State + Equatable

extension SettingsFeature.Path.State: Equatable {}
```

`Wait/Packages/WaitKit/Sources/SettingsFeature/SettingsView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

// MARK: - SettingsView

public struct SettingsView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      Form {
        Section("Checklist") {
          Button {
            store.send(.checklistTemplateTapped)
          } label: {
            LabeledContent {
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            } label: {
              Label("Checklist template", systemImage: "checklist")
            }
          }
          .foregroundStyle(.primary)
        }
        Section {
          LabeledContent("Version", value: store.appVersion)
        } header: {
          Text("About")
        } footer: {
          Text("Data: Twelve Data (temporary). Prices may be delayed. Not investment advice.")
        }
      }
      .navigationTitle("Settings")
    } destination: { store in
      switch store.case {
        case let .checklistTemplate(templateStore):
          ChecklistTemplateView(store: templateStore)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<SettingsFeature>
}

#Preview {
  SettingsView(store: Store(initialState: SettingsFeature.State()) { SettingsFeature() })
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh SettingsFeatureTests`
Expected PASS: 2 tests pass.

- [ ] **Step 6: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/SettingsFeature Wait/Packages/WaitKit/Tests/SettingsFeatureTests
git commit -m "feat(settings): SettingsFeature with reachable checklist template editor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 14: App root and widget

### Task 27: `AppFeature`, `DeepLink`, `AppDelegate`, new `WaitApp`, and the `wait://` scheme

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (add the `AppFeature` target and product, and `AppFeatureTests`)
- Create: `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`, `AppView.swift`, `DeepLink.swift`, `AppDelegateAction.swift`, `AppDelegate.swift`
- Create: `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureTests.swift`
- Modify: `Wait/Wait/WaitApp.swift` (full rewrite)
- Modify: `Wait/Wait/Info.plist` (add the URL scheme)
- Modify: `Wait/project.yml` (the app target gains the `AppFeature` product)

- [ ] **Step 1: Update `Package.swift`**
  - Append to `products:`: `.library(name: "AppFeature", targets: ["AppFeature"]),`
  - Append to `targets:`:
    ```swift
    .target(
      name: "AppFeature",
      dependencies: [
        "Domain",
        "DesignSystem",
        "Logging",
        "Persistence",
        "SettingsFeature",
        "WatchlistFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .testTarget(
      name: "AppFeatureTests",
      dependencies: [
        "AppFeature",
        "Domain",
        "MarketDataClient",
        "Persistence",
        "StockDetailsFeature",
        "WatchlistFeature",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    ```
  - Create `Wait/Packages/WaitKit/Sources/AppFeature/DeepLink.swift` containing only the file header, so the package loads (SwiftPM rejects a target with no sources). Step 4 fills it in.

- [ ] **Step 2: Write the failing tests**

`Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureTests.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import AppFeature
import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let appNow = Date(timeIntervalSince1970: 1_795_186_800)

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AppFeatureTests {
  func seedAAPL() {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock {
      $0 = [WatchlistItem(symbol: "AAPL", name: "Apple", ladder: try! PriceLadder(buyHigh: 100), createdAt: appNow, updatedAt: appNow)]
    }
  }

  @Test func deepLinkParsing() {
    #expect(DeepLink(url: URL(string: "wait://stock/aapl")!) == .stock("AAPL"))
    #expect(DeepLink(url: URL(string: "wait://stock/BRK.B")!) == .stock("BRK.B"))
    #expect(DeepLink(url: URL(string: "wait://stock/0700.HK")!) == .stock("0700.HK"))
    #expect(DeepLink(url: URL(string: "wait://other/AAPL")!) == nil)
    #expect(DeepLink(url: URL(string: "https://stock/AAPL")!) == nil)
    #expect(DeepLink(url: URL(string: "wait://stock/")!) == nil)
    #expect(DeepLink.stock("AAPL").url.absoluteString == "wait://stock/AAPL")
  }

  @Test func didFinishLaunchingPublishesASnapshot() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.appDelegate(.didFinishLaunching))
    await clock.advance(by: .seconds(1))
    #expect(published.value.map { $0.rows.map(\.symbol) } == [["AAPL"]])
  }

  @Test func openURLSelectsTheWatchlistAndPushesDetails() async {
    seedAAPL()
    var state = AppFeature.State()
    state.selectedTab = .settings
    let store = TestStore(initialState: state) { AppFeature() }
    await store.send(.openURL(URL(string: "wait://stock/AAPL")!)) {
      $0.selectedTab = .watchlist
      $0.watchlist.path.append(.details(StockDetailsFeature.State(item: Shared($0.watchlist.$items[id: "AAPL"])!)))
    }
  }

  @Test func unknownDeepLinkSymbolOnlySwitchesTabs() async {
    seedAAPL()
    var state = AppFeature.State()
    state.selectedTab = .settings
    let store = TestStore(initialState: state) { AppFeature() }
    await store.send(.openURL(URL(string: "wait://stock/NOPE")!)) {
      $0.selectedTab = .watchlist
    }
  }

  @Test func becomingActiveRefreshesQuotesAndPublishesOneSnapshot() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let quote = Quote(symbol: "AAPL", price: 90, asOf: appNow)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.marketData.quotes = { _, _ in [quote] }
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.scenePhaseChanged(.active))
    await store.receive(\.watchlist.sceneBecameActive)
    await store.receive(\.watchlist.quotesLoaded) {
      $0.watchlist.quotes = ["AAPL": quote]
    }
    await clock.advance(by: .seconds(1))
    #expect(published.value.count == 1)
    #expect(published.value.first?.rows.first?.status == .buyZone)
  }

  @Test func burstsOfChangesPublishOnce() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let first = Quote(symbol: "AAPL", price: 90, asOf: appNow)
    let second = Quote(symbol: "AAPL", price: 120, asOf: appNow)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.watchlist(.quotesLoaded([first]))) { $0.watchlist.quotes = ["AAPL": first] }
    await clock.advance(by: .milliseconds(500))
    await store.send(.watchlist(.quotesLoaded([second]))) { $0.watchlist.quotes = ["AAPL": second] }
    await clock.advance(by: .seconds(1))
    #expect(published.value.count == 1)
    #expect(published.value.first?.rows.first?.price == 120)
  }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test-waitkit.sh AppFeatureTests`
Expected FAIL: `error: cannot find 'DeepLink' in scope` and `cannot find 'AppFeature' in scope`.

- [ ] **Step 4: Implement `DeepLink.swift` (replacing the header-only file) and `AppDelegateAction.swift`**

`Wait/Packages/WaitKit/Sources/AppFeature/DeepLink.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DeepLink

/// `wait://stock/<SYMBOL>` (overview §9). It's used by widget rows and, in plan 06, by push notifications.
public enum DeepLink: Equatable, Sendable {
  case stock(String)

  // MARK: Lifecycle

  public init?(url: URL) {
    guard url.scheme == "wait", url.host() == "stock" else {
      return nil
    }
    let symbol = url.pathComponents.dropFirst().first?.uppercased() ?? ""
    // Letters and digits plus an exchange suffix: AAPL, BRK.B, 0700.HK.
    guard symbol.range(of: #"^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$"#, options: .regularExpression) != nil else {
      return nil
    }
    self = .stock(symbol)
  }

  // MARK: Public

  public var url: URL {
    switch self {
      case let .stock(symbol): URL(string: "wait://stock/\(symbol)")!
    }
  }
}
```

`Wait/Packages/WaitKit/Sources/AppFeature/AppDelegateAction.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

/// UIApplicationDelegate callbacks forwarded into the store. Plan 06 adds the remote-notification registration cases.
public enum AppDelegateAction: Equatable, Sendable {
  case didFinishLaunching
}
```

- [ ] **Step 5: Implement `AppFeature.swift`.**

The whole composition is wrapped in `CombineReducers`, and `.onChange(of: \.watchlist.snapshotInputs)` is attached outside it. That matters: `onChange` only sees mutations made by the reducer it wraps (overview §12.3). Attached to the inner `Reduce`, it would never see the watchlist child's changes. Plan 05 appends a second `.onChange` (the sync debounce on `\.watchlist.items`) to the same `CombineReducers`.

The single `snapshotClient.publish(` call site is in `publishSnapshot(_:)`. It's the debounced effect with `CancelID.publishSnapshot`, used both on launch and on every change. Plan 03 adds `connectivity.send` next to it.
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence
import SettingsFeature
import SwiftUI
import WatchlistFeature

// MARK: - AppFeature

@Reducer
public struct AppFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public enum Tab: Hashable, Sendable {
    case watchlist
    case settings
  }

  @ObservableState
  public struct State: Equatable {
    public init() {}

    public var selectedTab: Tab = .watchlist
    public var watchlist = WatchlistFeature.State()
    public var settings = SettingsFeature.State()
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case scenePhaseChanged(ScenePhase)
    case openURL(URL)
    case appDelegate(AppDelegateAction)
    case watchlist(WatchlistFeature.Action)
    case settings(SettingsFeature.Action)
  }

  public enum CancelID: Hashable, Sendable {
    case publishSnapshot
  }

  public var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Scope(state: \.watchlist, action: \.watchlist) {
        WatchlistFeature()
      }
      Scope(state: \.settings, action: \.settings) {
        SettingsFeature()
      }
      Reduce { state, action in
        switch action {
          case .appDelegate(.didFinishLaunching):
            // Publish once on launch, so the widget has data even before any quote changes.
            return publishSnapshot(state.watchlist.snapshotInputs)

          case let .scenePhaseChanged(phase):
            switch phase {
              case .active:
                return .send(.watchlist(.sceneBecameActive))
              case .background:
                // `@Shared(.fileStorage)` throttles writes, so flush them before the app is suspended (overview risk 5).
                @Shared(.checklistTemplate) var template
                return .run { [items = state.watchlist.$items, template = $template] _ in
                  try await items.save()
                  try await template.save()
                }
              default:
                return .none
            }

          case let .openURL(url):
            guard let link = DeepLink(url: url) else {
              return .none
            }
            switch link {
              case let .stock(symbol):
                state.selectedTab = .watchlist
                state.watchlist.destination = nil
                state.watchlist.path.removeAll()
                state.watchlist.showDetails(symbol: symbol)
            }
            return .none

          case .binding, .watchlist, .settings:
            return .none
        }
      }
    }
    .onChange(of: \.watchlist.snapshotInputs) { _, inputs in
      Reduce { _, _ in
        publishSnapshot(inputs)
      }
    }
  }

  // MARK: Internal

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date) var date
  @Dependency(\.snapshotClient) var snapshotClient

  // MARK: Private

  /// The only `snapshotClient.publish` call site: debounced 1 s and cancellable by `CancelID.publishSnapshot`.
  private func publishSnapshot(_ inputs: WatchlistFeature.SnapshotInputs) -> Effect<Action> {
    .run { [clock, date, snapshotClient] _ in
      try await clock.sleep(for: .seconds(1))
      await snapshotClient.publish(WatchlistSnapshot.make(items: inputs.items, quotes: inputs.quotes, now: date.now))
    }
    .cancellable(id: CancelID.publishSnapshot, cancelInFlight: true)
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `scripts/test-waitkit.sh AppFeatureTests`
Expected PASS: 6 tests pass.

- [ ] **Step 7: Implement `AppView.swift` and `AppDelegate.swift`** (`swiftui-expert:swiftui-expert-skill`)

`Wait/Packages/WaitKit/Sources/AppFeature/AppView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import SettingsFeature
import SwiftUI
import WatchlistFeature

// MARK: - AppView

public struct AppView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    TabView(selection: $store.selectedTab) {
      WatchlistView(store: store.scope(state: \.watchlist, action: \.watchlist))
        .tabItem { Label("Watchlist", systemImage: "list.bullet.rectangle") }
        .tag(AppFeature.Tab.watchlist)
      SettingsView(store: store.scope(state: \.settings, action: \.settings))
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(AppFeature.Tab.settings)
    }
    .tint(Palette.accent)
    .onOpenURL { store.send(.openURL($0)) }
    .onChange(of: scenePhase) { _, phase in
      store.send(.scenePhaseChanged(phase))
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<AppFeature>
  @Environment(\.scenePhase) private var scenePhase
}
```

`Wait/Packages/WaitKit/Sources/AppFeature/AppDelegate.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

#if os(iOS)
  import ComposableArchitecture
  import Logging
  import Persistence
  import UIKit

  // MARK: - AppDelegate

  /// Owns the root store. `@UIApplicationDelegateAdaptor` creates it before the `App` body runs, so the legacy migration runs inside the lazy store initializer, before any `@Shared(.watchlist)` is read (overview risk 26).
  @MainActor
  public final class AppDelegate: NSObject, UIApplicationDelegate {
    public lazy var store: StoreOf<AppFeature> = {
      do {
        let report = try LegacyMigration.live.runIfNeeded(now: Date())
        if report.didRun {
          Log.persistence.info("Legacy migration: \(report.migratedItems) items, template migrated: \(report.migratedTemplate)")
        }
      } catch {
        Log.persistence.error("Legacy migration failed (will retry next launch): \(error)")
      }
      return Store(initialState: AppFeature.State()) {
        AppFeature()
      }
    }()

    public func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      store.send(.appDelegate(.didFinishLaunching))
      return true
    }
  }
#endif
```

- [ ] **Step 8: Rewrite the app entry point.** Replace the entire contents of `Wait/Wait/WaitApp.swift`:
```swift
//
// Created by: kai_chen on 5/4/21.
// Copyright © 2021 Wait. All rights reserved.
//

import AppFeature
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      AppView(store: appDelegate.store)
    }
  }
}
```

- [ ] **Step 9: Register the `wait://` URL scheme in the app's Info.plist**

Run:
```sh
cd "$(git rev-parse --show-toplevel)/Wait" && /usr/libexec/PlistBuddy \
  -c "Add :CFBundleURLTypes array" \
  -c "Add :CFBundleURLTypes:0 dict" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.chenkai.wait" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string wait" \
  Wait/Info.plist && /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" Wait/Info.plist
```
Expected: `Array {` / `wait` / `}`.

- [ ] **Step 10: Link the `AppFeature` product in `project.yml`.** In the `Wait` target's `dependencies:`, add `- package: WaitKit` with `product: AppFeature`. The legacy products stay until the cutover. Then regenerate and build:

Run: `cd "$(git rev-parse --show-toplevel)/Wait" && xcodegen generate && cd .. && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`

Run: `R="$(git rev-parse --show-toplevel)"; test -f "$R/Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" && echo "Package.resolved present"; git -C "$R" status --short Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
Expected: `Package.resolved present`, and never a ` D` status line.

- [ ] **Step 11: Manual simulator check, including the legacy migration.** Run:
```sh
ROOT="$(git rev-parse --show-toplevel)"
BUILT=$(xcodebuild -project "$ROOT/Wait/Wait.xcodeproj" -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl uninstall booted com.chenkai.wait
xcrun simctl install booted "$BUILT/Wait.app"
DATA=$(xcrun simctl get_app_container booted com.chenkai.wait data)
cp "$ROOT/Wait/Packages/WaitKit/Tests/DomainTests/Fixtures/legacy-stocks.json" "$DATA/Documents/stocks"
xcrun simctl launch booted com.chenkai.wait
```
The simulator should show:
- The Watchlist tab with **AAPL, BABA and ZERO**. The duplicate and the `Empty` placeholder are gone.
- The temperature badges and status pills fill in as quotes arrive. ZERO shows "No Anchors".
- Tapping AAPL shows the note "Long term / hold".
- Changing the ladder keeps the note.
- The star toggles favorite and moves AAPL into Favorites without removing it.

Also run `xcrun simctl openurl booted wait://stock/BABA`. It should open BABA's details.

- [ ] **Step 12: Commit**
```bash
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/AppFeature Wait/Packages/WaitKit/Tests/AppFeatureTests Wait/Wait/WaitApp.swift Wait/Wait/Info.plist Wait/project.yml Wait/Wait.xcodeproj
git commit -m "feat(app): AppFeature root with tabs, deep links, scene phase refresh and debounced snapshot publishing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 28: Widget rewrite on the app-group snapshot

**Files:**
- Modify: `Wait/WaitWidget/WaitWidget.swift` (full rewrite)
- Create: `Wait/WaitWidget/WidgetRowView.swift`
- Delete: `Wait/WaitWidget/WidgetStockRow.swift`
- Modify: `Wait/WaitWidget/Info.plist` (remove `TwelveDataAPIKey` if plan 01 added it)
- Modify: `Wait/project.yml` (widget dependencies become `Domain`, `DesignSystem` and `Persistence` only)

The widget makes no network calls. The app writes the snapshot through `SnapshotClient` and reloads the widget timelines whenever the watchlist or its quotes change (Task 27).

- [ ] **Step 1: Point the widget at the new products.** In `project.yml`, replace the `WaitWidgetExtension` target's `dependencies:` list with the list below. Keep plan 01's `sdk:` framework entries; if plan 01 lists more `sdk:` entries, keep those too.
```yaml
    dependencies:
      - sdk: SwiftUI.framework
      - sdk: WidgetKit.framework
      - package: WaitKit
        product: Domain
      - package: WaitKit
        product: DesignSystem
      - package: WaitKit
        product: Persistence
```

- [ ] **Step 2: Rewrite the widget**

`Wait/WaitWidget/WaitWidget.swift`:
```swift
//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import Persistence
import SwiftUI
import WidgetKit

// MARK: - SnapshotEntry

struct SnapshotEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchlistSnapshot?
}

// MARK: - SnapshotProvider

/// Reads `snapshot.json` from the app group. Refreshing is driven by the app (`WidgetCenter.reloadAllTimelines`), with a 30-minute fallback.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: .now, snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
    let snapshot = context.isPreview ? WatchlistSnapshot.sample : (SnapshotStore.appGroup.load() ?? .sample)
    completion(SnapshotEntry(date: .now, snapshot: snapshot))
  }

  func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
    let entry = SnapshotEntry(date: .now, snapshot: SnapshotStore.appGroup.load())
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
  }
}

// MARK: - WaitWidgetEntryView

struct WaitWidgetEntryView: View {
  // MARK: Internal

  let entry: SnapshotEntry

  var body: some View {
    Group {
      if let snapshot = entry.snapshot, !snapshot.rows.isEmpty {
        content(snapshot)
      } else {
        empty
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  // MARK: Private

  @Environment(\.widgetFamily) private var family

  private var maxRows: Int {
    family == .systemSmall ? 3 : 4
  }

  private var empty: some View {
    VStack(spacing: Spacing.s) {
      Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(Palette.accent)
      Text("Add stocks in Wait").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  private func content(_ snapshot: WatchlistSnapshot) -> some View {
    let rows = Array(snapshot.rows.prefix(maxRows))
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text("Wait").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
        Spacer()
        if let asOf = snapshot.quotesAsOf {
          Text(asOf, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
      }
      ForEach(rows) { row in
        if family == .systemSmall {
          WidgetRowView(row: row, compact: true)
        } else {
          Link(destination: Self.stockURL(row.symbol)) {
            WidgetRowView(row: row, compact: false)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .widgetURL(rows.first.map { Self.stockURL($0.symbol) })
  }

  /// The same format as `AppFeature.DeepLink`, which the widget can't import.
  private static func stockURL(_ symbol: String) -> URL {
    URL(string: "wait://stock/\(symbol)")!
  }
}

// MARK: - WaitWidget

@main
struct WaitWidget: Widget {
  let kind = "WaitWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
      WaitWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Watchlist")
    .description("Your watchlist with ladder status and temperature.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Sample

extension WatchlistSnapshot {
  static let sample = WatchlistSnapshot(
    generatedAt: .now,
    quotesAsOf: .now,
    rows: [
      .init(symbol: "AAPL", name: "Apple", price: Decimal(string: "189.98"), changePercent: 1.24, status: .watch, temperature: 52, ladder: .empty, isFavorite: true),
      .init(symbol: "PINS", name: "Pinterest", price: Decimal(string: "14.20"), changePercent: -0.8, status: .buyZone, temperature: 21, ladder: .empty, isFavorite: false),
      .init(symbol: "MSFT", name: "Microsoft", price: Decimal(string: "414.25"), changePercent: 0.4, status: .trim, temperature: 84, ladder: .empty, isFavorite: false),
    ]
  )
}

#Preview(as: .systemMedium) {
  WaitWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
  SnapshotEntry(date: .now, snapshot: nil)
}
```
The completions are written `@escaping @Sendable`, as the iOS 27 SDK declares them. If an older SDK reports a near-miss against the `TimelineProvider` requirement, apply Xcode's fix-it.

`Wait/WaitWidget/WidgetRowView.swift`:
```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WidgetRowView

struct WidgetRowView: View {
  let row: WatchlistSnapshot.Row
  let compact: Bool

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Text(row.symbol).font(.caption.weight(.semibold)).lineLimit(1)
      Spacer(minLength: Spacing.xxs)
      if !compact, let price = row.price {
        Text(price, format: .currency(code: "USD")).font(.caption.monospacedDigit())
      }
      if !compact, let change = row.changePercent {
        Text(change / 100, format: .percent.precision(.fractionLength(1)))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Palette.change(change))
      }
      StatusPill(status: row.status, compact: true)
      if !compact {
        TemperatureBadge(temperature: row.temperature.map(Temperature.init(value:)))
      }
    }
  }
}
```

- [ ] **Step 3: Remove the old row and the widget's API key**

Run:
```sh
cd "$(git rev-parse --show-toplevel)" && git rm Wait/WaitWidget/WidgetStockRow.swift && \
  (/usr/libexec/PlistBuddy -c "Delete :TwelveDataAPIKey" Wait/WaitWidget/Info.plist 2>/dev/null || true)
```

- [ ] **Step 4: Regenerate and build**

Run: `cd "$(git rev-parse --show-toplevel)/Wait" && xcodegen generate && cd .. && scripts/build-app.sh`
Expected: `** BUILD SUCCEEDED **`

Run: `R="$(git rev-parse --show-toplevel)"; test -f "$R/Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" && echo "Package.resolved present"; git -C "$R" status --short Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
Expected: `Package.resolved present`, and never a ` D` status line.

- [ ] **Step 5: Manual check (manual: user, or an agent with simulator UI access).** With the app from Task 27 installed and launched once, so `snapshot.json` exists:
  1. Long-press the home screen, choose **+**, then **Wait**, then **Watchlist (medium)**.
  2. Expected: the widget shows up to four real symbols, with status pills, temperature badges and the quote time.
  3. Tapping a row opens that stock in the app.
  4. A fresh install, before the app has run, shows "Add stocks in Wait".

- [ ] **Step 6: Commit**
```bash
git add Wait/WaitWidget Wait/project.yml Wait/Wait.xcodeproj
git commit -m "feat(widget): render the app-group watchlist snapshot with deep links (no network)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Chunk 15: Cutover and docs

### Task 29: Cutover: delete the legacy targets and move the app to Swift 6

**Files:**
- Delete:
  - `Wait/Packages/WaitKit/Sources/{Model,CacheService,Networking,StockCharts,Checklist,ChecklistEditFeature,LegacyStockDetails,SettingsTab}/`
  - `Wait/Packages/WaitKit/Tests/{ChecklistTests,ChecklistEditFeatureTests}/`
  - `Wait/Packages/WaitKit/Sources/Logging/LegacyLogger.swift`
  - The legacy DesignSystem files `Colors.swift`, `UIColor+CodeName.swift`, `UIColor+Hex.swift`, `UIColor+Theme.swift` and `Size.swift`
  - `Wait/Wait/Waitlist/`
- Replace: `Wait/Packages/WaitKit/Package.swift` (final content below)
- Modify: `Wait/project.yml` (the `Wait` target)

- [ ] **Step 1: Confirm nothing new depends on legacy code**

Run: `cd "$(git rev-parse --show-toplevel)" && grep -rlE "^import (Model|CacheService|Networking|StockCharts|Checklist|ChecklistEditFeature|LegacyStockDetails|SettingsTab|Money|Alamofire|SwiftyJSON|SwiftyBeaver)$" Wait/Wait/WaitApp.swift Wait/WaitWidget Wait/Packages/WaitKit/Sources/{Domain,Logging,DesignSystem,Persistence,MarketDataClient,ChecklistFeature,StockChartFeature,StockDetailsFeature,WatchlistFeature,SettingsFeature,AppFeature} ; echo "exit=$?"`
Expected: no file paths, then `exit=1` (grep matched nothing).

- [ ] **Step 2: Delete the legacy code**

Run:
```sh
cd "$(git rev-parse --show-toplevel)/Wait" && \
git rm -r -q Packages/WaitKit/Sources/Model Packages/WaitKit/Sources/CacheService Packages/WaitKit/Sources/Networking \
  Packages/WaitKit/Sources/StockCharts Packages/WaitKit/Sources/Checklist Packages/WaitKit/Sources/ChecklistEditFeature \
  Packages/WaitKit/Sources/LegacyStockDetails Packages/WaitKit/Sources/SettingsTab \
  Packages/WaitKit/Tests/ChecklistTests Packages/WaitKit/Tests/ChecklistEditFeatureTests \
  Packages/WaitKit/Sources/Logging/LegacyLogger.swift \
  Packages/WaitKit/Sources/DesignSystem/Colors.swift Packages/WaitKit/Sources/DesignSystem/UIColor+CodeName.swift \
  Packages/WaitKit/Sources/DesignSystem/UIColor+Hex.swift Packages/WaitKit/Sources/DesignSystem/UIColor+Theme.swift \
  Packages/WaitKit/Sources/DesignSystem/Size.swift \
  Wait/Waitlist && ls Packages/WaitKit/Sources Packages/WaitKit/Sources/DesignSystem
```
Expected:
- `Sources` lists: `AppFeature ChecklistFeature DesignSystem Domain Logging MarketDataClient Persistence SettingsFeature StockChartFeature StockDetailsFeature WatchlistFeature`.
- `DesignSystem` lists: `LadderStatus+Style.swift Palette.swift Spacing.swift StatusPill.swift TemperatureBadge.swift`.

If `git rm` reports a pathspec that doesn't match (for example, plan 01 named one of these files differently), list the directory, remove the legacy equivalent, and keep going.

- [ ] **Step 3: Replace `Package.swift` with its final plan 02 content.** It has no legacy targets, no Money/Alamofire/SwiftyJSON, and no `legacySettings`, and every target is Swift 6. Plans 03–06 only append to this file.
```swift
// swift-tools-version: 6.1
import PackageDescription

extension Target.Dependency {
  static let tca = Self.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
  static let dependencies = Self.product(name: "Dependencies", package: "swift-dependencies")
  static let dependenciesMacros = Self.product(name: "DependenciesMacros", package: "swift-dependencies")
  static let dependenciesTestSupport = Self.product(name: "DependenciesTestSupport", package: "swift-dependencies")
  static let sharing = Self.product(name: "Sharing", package: "swift-sharing")
  static let identifiedCollections = Self.product(name: "IdentifiedCollections", package: "swift-identified-collections")
}

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "AppFeature", targets: ["AppFeature"]),
    .library(name: "ChecklistFeature", targets: ["ChecklistFeature"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "MarketDataClient", targets: ["MarketDataClient"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    .library(name: "StockChartFeature", targets: ["StockChartFeature"]),
    .library(name: "StockDetailsFeature", targets: ["StockDetailsFeature"]),
    .library(name: "WatchlistFeature", targets: ["WatchlistFeature"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2", traits: ["ComposableArchitecture2Deprecations"]),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
  ],
  targets: [
    // Core (Domain, Logging, DesignSystem and Persistence also build for watchOS)
    .target(name: "Domain"),
    .target(name: "Logging"),
    .target(name: "DesignSystem", dependencies: ["Domain"]),
    .target(name: "Persistence", dependencies: ["Domain", "Logging", .sharing, .identifiedCollections, .dependencies, .dependenciesMacros]),
    .target(name: "MarketDataClient", dependencies: ["Domain", "Logging", .dependencies, .dependenciesMacros]),

    // Features
    .target(name: "ChecklistFeature", dependencies: ["Domain", "Persistence", "DesignSystem", .tca]),
    .target(name: "StockChartFeature", dependencies: ["Domain", "MarketDataClient", "DesignSystem", .tca]),
    .target(name: "StockDetailsFeature", dependencies: ["Domain", "Persistence", "MarketDataClient", "StockChartFeature", "DesignSystem", .tca]),
    .target(name: "WatchlistFeature", dependencies: ["Domain", "Persistence", "MarketDataClient", "StockDetailsFeature", "ChecklistFeature", "DesignSystem", .tca]),
    .target(name: "SettingsFeature", dependencies: ["ChecklistFeature", "DesignSystem", .tca]),
    .target(name: "AppFeature", dependencies: ["Domain", "DesignSystem", "Logging", "Persistence", "SettingsFeature", "WatchlistFeature", .tca]),

    // Tests
    .testTarget(name: "DomainTests", dependencies: ["Domain"], resources: [.copy("Fixtures")]),
    .testTarget(name: "LoggingTests", dependencies: ["Logging"]),
    .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "Domain"]),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain", .sharing, .identifiedCollections, .dependenciesTestSupport]),
    .testTarget(name: "MarketDataClientTests", dependencies: ["MarketDataClient", "Domain", .dependencies, .dependenciesTestSupport], resources: [.copy("Fixtures")]),
    .testTarget(name: "ChecklistFeatureTests", dependencies: ["ChecklistFeature", "Domain", "Persistence", .tca, .dependenciesTestSupport]),
    .testTarget(name: "StockChartFeatureTests", dependencies: ["StockChartFeature", "Domain", "MarketDataClient", .tca]),
    .testTarget(name: "StockDetailsFeatureTests", dependencies: ["StockDetailsFeature", "Domain", "MarketDataClient", .tca]),
    .testTarget(
      name: "WatchlistFeatureTests",
      dependencies: ["WatchlistFeature", "ChecklistFeature", "Domain", "MarketDataClient", "Persistence", "StockDetailsFeature", .tca, .dependenciesTestSupport]
    ),
    .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature", "ChecklistFeature", .tca, .dependenciesTestSupport]),
    .testTarget(
      name: "AppFeatureTests",
      dependencies: ["AppFeature", "Domain", "MarketDataClient", "Persistence", "StockDetailsFeature", "WatchlistFeature", .tca, .dependenciesTestSupport]
    ),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 4: Update the `Wait` target in `project.yml`**
  - `sources:` must contain only the `Wait` folder. Remove the `Shared` entry. The `WaitWatch` target keeps `Shared/Connectivity.swift` until plan 03 deletes it; under Swift 6 the app could no longer compile its `static let shared`.
  - `dependencies:`:
    - Keep `- package: WaitKit` with `product: AppFeature`.
    - Keep the `- target: WaitWidgetExtension` and `- target: WaitWatch` embed entries.
    - Delete every other `- package:` entry: legacy WaitKit products, Money, Alamofire and SwiftyJSON.
    - The top-level `packages:` keep Money, Alamofire and SwiftyJSON, because the watch still links them until plan 03.
  - `settings.base`: set `SWIFT_VERSION: "6.0"` for the `Wait` target. The widget keeps the plan 01 value; plan 03 normalizes tooling.

Run: `cd "$(git rev-parse --show-toplevel)/Wait" && xcodegen generate && xcodebuild -project Wait.xcodeproj -target Wait -showBuildSettings 2>/dev/null | grep -E "^\s+SWIFT_VERSION"`
Expected: `SWIFT_VERSION = 6.0`

Run: `R="$(git rev-parse --show-toplevel)"; test -f "$R/Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" && echo "Package.resolved present"; git -C "$R" status --short Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
Expected: `Package.resolved present`, and never a ` D` status line.

Run, to check that the entitlements still resolve after the edits:
```sh
cd "$(git rev-parse --show-toplevel)/Wait" && \
for cfg in Debug Release; do xcodebuild -project Wait.xcodeproj -target Wait -configuration $cfg -showBuildSettings 2>/dev/null | grep -E "^\s+CODE_SIGN_ENTITLEMENTS"; done; \
for cfg in Debug Release; do xcodebuild -project Wait.xcodeproj -target WaitWidgetExtension -configuration $cfg -showBuildSettings 2>/dev/null | grep -E "^\s+CODE_SIGN_ENTITLEMENTS"; done
```
Expected, in order:
```
    CODE_SIGN_ENTITLEMENTS = Wait/Wait.entitlements
    CODE_SIGN_ENTITLEMENTS = Wait/WaitRelease.entitlements
    CODE_SIGN_ENTITLEMENTS = WaitWidget/WaitWidget.entitlements
    CODE_SIGN_ENTITLEMENTS = WaitWidget/WaitWidget.entitlements
```

- [ ] **Step 5: Run the grep guards**

Run:
```sh
cd "$(git rev-parse --show-toplevel)" && \
grep -rnE "^import (Model|CacheService|Networking|StockCharts|Checklist|ChecklistEditFeature|LegacyStockDetails|SettingsTab|Money|Alamofire|SwiftyJSON|SwiftyBeaver)$" Wait/Wait Wait/WaitWidget Wait/Packages/WaitKit ; \
grep -rnE "Logger\.shared|StockCache|(^|[^A-Za-z])Size\." Wait/Wait Wait/WaitWidget Wait/Packages/WaitKit/Sources ; \
grep -nE "Money|Alamofire|SwiftyJSON|legacySettings|swiftLanguageMode\(\.v5\)" Wait/Packages/WaitKit/Package.swift ; \
echo "guards done"
```
Expected: only `guards done`. No line may match.

- [ ] **Step 6: Run the full verification**

Run: `scripts/test-waitkit.sh && scripts/build-app.sh && scripts/build-app.sh WaitWatch`
Expected:
- `** TEST SUCCEEDED **`, with 0 failures, for all eleven test targets in the scheme.
- `** BUILD SUCCEEDED **`, twice.

Then rerun the independent vectors check from Task 1 Step 2, the second command block. Expected: `vectors match overview`.

If Swift 6 strict concurrency reports errors, fix them in DesignSystem and the app, using overview §11 item 3. Those are the two places that changed language mode here. The app target now holds only `WaitApp.swift`.

- [ ] **Step 7: Repeat the manual migration and UI check** from Task 27 Step 11. Then also:
  - Add a stock through search. Its ladder must have a decimal buy high, such as `12.34`.
  - Pull to refresh.
  - Delete a stock with a swipe.
  - Reorder with Edit.
  - Open the 1D and 5Y chart ranges. Scrubbing updates the header.
  - Open Settings, then Checklist template, and add a prompt. The next stock you add starts with that prompt.
  - Background the app, then relaunch it. All edits persist.

- [ ] **Step 8: Commit**
```bash
git add -A Wait/Packages/WaitKit Wait/Wait Wait/project.yml Wait/Wait.xcodeproj
git commit -m "refactor!: cut over to WaitKit features; delete legacy modules, Money, Alamofire, SwiftyJSON; app in Swift 6

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 30: Update CLAUDE.md and the WaitKit README

**Files:**
- Modify: `CLAUDE.md` (repo root; `AGENTS.md` is a symlink to it)
- Create: `Wait/Packages/WaitKit/README.md`

- [ ] **Step 1: Replace the `## Architecture` section of `CLAUDE.md`** (from `## Architecture` up to, but not including, `## Code style`) with:

````markdown
## Architecture

### Targets
`Wait/project.yml` (XcodeGen; never hand-edit the pbxproj) generates three Xcode targets:
- `Wait`, which links `AppFeature`.
- `WaitWidgetExtension`, which links `Domain`, `DesignSystem` and `Persistence`.
- `WaitWatch`, which is still the legacy copy-based app until plan 03.

All other code lives in the local package `Wait/Packages/WaitKit` (iOS 17 / watchOS 10, Swift 6 language mode):

```
Domain              value types + ladder math: PriceLadder, Temperature, LadderStatus, WatchlistItem, Quote,
                    PriceSeries, ChartRange, MarketCalendar, PriceInput, WatchlistSnapshot, legacy decoders (no deps)
Logging             os.Logger channels: Log.app/.network/.persistence/.ui/.sync/.push/.connectivity
DesignSystem        -> Domain                         Palette, Spacing, StatusPill, TemperatureBadge
Persistence         -> Domain, Logging, Sharing, IdentifiedCollections, Dependencies
                    app-group files, @Shared(.watchlist) / @Shared(.checklistTemplate), mutation helpers,
                    SnapshotStore + SnapshotClient (\.snapshotClient), LegacyMigration
MarketDataClient    -> Domain, Logging, Dependencies  @DependencyClient (\.marketData) + CachingMarketDataClient + Twelve Data stopgap
ChecklistFeature    -> Domain, Persistence, DesignSystem, TCA         ChecklistFeature, ChecklistTemplateFeature
StockChartFeature   -> Domain, MarketDataClient, DesignSystem, TCA    StockChartFeature, ChartGeometry, StockChartView
StockDetailsFeature -> StockChartFeature, Persistence, MarketDataClient, DesignSystem, TCA
                    StockDetailsFeature, LadderEditorFeature, NotesEditorFeature
WatchlistFeature    -> StockDetailsFeature, ChecklistFeature, Persistence, MarketDataClient, DesignSystem, TCA
                    WatchlistFeature (Path: details, checklist), AddStockFeature
SettingsFeature     -> ChecklistFeature, DesignSystem, TCA
AppFeature          -> WatchlistFeature, SettingsFeature, Persistence, DesignSystem, Logging, TCA
                    AppFeature, AppView, DeepLink, AppDelegate (owns the store)
```

### Data flow
- **Source of truth.**
  - The watchlist is `@Shared(.watchlist)`: an `IdentifiedArrayOf<WatchlistItem>` stored in `watchlist.json` in the app group `group.chenkai.wait.contents`.
  - Mutate it only through the helpers in `Persistence/Shared+Watchlist.swift` (`update`, `add`, `remove`, `reorder`, `Shared<WatchlistItem>.update(now:)`). They stamp `updatedAt`, truncated to milliseconds.
- **Legacy data.**
  - `LegacyMigration` runs once, inside the lazy initializer of `AppDelegate.store`. The marker file `migration-v1.done` stops it running again.
  - It converts `Documents/stocks` (Money JSON) and the `checklist-*` files. The old files are left in place.
- **Price ladder.**
  - Anchors: `buyLow`, `buyHigh`, `fair`, `trim`, `sell`. `temperature(at:)` gives 0–100; `status(at:)` gives a `LadderStatus`.
  - The test vectors in `shared/ladder-test-vectors.json` are shared with the server tests. Change them only together with both test suites.
- **Market data.**
  - Features call `@Dependency(\.marketData)`. Its `liveValue` is `.cached(.twelveData(...))`, a stopgap until plan 04.
  - Read `.cacheOnly` first, then `.useCache`. Pull-to-refresh uses `.reload`.
  - TTLs follow NYSE hours (`CacheTTL`, `MarketCalendar`). After a 429, a cooldown makes every request serve from cache.
- **Widget.**
  - `AppFeature` publishes a `WatchlistSnapshot`, debounced 1 s, through `SnapshotClient`. That writes `snapshot.json` and calls `WidgetCenter.reloadAllTimelines()`.
  - The widget never touches the network.
- **Deep links.** `wait://stock/<SYMBOL>`.

### Presentation pattern
- Every screen is a TCA 1.26 `@Reducer` with `@ObservableState`.
- Navigation:
  - Stacks are `StackState` (`WatchlistFeature.Path`, `SettingsFeature.Path`).
  - Sheets and alerts are `@Presents`.
  - Child features report to their parents with `delegate` actions.
- Effects send back paired success and failure actions.
- Tests use Swift Testing with `TestStore`, in `Packages/WaitKit/Tests/<Target>Tests`. Run them with `scripts/test-waitkit.sh`.
````

- [ ] **Step 2: Update the test and build lines in the `## Commands` section of `CLAUDE.md`** so they read:
```sh
cd Wait && xcodegen generate                 # after editing Wait/project.yml
scripts/build-app.sh                         # app + widget (+ embedded watch), iPhone 17 / iOS 27.0
scripts/build-app.sh WaitWatch               # watch app
scripts/test-waitkit.sh                      # every WaitKit test target (scheme WaitKit-Package)
scripts/test-waitkit.sh DomainTests/PriceLadderTemperatureTests   # one suite
```
Also add this line: "`xcodebuild`/`xcodegen` need to run unsandboxed in agent sessions."

- [ ] **Step 3: Create `Wait/Packages/WaitKit/README.md`**
````markdown
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
- **Tests.**
  - Every target has a Swift Testing target, and TCA tests are `@MainActor`.
  - Suites that touch `@Shared` use `@Suite(.dependencies { $0.defaultFileStorage = .inMemory })`.
  - Run them with `scripts/test-waitkit.sh [Target[/Suite]]`. `swift test` doesn't work, because the features use iOS-only SwiftUI.
- **Adding a target.** Append its `.target` and `.testTarget` to `Package.swift`. If an Xcode target links it, add a `.library` product and list that product in `Wait/project.yml`.
````

- [ ] **Step 4: Commit**
```bash
git add CLAUDE.md Wait/Packages/WaitKit/README.md
git commit -m "docs: describe WaitKit architecture, data flow and commands after plan 02

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Plan 02 done when
- Every box above is checked.
- `scripts/test-waitkit.sh && scripts/build-app.sh && scripts/build-app.sh WaitWatch` is green.
- The manual checks in Tasks 27–29 passed: migrated list, memo kept, star toggles, no crash with an empty chart, widget shows the real watchlist.
- `Package.swift` has no legacy targets or third-party dependencies apart from Point-Free's.

Then hand off to plan 03 (watch and cleanup) and/or plan 04 (backend). Use superpowers:finishing-a-development-branch.
