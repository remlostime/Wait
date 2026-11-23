# iOS Watch App and Cleanup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The watch shows the iPhone's real watchlist, using the shared `Domain` types and a WCSession snapshot sent by the phone. The watch's drifted model copies, network clients and API keys are deleted, and the iOS tooling and docs are finished.

**Architecture:**
- A new watchOS-compatible WaitKit target, `Connectivity`, wraps `WCSession` behind a `WCSessionAdapter` protocol.
- `ConnectivityEngine` delivers in both directions, and the latest snapshot always wins:
  - Sending: the newest unsent payload waits until the session is activated and the counterpart app is installed.
  - Receiving: a context older than the one already seen is ignored, and every stream first replays the latest known snapshot.
- `ConnectivityClient` exposes the engine as a swift-dependencies client. `SnapshotClient.alsoSending(to:)`, declared in `AppFeature`, makes the existing publish effect also send the snapshot to the watch.
- The watch app is reduced to four small SwiftUI files over a `@MainActor @Observable WatchSnapshotStore`.

**Tech Stack:** Swift 6, SwiftUI (iOS 17 / watchOS 10), WatchConnectivity, Observation, `os` (`OSAllocatedUnfairLock`, `Logger`), swift-dependencies 1.17 (`@DependencyClient`), TCA 1.26 (`TestStore`), Swift Testing, XcodeGen 2.46, SwiftLint.

> **Deviation from overview:**
> 1. `WatchSnapshotStore` lives in the `Connectivity` package target (`Sources/Connectivity/WatchSnapshotStore.swift`), not in `WaitWatch/WatchSnapshotStore.swift` as overview §12.1 says. The watch app has no test target, and package tests run on the iOS simulator, so this is the only place the store can be tested.
> 2. Files beyond the two that §12.1 lists: `Connectivity/{SnapshotCoding,ConnectivityEngine,LiveWCSessionAdapter,WatchSnapshotStore}.swift`, `AppFeature/SnapshotClient+Connectivity.swift`, and `WaitWatch/{WatchlistRowView,WatchFormat}.swift`.
> 3. The publish effect reaches `connectivity.send` through `snapshotClient.alsoSending(to: connectivity)`. This combinator lives in `AppFeature` and keeps every other `SnapshotClient` endpoint intact. That satisfies §12.3's "In 03 it also calls `connectivity.send`".
> 4. **Plan 02's app-layer fix changed `publishSnapshot` (verified by Task 1).** The helper is now `private func publishSnapshot(_ inputs:, debounced: Bool = true)`, and the `.run` effect does `if debounced { try await clock.sleep(for: .seconds(1)) }` before publishing. `.scenePhaseChanged(.background)` calls it with `debounced: false` inside a `.merge`, so a suspended app still publishes at once. There is still exactly one `snapshotClient.publish(` call site, so Task 6's two substring edits apply unchanged. Only the code block in Task 6 Step 7 is adapted. More plan-02 tests now reach the publish path than Task 6 Step 10 lists: `didFinishLaunchingPublishesASnapshot`, `backgroundPublishesImmediatelyAndCancelsTheDebouncedPublish`, `becomingActiveRefreshesQuotesAndPublishesOneSnapshot` and `burstsOfChangesPublishOnce`. Step 10's rule (add `$0.connectivity = .noop` plus `import Connectivity`) applies to each of them.
> 5. `Package.swift` already defines `Target.Dependency` shortcuts, so Task 2 Step 1 writes `.dependencies` and `.dependenciesMacros` instead of `.product(name: "Dependencies", package: "swift-dependencies")`, and declares the `Connectivity` target on one line.
>
> `Connectivity` depends only on Domain, Dependencies and DependenciesMacros, as overview §3.1 specifies, so the watch doesn't link Persistence, Sharing or IdentifiedCollections. It logs with `os.Logger` directly.

---

## Prerequisites

- **Plans 01 and 02 are complete.** Their definitions of done are in `docs/superpowers/plans/2026-11-22-wait-00-overview.md` §4.1. Read the overview before starting. It is the source of truth for names and paths.
- **Work in a git worktree off `ck/new-version`.** Use `superpowers:using-git-worktrees`. Never work on `master`. All paths below are relative to the repo root `/Users/ckai/code/Wait` unless a command `cd`s elsewhere. If you use a worktree, replace `/Users/ckai/code/Wait` with the worktree root.
- **Skills:**
  - `superpowers:test-driven-development` for every task.
  - `swiftui-expert:swiftui-expert-skill` for Task 7.
  - `ios-code-best-practice:ios-code-best-practice`, only its Swift concurrency guidance (Tasks 3–5).
- **Tools:**
  - Xcode 27.0, XcodeGen 2.46.0 and SwiftLint are installed.
  - SwiftFormat is optional (`brew install swiftformat`).
  - Simulators: `iPhone 17` on iOS 27.0 and `Apple Watch Series 12 (42mm)` on watchOS 27.0.
- **Sandbox:** run every `xcodebuild` and `xcodegen` command, and plan 02's `scripts/test-waitkit.sh` and `scripts/build-app.sh`, **outside the agent sandbox**. In Claude Code that means `dangerouslyDisableSandbox: true` for those Bash calls. SwiftPM's manifest sandbox can't nest, and fails with `sandbox_apply: Operation not permitted` (plan 01).
- **Quotes (for Task 8 only):** a Twelve Data key in `Wait/Config/Secrets.xcconfig` (plan 01), or plan 04's backend. Without one, rows show "No quote" and no temperature.
- **Plan-02 APIs this plan uses** (Task 1 verifies each):

  | Where | API |
  |---|---|
  | `Domain` | `WatchlistSnapshot(generatedAt:quotesAsOf:rows:)`, `WatchlistSnapshot.Row(symbol:name:price:changePercent:status:temperature:ladder:isFavorite:)` |
  | `Domain` | `PriceLadder(buyLow:buyHigh:fair:trim:sell:) throws`, `PriceLadder.empty`, `.rungs: [LadderRung]` (with `rung`, `price`, `isDerived`), `.distanceToBuy(from:)` |
  | `Domain` | `LadderStatus`, `PriceLadder.Rung.title` |
  | `DesignSystem` | `StatusPill(status:compact:)` |
  | `Persistence` | `@DependencyClient SnapshotClient` with `var publish: @Sendable (WatchlistSnapshot) async -> Void`, and `\.snapshotClient` |
  | `AppFeature` | `AppFeature.State()`, `Action.appDelegate(.didFinishLaunching)`, exactly one call site of `snapshotClient.publish(` |

## File Structure

| Path (relative to `Wait/`) | Action | Responsibility |
|---|---|---|
| `Packages/WaitKit/Package.swift` | Modify | Add the `Connectivity` product, target and test target. Add `Connectivity` to `AppFeature` and `AppFeatureTests`. |
| `Packages/WaitKit/Sources/Connectivity/SnapshotCoding.swift` | Create | JSON coding of `WatchlistSnapshot` for the application context, with a byte cap |
| `Packages/WaitKit/Sources/Connectivity/WCSessionAdapter.swift` | Create | The `WCSessionAdapter` protocol and `SessionEvent` |
| `Packages/WaitKit/Sources/Connectivity/ConnectivityEngine.swift` | Create | Latest-wins send and receive, plus snapshot streams |
| `Packages/WaitKit/Sources/Connectivity/LiveWCSessionAdapter.swift` | Create | The `WCSession.default` adapter and its delegate (Swift 6 isolation) |
| `Packages/WaitKit/Sources/Connectivity/ConnectivityClient.swift` | Create | `@DependencyClient ConnectivityClient`, `ConnectivityError`, `\.connectivity` |
| `Packages/WaitKit/Sources/Connectivity/WatchSnapshotStore.swift` | Create | The watch's `@Observable` model |
| `Packages/WaitKit/Tests/ConnectivityTests/Support/{SnapshotFixtures,FakeSessionAdapter,CallRecorder}.swift` | Create | Test helpers |
| `Packages/WaitKit/Tests/ConnectivityTests/{SnapshotCodingTests,ConnectivityEngineTests,ConnectivityClientTests,WatchSnapshotStoreTests}.swift` | Create | Unit tests |
| `Packages/WaitKit/Sources/AppFeature/SnapshotClient+Connectivity.swift` | Create | `SnapshotClient.alsoSending(to:)` (internal to AppFeature) |
| `Packages/WaitKit/Sources/AppFeature/AppFeature.swift` | Modify | Activate connectivity on launch; publish through `alsoSending(to:)` |
| `Packages/WaitKit/Tests/AppFeatureTests/AppFeatureConnectivityTests.swift` | Create | TestStore test for activation and unit tests for the combinator |
| `Shared/Connectivity.swift` | Delete (if present) | Legacy WCSession singleton, plus its single `path: Shared/Connectivity.swift` entry under `WaitWatch` in `project.yml` |
| `WaitWatch Watch App/` → `WaitWatch/` | Move | Watch app folder. The drifted copies are deleted. |
| `WaitWatch/{WaitWatchApp,WatchlistListView,WatchlistRowView,WatchStockDetailView,WatchFormat}.swift` | Create/replace | The watch UI |
| `project.yml` | Modify | Watch target on WaitKit products; drop `Shared` sources and the Money, Alamofire and SwiftyJSON packages |
| `.swiftformat`, `.swiftlint.yml` | Modify | Swift 6, package excludes, deployment targets |
| `../.gitignore` | Modify | Ignore the package's own `Package.resolved` and `.swiftpm` |
| `../CLAUDE.md`, `Packages/WaitKit/README.md`, `../docs/ci/bitrise-checklist.md` | Rewrite/create | Docs |

---

## Chunk 1: Connectivity core

### Task 1: Verify the plan-02 contracts this plan builds on

No code changes and no commit. If any expected output differs, **stop and ask the user**, because the overview says a mismatch must not be guessed around.

**Files:** none (read-only)

- [x] **Step 1: Check the Domain snapshot initializers**

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit
grep -c "public init" Sources/Domain/WatchlistSnapshot.swift
grep -n "public init(generatedAt: Date, quotesAsOf: Date?, rows: \[Row\])" Sources/Domain/WatchlistSnapshot.swift
grep -n -A 9 "public init($" Sources/Domain/WatchlistSnapshot.swift
```

Expected:
- The count is `3`: the snapshot init, the `Row` memberwise init, and the `Row` `init(from:)`.
- The `generatedAt` grep prints exactly one line. Line numbers may vary.
- The `-A 9` grep shows the multi-line `Row` init. Its parameters, one per line and in this order, are `symbol: String`, `name: String`, `price: Decimal?`, `changePercent: Double?`, `status: LadderStatus?`, `temperature: Double?`, `ladder: PriceLadder`, `isFavorite: Bool`.
- If the `Row` init is on a single line instead, it shows up in the `public init` count and should read `public init(symbol: String, name: String, price: Decimal?, changePercent: Double?, status: LadderStatus?, temperature: Double?, ladder: PriceLadder, isFavorite: Bool)`.

- [x] **Step 2: Check `LadderRung` and `StatusPill`**

Run: `grep -rn -A 5 "public struct LadderRung" Sources/Domain/ && grep -n "public init" Sources/DesignSystem/StatusPill.swift`

Expected:
- `LadderRung` has `public let rung: PriceLadder.Rung`, `public let price: Decimal` and `public let isDerived: Bool`. `var` instead of `let` is fine.
- `PriceLadder.Rung` has `public var title: String` ("Buy low", "Buy high", …). Check with `grep -n "public var title" Sources/Domain/PriceLadder.swift`. The watch detail view uses it.
- `StatusPill` has an initializer whose first parameter is `status:` and whose other parameters all have defaults. Plan 02 writes `public init(status: LadderStatus?, compact: Bool = false)`, which is fine. This plan calls `StatusPill(status:compact:)` with `compact: true`.

- [x] **Step 3: Check `SnapshotClient`**

Run: `grep -n -B 2 -A 4 "struct SnapshotClient" Sources/Persistence/SnapshotClient.swift && grep -rn "var snapshotClient" Sources/Persistence/`

Expected: `@DependencyClient` above `public struct SnapshotClient`, a `public var publish: @Sendable (_ snapshot: WatchlistSnapshot) async -> Void` (the argument label may be omitted), and a `public var snapshotClient: SnapshotClient` in a `DependencyValues` extension.

- [x] **Step 4: Check the AppFeature anchors**

Run: `grep -n "didFinishLaunching" Sources/AppFeature/*.swift; grep -c "snapshotClient.publish(" Sources/AppFeature/AppFeature.swift; grep -n "public init()" Sources/AppFeature/AppFeature.swift; ls Tests/AppFeatureTests`

Expected:
- `didFinishLaunching` appears in `AppDelegateAction.swift` (the case), in `AppFeature.swift` (`case .appDelegate(.didFinishLaunching):`) and in `AppDelegate.swift` (`store.send(.appDelegate(.didFinishLaunching))`).
- The count printed is `1`. Plan 02 puts it inside `private func publishSnapshot(_:)`, whose effect captures `[clock, date, snapshotClient]`.
- `AppFeature.State` has a `public init()` (inside `struct State`).
- `Tests/AppFeatureTests` lists at least one `.swift` file.

- [x] **Step 5: Check the package dependency identities**

Run: `grep -n "swift-dependencies\|swift-composable-architecture" Package.swift | head -4`

Expected: `.package(url: "https://github.com/pointfreeco/swift-dependencies", …)` and the TCA package are both declared.

- [x] **Step 6: Check platforms, the snapshot dependency, the watch target key and `.gitignore`**

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit
grep -n "platforms:" Package.swift
grep -n '@Dependency(\\.snapshotClient)' Sources/AppFeature/AppFeature.swift
cd /Users/ckai/code/Wait/Wait
awk '/^targets:/{t=1; next} /^[A-Za-z]/{t=0} t && /^  "?WaitWatch( Watch App)?"?:/' project.yml
awk '/^schemes:/{t=1; next} /^[A-Za-z]/{t=0} t && /^  "?WaitWatch( Watch App)?"?:/' project.yml
grep -n "Shared" project.yml
cd /Users/ckai/code/Wait
grep -n "Packages/WaitKit" .gitignore
```

Expected:
- `platforms: [.iOS(.v17), .watchOS(.v10)]`.
- One `@Dependency(\.snapshotClient) var snapshotClient` line.
- The first `awk`, scoped to `targets:`, prints exactly one line: the watch target key, normally `  WaitWatch:`. The spelling `  "WaitWatch Watch App":` is handled in Task 7 Step 2. Write down which spelling you saw.
- The second `awk`, scoped to `schemes:`, prints exactly one line: the watch scheme key, normally `  WaitWatch:`. An unscoped `grep '^  WaitWatch:'` matches both keys, which is why both checks are scoped.
- Zero or one `Shared` line. After plan 02's cutover the app target no longer compiles `Shared/`, so the only possible entry is one `- path: Shared/Connectivity.swift` under the watch target. Task 6 Step 11 removes it. If a `Shared` line appears under the `Wait` target, stop and ask.
- `.gitignore` already lists `Wait/Packages/WaitKit/Package.resolved` and `Wait/Packages/WaitKit/.swiftpm/` (plan 01).

On any mismatch, stop and ask the user. The one exception is `.gitignore`: if either line is missing, note it, because Task 9 Step 3 adds only missing lines.

---

### Task 2: `Connectivity` target and `SnapshotCoding`

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift`
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/SnapshotCoding.swift`
- Create: `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/SnapshotFixtures.swift`
- Test: `Wait/Packages/WaitKit/Tests/ConnectivityTests/SnapshotCodingTests.swift`

- [x] **Step 1: Declare the product and targets**

In `Wait/Packages/WaitKit/Package.swift`, add this element to the `products:` array (after the `Persistence` product):

```swift
    .library(name: "Connectivity", targets: ["Connectivity"]),
```

Add these two elements to the `targets:` array (after the `Persistence` target):

```swift
    .target(
      name: "Connectivity",
      dependencies: [
        "Domain",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "ConnectivityTests",
      dependencies: [
        "Connectivity",
        "Domain",
      ]
    ),
```

- [x] **Step 2: Write the test fixtures**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/SnapshotFixtures.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotFixtures

enum SnapshotFixtures {
  static let generatedAt = Date(timeIntervalSince1970: 1_763_800_000)

  static func row(_ index: Int, isFavorite: Bool = false) throws -> WatchlistSnapshot.Row {
    WatchlistSnapshot.Row(
      symbol: "SYM\(index)",
      name: "Company \(index) Holdings Incorporated",
      price: Decimal(string: "3.133"),
      changePercent: -1.25,
      status: .buyZone,
      temperature: 27.5,
      ladder: try PriceLadder(buyLow: Decimal(string: "2.5"), buyHigh: Decimal(string: "3.2"), fair: 5),
      isFavorite: isFavorite
    )
  }

  static func snapshot(rowCount: Int, generatedAt: Date = generatedAt) throws -> WatchlistSnapshot {
    WatchlistSnapshot(
      generatedAt: generatedAt,
      quotesAsOf: generatedAt.addingTimeInterval(-60),
      rows: try (0 ..< rowCount).map { try row($0, isFavorite: $0 == 0) }
    )
  }
}
```

- [x] **Step 3: Write the failing tests**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/SnapshotCodingTests.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - SnapshotCodingTests

@Suite
struct SnapshotCodingTests {
  @Test
  func roundTripPreservesDecimalsAndDates() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 3)

    let data = try SnapshotCoding.encode(snapshot)

    #expect(SnapshotCoding.decode(data) == snapshot)
  }

  @Test
  func encodesPricesAsDecimalStrings() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)

    let json = try String(decoding: SnapshotCoding.encode(snapshot), as: UTF8.self)

    #expect(json.contains("\"price\":\"3.133\""))
  }

  @Test
  func dropsTrailingRowsUntilThePayloadFits() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 40)
    let full = try SnapshotCoding.encode(snapshot, maxBytes: .max)
    let limit = full.count / 2

    let data = try SnapshotCoding.encode(snapshot, maxBytes: limit)
    let decoded = try #require(SnapshotCoding.decode(data))

    #expect(data.count <= limit)
    #expect(decoded.rows.count < snapshot.rows.count)
    #expect(decoded.rows == Array(snapshot.rows.prefix(decoded.rows.count)))
    #expect(decoded.generatedAt == snapshot.generatedAt)
  }

  @Test
  func throwsWhenEvenAnEmptySnapshotDoesNotFit() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)

    #expect(throws: SnapshotCodingError.self) {
      try SnapshotCoding.encode(snapshot, maxBytes: 10)
    }
  }

  @Test
  func decodeReturnsNilForGarbage() {
    #expect(SnapshotCoding.decode(Data("not json".utf8)) == nil)
  }
}
```

- [ ] **Step 4: Run the tests to verify they fail** — NOT RUN (code-only; checked in the /tmp harness instead: RED = `no such module 'Connectivity'`, GREEN = 5 of 5 pass)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ConnectivityTests
```
Expected: FAIL. Package resolution reports that the target `Connectivity` has no source files under `Sources/Connectivity`, or the compile stops with `cannot find 'SnapshotCoding' in scope`.

- [x] **Step 5: Implement `SnapshotCoding`**

Create `Wait/Packages/WaitKit/Sources/Connectivity/SnapshotCoding.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotCoding

/// Encodes a `WatchlistSnapshot` for `WCSession.updateApplicationContext`.
///
/// The application context is capped at about 65 KB. When the snapshot is larger than `maxBytes`,
/// `encode` drops rows from the end until it fits. Favorites come first in a snapshot, so they survive longest.
public enum SnapshotCoding {
  // MARK: Public

  public static let contextKey = "snapshot"
  public static let defaultMaxBytes = 60000

  public static func encode(_ snapshot: WatchlistSnapshot, maxBytes: Int = defaultMaxBytes) throws -> Data {
    let encoder = makeEncoder()
    var rows = snapshot.rows
    while true {
      let candidate = WatchlistSnapshot(generatedAt: snapshot.generatedAt, quotesAsOf: snapshot.quotesAsOf, rows: rows)
      let data = try encoder.encode(candidate)
      if data.count <= maxBytes {
        return data
      }
      guard !rows.isEmpty else {
        throw SnapshotCodingError.tooLarge(bytes: data.count, maxBytes: maxBytes)
      }
      rows.removeLast()
    }
  }

  public static func decode(_ data: Data) -> WatchlistSnapshot? {
    try? JSONDecoder().decode(WatchlistSnapshot.self, from: data)
  }

  // MARK: Private

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

// MARK: - SnapshotCodingError

public enum SnapshotCodingError: Error, Equatable, Sendable {
  case tooLarge(bytes: Int, maxBytes: Int)
}
```

- [ ] **Step 6: Run the tests to verify they pass** — NOT RUN (code-only; checked in the /tmp harness instead: RED = `no such module 'Connectivity'`, GREEN = 5 of 5 pass)

Run: the same command as Step 4.
Expected: PASS. `** TEST SUCCEEDED **`, with 5 tests passing in `SnapshotCodingTests`.

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Package.swift Wait/Packages/WaitKit/Sources/Connectivity Wait/Packages/WaitKit/Tests/ConnectivityTests
git commit -m "$(cat <<'EOF'
feat(connectivity): add Connectivity target with size-capped snapshot coding

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `ConnectivityEngine`: latest-wins delivery behind `WCSessionAdapter`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/WCSessionAdapter.swift`
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/ConnectivityEngine.swift`
- Create: `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/FakeSessionAdapter.swift`
- Test: `Wait/Packages/WaitKit/Tests/ConnectivityTests/ConnectivityEngineTests.swift`

- [x] **Step 1: Write the fake session**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/FakeSessionAdapter.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import os
@testable import Connectivity

// MARK: - FakeSessionError

enum FakeSessionError: Error, Equatable, Sendable {
  case notReachable
}

// MARK: - FakeSessionAdapter

/// A synchronous stand-in for `WCSession`. Events fire on the calling thread, so tests are deterministic.
final class FakeSessionAdapter: WCSessionAdapter, Sendable {
  // MARK: Lifecycle

  init(_ initial: State = State()) {
    state = OSAllocatedUnfairLock(initialState: initial)
  }

  // MARK: Internal

  struct State: Sendable {
    var isSupported = true
    var isActivated = false
    var canSendToCounterpart = true
    var receivedContextData: Data?
    var activationCount = 0
    var sentContexts: [Data] = []
    var updateError: FakeSessionError?
    var onEvent: (@Sendable (SessionEvent) -> Void)?
  }

  var isSupported: Bool { state.withLock { $0.isSupported } }
  var isActivated: Bool { state.withLock { $0.isActivated } }
  var canSendToCounterpart: Bool { state.withLock { $0.canSendToCounterpart } }
  var receivedContextData: Data? { state.withLock { $0.receivedContextData } }
  var activationCount: Int { state.withLock { $0.activationCount } }
  var sentContexts: [Data] { state.withLock { $0.sentContexts } }

  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void) {
    state.withLock {
      $0.activationCount += 1
      $0.onEvent = onEvent
    }
  }

  func updateContext(_ data: Data) throws {
    try state.withLock { locked in
      if let error = locked.updateError {
        throw error
      }
      locked.sentContexts.append(data)
    }
  }

  /// Simulates `activationDidCompleteWith: .activated`.
  func completeActivation() {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.isActivated = true
      return locked.onEvent
    }
    onEvent?(.activated)
  }

  /// Simulates `didReceiveApplicationContext`.
  func receive(_ data: Data) {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.receivedContextData = data
      return locked.onEvent
    }
    onEvent?(.receivedContext(data))
  }

  /// Simulates the watch app being installed or removed.
  func setCanSendToCounterpart(_ value: Bool) {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.canSendToCounterpart = value
      return locked.onEvent
    }
    onEvent?(.counterpartChanged)
  }

  func setUpdateError(_ error: FakeSessionError?) {
    state.withLock { $0.updateError = error }
  }

  // MARK: Private

  private let state: OSAllocatedUnfairLock<State>
}
```

- [x] **Step 2: Write the failing engine tests**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/ConnectivityEngineTests.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - ConnectivityEngineTests

@Suite
struct ConnectivityEngineTests {
  // MARK: Sending

  @Test
  func onlyTheLatestSnapshotSentBeforeActivationIsDelivered() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let newer = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(30))

    try engine.send(older)
    try engine.send(newer)
    #expect(fake.sentContexts.isEmpty)

    engine.activate()
    fake.completeActivation()

    #expect(fake.sentContexts.count == 1)
    let sent = try #require(fake.sentContexts.last)
    #expect(SnapshotCoding.decode(sent) == newer)
  }

  @Test
  func sendAfterActivationDeliversImmediately() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))

    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func nothingIsSentUntilTheCounterpartAppIsInstalled() throws {
    let fake = FakeSessionAdapter(.init(canSendToCounterpart: false))
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    #expect(fake.sentContexts.isEmpty)

    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func aFailedUpdateKeepsThePayloadForTheNextChance() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    fake.setUpdateError(.notReachable)

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    #expect(fake.sentContexts.isEmpty)

    fake.setUpdateError(nil)
    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func sendThrowsWhenTheSnapshotCannotFit() throws {
    let engine = ConnectivityEngine(adapter: FakeSessionAdapter(), maxContextBytes: 10)

    #expect(throws: SnapshotCodingError.self) {
      try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    }
  }

  // MARK: Activation

  @Test
  func activateIsIdempotent() {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)

    engine.activate()
    engine.activate()

    #expect(fake.activationCount == 1)
  }

  @Test
  func anUnsupportedSessionIsNeverActivated() {
    let fake = FakeSessionAdapter(.init(isSupported: false))
    let engine = ConnectivityEngine(adapter: fake)

    engine.activate()

    #expect(fake.activationCount == 0)
  }

  // MARK: Receiving

  @Test
  func theContextReceivedBeforeLaunchIsYieldedFirst() async throws {
    let initial = try SnapshotFixtures.snapshot(rowCount: 2)
    let fake = FakeSessionAdapter(.init(receivedContextData: try SnapshotCoding.encode(initial)))
    let engine = ConnectivityEngine(adapter: fake)
    var iterator = engine.snapshots().makeAsyncIterator()

    engine.activate()
    fake.completeActivation()

    let first = await iterator.next()
    #expect(first == initial)
  }

  @Test
  func aLateSubscriberGetsTheLatestSnapshotImmediately() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)
    engine.activate()
    fake.completeActivation()
    fake.receive(try SnapshotCoding.encode(snapshot))

    var iterator = engine.snapshots().makeAsyncIterator()

    let first = await iterator.next()
    #expect(first == snapshot)
  }

  @Test
  func olderAndDuplicateContextsAreIgnored() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let base = SnapshotFixtures.generatedAt
    let middle = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: base.addingTimeInterval(60))
    let oldest = try SnapshotFixtures.snapshot(rowCount: 1, generatedAt: base)
    let newest = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: base.addingTimeInterval(120))
    engine.activate()
    fake.completeActivation()
    var iterator = engine.snapshots().makeAsyncIterator()

    fake.receive(try SnapshotCoding.encode(middle))
    let first = await iterator.next()
    fake.receive(try SnapshotCoding.encode(middle))
    fake.receive(try SnapshotCoding.encode(oldest))
    fake.receive(try SnapshotCoding.encode(newest))
    let second = await iterator.next()

    #expect(first == middle)
    #expect(second == newest)
  }

  @Test
  func garbageContextsAreDropped() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)
    engine.activate()
    fake.completeActivation()
    var iterator = engine.snapshots().makeAsyncIterator()

    fake.receive(Data("garbage".utf8))
    fake.receive(try SnapshotCoding.encode(snapshot))

    let first = await iterator.next()
    #expect(first == snapshot)
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail** — NOT RUN (code-only; checked in the /tmp harness instead: RED = `cannot find 'ConnectivityEngine' in scope`)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ConnectivityTests
```
Expected: FAIL with compile errors `cannot find type 'WCSessionAdapter' in scope` and `cannot find 'ConnectivityEngine' in scope`.

- [x] **Step 4: Write the adapter protocol**

Create `Wait/Packages/WaitKit/Sources/Connectivity/WCSessionAdapter.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - SessionEvent

public enum SessionEvent: Equatable, Sendable {
  /// The session finished activating and can send and receive.
  case activated
  /// The counterpart app was installed or removed, or the iPhone was paired with another watch.
  case counterpartChanged
  /// A new application context arrived. The payload is the value stored under `SnapshotCoding.contextKey`.
  case receivedContext(Data)
}

// MARK: - WCSessionAdapter

/// The part of `WCSession` that `ConnectivityEngine` needs. The live type is `LiveWCSessionAdapter`; tests use a fake.
public protocol WCSessionAdapter: AnyObject, Sendable {
  var isSupported: Bool { get }
  var isActivated: Bool { get }
  /// iOS: a watch is paired and the watch app is installed. watchOS: the companion iPhone app is installed.
  var canSendToCounterpart: Bool { get }
  /// The snapshot payload of the most recent application context received from the counterpart, if any.
  var receivedContextData: Data? { get }
  /// Activates the session. `onEvent` may be called on any thread.
  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void)
  /// Replaces the application context with `[SnapshotCoding.contextKey: data]`.
  func updateContext(_ data: Data) throws
}
```

- [x] **Step 5: Implement the engine**

Create `Wait/Packages/WaitKit/Sources/Connectivity/ConnectivityEngine.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import os

// MARK: - ConnectivityEngine

/// Runs this process's side of the phone–watch conversation.
///
/// - Sending is latest-wins. `send` keeps only the newest payload and delivers it once the session
///   is activated and the counterpart app is installed. Older payloads that were never delivered are dropped.
/// - Receiving is latest-wins by `generatedAt`. A context older than, or equal to, the latest one is ignored.
/// - Every stream from `snapshots()` first yields the latest snapshot already known (including the
///   context received before launch), then each newer one.
///
/// State sits behind a lock and events are handled synchronously, so delivery order is deterministic.
public final class ConnectivityEngine: Sendable {
  // MARK: Lifecycle

  public init(adapter: any WCSessionAdapter, maxContextBytes: Int = SnapshotCoding.defaultMaxBytes) {
    self.adapter = adapter
    self.maxContextBytes = maxContextBytes
  }

  // MARK: Public

  public func activate() {
    guard adapter.isSupported else {
      return
    }
    let isFirstRequest = state.withLock { locked -> Bool in
      guard !locked.didRequestActivation else {
        return false
      }
      locked.didRequestActivation = true
      return true
    }
    guard isFirstRequest else {
      return
    }
    adapter.activate { [weak self] event in
      self?.handle(event)
    }
  }

  public func send(_ snapshot: WatchlistSnapshot) throws {
    let data = try SnapshotCoding.encode(snapshot, maxBytes: maxContextBytes)
    state.withLock { $0.pending = data }
    flush()
  }

  public func snapshots() -> AsyncStream<WatchlistSnapshot> {
    let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    let latest = state.withLock { locked -> WatchlistSnapshot? in
      locked.continuations[id] = continuation
      return locked.latestReceived
    }
    if let latest {
      continuation.yield(latest)
    }
    continuation.onTermination = { [weak self] _ in
      self?.removeContinuation(id: id)
    }
    return stream
  }

  // MARK: Internal

  func handle(_ event: SessionEvent) {
    switch event {
      case .activated:
        if let data = adapter.receivedContextData {
          deliver(data)
        }
        flush()
      case .counterpartChanged:
        flush()
      case let .receivedContext(data):
        deliver(data)
    }
  }

  // MARK: Private

  private struct State: Sendable {
    var didRequestActivation = false
    var pending: Data?
    var latestReceived: WatchlistSnapshot?
    var continuations: [UUID: AsyncStream<WatchlistSnapshot>.Continuation] = [:]
  }

  private static let logger = Logger(subsystem: "com.chenkai.wait", category: "connectivity")

  private let adapter: any WCSessionAdapter
  private let maxContextBytes: Int
  private let state = OSAllocatedUnfairLock(initialState: State())

  private func flush() {
    guard adapter.isActivated, adapter.canSendToCounterpart else {
      return
    }
    guard let data = state.withLock({ $0.pending }) else {
      return
    }
    do {
      try adapter.updateContext(data)
      state.withLock { locked in
        if locked.pending == data {
          locked.pending = nil
        }
      }
    } catch {
      Self.logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func deliver(_ data: Data) {
    guard let snapshot = SnapshotCoding.decode(data) else {
      Self.logger.error("Dropped an application context that is not a WatchlistSnapshot")
      return
    }
    let continuations = state.withLock { locked -> [AsyncStream<WatchlistSnapshot>.Continuation] in
      if let current = locked.latestReceived, snapshot.generatedAt < current.generatedAt || snapshot == current {
        return []
      }
      locked.latestReceived = snapshot
      return Array(locked.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(snapshot)
    }
  }

  private func removeContinuation(id: UUID) {
    state.withLock { _ = $0.continuations.removeValue(forKey: id) }
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass** — NOT RUN (code-only; checked in the /tmp harness instead: GREEN = 16 of 16 pass, 11 engine + 5 coding, stable over 31 runs)

Run: the same command as Step 3.
Expected: PASS. `** TEST SUCCEEDED **`, with all 11 `ConnectivityEngineTests` passing plus the 5 `SnapshotCodingTests`.

- [x] **Step 7: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/Connectivity Wait/Packages/WaitKit/Tests/ConnectivityTests
git commit -m "$(cat <<'EOF'
feat(connectivity): add latest-wins ConnectivityEngine behind WCSessionAdapter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 2: Live client and watch store

### Task 4: Live WCSession adapter and `ConnectivityClient`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/LiveWCSessionAdapter.swift`
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/ConnectivityClient.swift`
- Create: `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/CallRecorder.swift`
- Test: `Wait/Packages/WaitKit/Tests/ConnectivityTests/ConnectivityClientTests.swift`

- [x] **Step 1: Write the call recorder**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/Support/CallRecorder.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

// MARK: - CallRecorder

actor CallRecorder {
  private(set) var values: [String] = []

  func record(_ value: String) {
    values.append(value)
  }
}
```

- [x] **Step 2: Write the failing tests**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/ConnectivityClientTests.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - ConnectivityClientTests

@Suite
struct ConnectivityClientTests {
  @Test
  func liveClientRoutesThroughTheEngine() async throws {
    let fake = FakeSessionAdapter()
    let client = ConnectivityClient.live(engine: ConnectivityEngine(adapter: fake))

    await client.activate()
    fake.completeActivation()
    try await client.send(try SnapshotFixtures.snapshot(rowCount: 1))

    #expect(fake.activationCount == 1)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func noopClientFinishesItsStreamImmediately() async {
    var count = 0
    for await _ in ConnectivityClient.noop.snapshots() {
      count += 1
    }

    #expect(count == 0)
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail** — NOT RUN (code-only)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ConnectivityTests
```
Expected: FAIL with compile error `cannot find 'ConnectivityClient' in scope`.

- [x] **Step 4: Implement the live adapter**

Create `Wait/Packages/WaitKit/Sources/Connectivity/LiveWCSessionAdapter.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import os
@preconcurrency import WatchConnectivity

// MARK: - LiveWCSessionAdapter

/// Wraps `WCSession.default`.
///
/// WCSession calls its delegate on a private background queue. The only mutable state here is the
/// event handler, and it sits behind a lock. The delegate methods stay nonisolated and only forward
/// `Sendable` values, so the Swift 6 checker is satisfied without hopping to the main actor.
final class LiveWCSessionAdapter: NSObject, WCSessionAdapter, @unchecked Sendable {
  // MARK: Lifecycle

  override init() {
    session = WCSession.isSupported() ? WCSession.default : nil
    super.init()
  }

  // MARK: Internal

  static let shared = LiveWCSessionAdapter()

  var isSupported: Bool {
    session != nil
  }

  var isActivated: Bool {
    session?.activationState == .activated
  }

  var canSendToCounterpart: Bool {
    guard let session, session.activationState == .activated else {
      return false
    }
    #if os(watchOS)
      return session.isCompanionAppInstalled
    #else
      return session.isPaired && session.isWatchAppInstalled
    #endif
  }

  var receivedContextData: Data? {
    session?.receivedApplicationContext[SnapshotCoding.contextKey] as? Data
  }

  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void) {
    guard let session else {
      return
    }
    handler.withLock { $0 = onEvent }
    session.delegate = self
    session.activate()
  }

  func updateContext(_ data: Data) throws {
    guard let session else {
      throw ConnectivityError.unsupported
    }
    try session.updateApplicationContext([SnapshotCoding.contextKey: data])
  }

  // MARK: Private

  private static let logger = Logger(subsystem: "com.chenkai.wait", category: "connectivity")

  private let session: WCSession?
  private let handler = OSAllocatedUnfairLock<(@Sendable (SessionEvent) -> Void)?>(initialState: nil)

  private func emit(_ event: SessionEvent) {
    let onEvent = handler.withLock { $0 }
    onEvent?(event)
  }
}

// MARK: WCSessionDelegate

extension LiveWCSessionAdapter: WCSessionDelegate {
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
    if let error {
      Self.logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
    }
    if activationState == .activated {
      emit(.activated)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let data = applicationContext[SnapshotCoding.contextKey] as? Data else {
      return
    }
    emit(.receivedContext(data))
  }

  #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
      // The user switched to another watch. Reactivate so the new watch gets the next context.
      session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
      emit(.counterpartChanged)
    }
  #endif

  #if os(watchOS)
    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
      emit(.counterpartChanged)
    }
  #endif
}
```

- [x] **Step 5: Implement the client**

Create `Wait/Packages/WaitKit/Sources/Connectivity/ConnectivityClient.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation

// MARK: - ConnectivityClient

/// Transport for `WatchlistSnapshot` between the phone and the watch.
/// iOS calls `send`, and watchOS consumes `snapshots()`. Both sides call `activate` once at launch.
@DependencyClient
public struct ConnectivityClient: Sendable {
  public var activate: @Sendable () async -> Void
  public var send: @Sendable (_ snapshot: WatchlistSnapshot) async throws -> Void
  public var snapshots: @Sendable () -> AsyncStream<WatchlistSnapshot> = { AsyncStream { $0.finish() } }
}

// MARK: - ConnectivityError

public enum ConnectivityError: Error, Equatable, Sendable {
  case unsupported
}

public extension ConnectivityClient {
  static let noop = ConnectivityClient(
    activate: {},
    send: { _ in },
    snapshots: { AsyncStream { $0.finish() } }
  )

  static func live(engine: ConnectivityEngine) -> ConnectivityClient {
    ConnectivityClient(
      activate: { engine.activate() },
      send: { snapshot in try engine.send(snapshot) },
      snapshots: { engine.snapshots() }
    )
  }
}

// MARK: - ConnectivityClient + DependencyKey

extension ConnectivityClient: DependencyKey {
  public static let liveValue = ConnectivityClient.live(engine: ConnectivityEngine(adapter: LiveWCSessionAdapter.shared))
  public static let previewValue = ConnectivityClient.noop
  public static let testValue = ConnectivityClient()
}

public extension DependencyValues {
  var connectivity: ConnectivityClient {
    get { self[ConnectivityClient.self] }
    set { self[ConnectivityClient.self] = newValue }
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass** — NOT RUN (code-only)

Run: the same command as Step 3.
Expected: PASS. `** TEST SUCCEEDED **`, with 2 `ConnectivityClientTests` passing plus the 16 tests from Tasks 2–3.

- [ ] **Step 7: Build for watchOS to prove the target compiles there** — NOT RUN (code-only)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild build -scheme Connectivity \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation
```
Expected: `** BUILD SUCCEEDED **`. If Xcode reports `scheme Connectivity not found`, run `xcodebuild -list` in the same directory and use the scheme it lists for the `Connectivity` library. The scheme is auto-generated per product.

- [x] **Step 8: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/Connectivity Wait/Packages/WaitKit/Tests/ConnectivityTests
git commit -m "$(cat <<'EOF'
feat(connectivity): add live WCSession adapter and ConnectivityClient

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `WatchSnapshotStore`

**Files:**
- Create: `Wait/Packages/WaitKit/Sources/Connectivity/WatchSnapshotStore.swift`
- Test: `Wait/Packages/WaitKit/Tests/ConnectivityTests/WatchSnapshotStoreTests.swift`

- [x] **Step 1: Write the failing tests**

Create `Wait/Packages/WaitKit/Tests/ConnectivityTests/WatchSnapshotStoreTests.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - WatchSnapshotStoreTests

@MainActor
@Suite
struct WatchSnapshotStoreTests {
  // MARK: Internal

  @Test
  func isEmptyUntilTheFirstSnapshot() {
    let store = WatchSnapshotStore(connectivity: .noop)

    #expect(store.snapshot == nil)
    #expect(store.isEmpty)
    #expect(store.favorites.isEmpty)
    #expect(store.others.isEmpty)
  }

  @Test
  func startActivatesAndAppliesStreamedSnapshots() async throws {
    let first = try SnapshotFixtures.snapshot(rowCount: 2)
    let second = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(60))
    let recorder = CallRecorder()
    let store = WatchSnapshotStore(connectivity: client(yielding: [first, second], recorder: recorder))

    await store.start()

    #expect(await recorder.values == ["activate"])
    #expect(store.snapshot == second)
  }

  @Test
  func anOlderSnapshotDoesNotReplaceANewerOne() async throws {
    let newer = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(60))
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let store = WatchSnapshotStore(connectivity: client(yielding: [newer, older]))

    await store.start()

    #expect(store.snapshot == newer)
  }

  @Test
  func splitsFavoritesFromOthersInSnapshotOrder() async throws {
    let snapshot = WatchlistSnapshot(
      generatedAt: SnapshotFixtures.generatedAt,
      quotesAsOf: nil,
      rows: [
        try SnapshotFixtures.row(0, isFavorite: true),
        try SnapshotFixtures.row(1, isFavorite: false),
        try SnapshotFixtures.row(2, isFavorite: true),
      ]
    )
    let store = WatchSnapshotStore(connectivity: client(yielding: [snapshot]))

    await store.start()

    #expect(store.favorites.map(\.symbol) == ["SYM0", "SYM2"])
    #expect(store.others.map(\.symbol) == ["SYM1"])
    #expect(!store.isEmpty)
  }

  @Test
  func findsARowBySymbol() async throws {
    let store = WatchSnapshotStore(connectivity: client(yielding: [try SnapshotFixtures.snapshot(rowCount: 2)]))

    await store.start()

    #expect(store.row(symbol: "SYM1")?.name == "Company 1 Holdings Incorporated")
    #expect(store.row(symbol: "NOPE") == nil)
  }

  // MARK: Private

  private func client(yielding snapshots: [WatchlistSnapshot], recorder: CallRecorder = CallRecorder()) -> ConnectivityClient {
    let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self)
    for snapshot in snapshots {
      continuation.yield(snapshot)
    }
    continuation.finish()
    return ConnectivityClient(
      activate: { await recorder.record("activate") },
      send: { _ in },
      snapshots: { stream }
    )
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail** — NOT RUN (code-only)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ConnectivityTests/WatchSnapshotStoreTests
```
Expected: FAIL with compile error `cannot find 'WatchSnapshotStore' in scope`.

- [x] **Step 3: Implement the store**

Create `Wait/Packages/WaitKit/Sources/Connectivity/WatchSnapshotStore.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Observation

// MARK: - WatchSnapshotStore

/// The watch app's model: the latest `WatchlistSnapshot` the phone sent.
/// It lives in the package rather than the watch target so it can be unit-tested.
@MainActor
@Observable
public final class WatchSnapshotStore {
  // MARK: Lifecycle

  public init(connectivity: ConnectivityClient) {
    self.connectivity = connectivity
  }

  // MARK: Public

  public private(set) var snapshot: WatchlistSnapshot?

  public var favorites: [WatchlistSnapshot.Row] {
    snapshot?.rows.filter(\.isFavorite) ?? []
  }

  public var others: [WatchlistSnapshot.Row] {
    snapshot?.rows.filter { !$0.isFavorite } ?? []
  }

  public var isEmpty: Bool {
    snapshot?.rows.isEmpty ?? true
  }

  public func row(symbol: String) -> WatchlistSnapshot.Row? {
    snapshot?.rows.first { $0.symbol == symbol }
  }

  /// Activates the session, then applies snapshots until the stream ends. The live stream never ends,
  /// so call this from `.task` and let SwiftUI cancel it.
  public func start() async {
    await connectivity.activate()
    for await incoming in connectivity.snapshots() {
      apply(incoming)
    }
  }

  // MARK: Internal

  func apply(_ incoming: WatchlistSnapshot) {
    if let snapshot, incoming.generatedAt < snapshot.generatedAt {
      return
    }
    snapshot = incoming
  }

  // MARK: Private

  private let connectivity: ConnectivityClient
}
```

- [ ] **Step 4: Run the tests to verify they pass** — NOT RUN (code-only)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ConnectivityTests
```
Expected: PASS. `** TEST SUCCEEDED **`, with 23 tests passing across the four suites.

- [x] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add Wait/Packages/WaitKit/Sources/Connectivity/WatchSnapshotStore.swift Wait/Packages/WaitKit/Tests/ConnectivityTests/WatchSnapshotStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(connectivity): add WatchSnapshotStore for the watch app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 3: Phone integration and watch rewrite

### Task 6: AppFeature activates connectivity and sends every snapshot to the watch

**Files:**
- Modify: `Wait/Packages/WaitKit/Package.swift` (the `AppFeature` and `AppFeatureTests` targets)
- Create: `Wait/Packages/WaitKit/Sources/AppFeature/SnapshotClient+Connectivity.swift`
- Modify: `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`
- Modify: the existing tests in `Wait/Packages/WaitKit/Tests/AppFeatureTests/` that reach the publish or launch paths
- Create: `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureConnectivityTests.swift`
- Delete (if present): `Wait/Shared/Connectivity.swift`
- Modify: `Wait/project.yml` (remove the single `path: Shared/Connectivity.swift` source entry under `WaitWatch`)

- [x] **Step 1: Add `Connectivity` to the AppFeature targets**

In `Wait/Packages/WaitKit/Package.swift`:
- Add the string `"Connectivity",` to the `dependencies:` array of `.target(name: "AppFeature", …)`.
- Add `"Connectivity",` to the `dependencies:` array of `.testTarget(name: "AppFeatureTests", …)`, and also `"Domain",` and `"Persistence",` if they aren't already there. The new tests import all three.

Verify:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit
awk '/\.library\(/{next} /name: "AppFeature"[,)]/{b=1; print; next} b && /\.(target|testTarget)\(/{exit} b{print}' Package.swift | grep -o '"Connectivity"' | wc -l
awk '/\.library\(/{next} /name: "AppFeatureTests"/{b=1; print; next} b && /\.(target|testTarget)\(/{exit} b{print}' Package.swift | grep -oE '"(Connectivity|Domain|Persistence)"' | sort -u | wc -l
```
Expected: `1`, then `3`. The commands count matches, not lines, because plan 02 writes the `AppFeatureTests` dependency list on a single line. Each `awk` prints only one target's block: from its `name:` line up to the next `.target(` or `.testTarget(`. It skips `.library(` product lines, so `.library(name: "AppFeature", …)` can't match.

- [x] **Step 2: Write the failing tests**

Create `Wait/Packages/WaitKit/Tests/AppFeatureTests/AppFeatureConnectivityTests.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Domain
import Foundation
import Persistence
import Testing
@testable import AppFeature

// MARK: - CallLog

private actor CallLog {
  private(set) var entries: [String] = []

  func append(_ entry: String) {
    entries.append(entry)
  }
}

// MARK: - AppFeatureConnectivityTests

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AppFeatureConnectivityTests {
  // MARK: Internal

  @Test
  func alsoSendingPublishesLocallyThenSendsToTheWatch() async {
    let log = CallLog()
    var base = SnapshotClient()
    base.publish = { _ in await log.append("publish") }
    var connectivity = ConnectivityClient.noop
    connectivity.send = { _ in await log.append("send") }

    await base.alsoSending(to: connectivity).publish(snapshot)

    #expect(await log.entries == ["publish", "send"])
  }

  @Test
  func aWatchDeliveryErrorDoesNotFailPublishing() async {
    let log = CallLog()
    var base = SnapshotClient()
    base.publish = { _ in await log.append("publish") }
    var connectivity = ConnectivityClient.noop
    connectivity.send = { _ in throw ConnectivityError.unsupported }

    await base.alsoSending(to: connectivity).publish(snapshot)

    #expect(await log.entries == ["publish"])
  }

  @Test(.timeLimit(.minutes(1)))
  func didFinishLaunchingActivatesConnectivity() async {
    let (activations, activationContinuation) = AsyncStream.makeStream(of: Void.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.connectivity = .noop
      $0.connectivity.activate = { activationContinuation.yield() }
      $0.snapshotClient.publish = { _ in }
      $0.continuousClock = ImmediateClock()
      $0.date.now = Date(timeIntervalSince1970: 1_763_800_000)
    }
    store.exhaustivity = .off

    await store.send(.appDelegate(.didFinishLaunching))

    var iterator = activations.makeAsyncIterator()
    let activated: Void? = await iterator.next()
    #expect(activated != nil)
    // `strict: false`: the effects may already have finished, which is not a failure here.
    await store.skipInFlightEffects(strict: false)
  }

  // MARK: Private

  private let snapshot = WatchlistSnapshot(generatedAt: Date(timeIntervalSince1970: 1_763_800_000), quotesAsOf: nil, rows: [])
}
```

- [ ] **Step 3: Run the tests to verify they fail** — NOT RUN (code-only)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:AppFeatureTests/AppFeatureConnectivityTests
```
Expected: FAIL with compile error `value of type 'SnapshotClient' has no member 'alsoSending'`.

- [x] **Step 4: Implement the combinator**

Create `Wait/Packages/WaitKit/Sources/AppFeature/SnapshotClient+Connectivity.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Persistence

extension SnapshotClient {
  /// Returns a copy of this client whose `publish` first runs the original (the `snapshot.json` write
  /// and the widget reload), then sends the same snapshot to the watch.
  ///
  /// It lives in AppFeature so `Connectivity`, which the watch links, doesn't depend on `Persistence`.
  /// Watch delivery is best effort: `ConnectivityEngine` keeps the latest payload until a watch can take it,
  /// so an error here never fails publishing.
  func alsoSending(to connectivity: ConnectivityClient) -> SnapshotClient {
    let publishLocally = publish
    var client = self
    client.publish = { snapshot in
      await publishLocally(snapshot)
      try? await connectivity.send(snapshot)
    }
    return client
  }
}
```

- [ ] **Step 5: Run the tests to verify the combinator passes and launch still fails** — NOT RUN (code-only)

Run: the same command as Step 3.
Expected: FAIL overall.
- `alsoSendingPublishesLocallyThenSendsToTheWatch()` and `aWatchDeliveryErrorDoesNotFailPublishing()` pass.
- `didFinishLaunchingActivatesConnectivity()` fails with "Time limit was exceeded", because nothing calls `activate` yet.

The test overrides `continuousClock` and `date` because plan 02's launch case also runs `publishSnapshot`. If the launch test fails instead with `Unimplemented: …` for another dependency, add a no-op override for the dependency named in the message to its `withDependencies` closure, re-run, and expect the time-limit failure.

- [x] **Step 6: Inject the dependency**

In `Wait/Packages/WaitKit/Sources/AppFeature/AppFeature.swift`:
- Add `import Connectivity` to the import block, keeping it alphabetical.
- Directly below the existing `@Dependency(\.snapshotClient) var snapshotClient` line (checked in Task 1 Step 6), add:

```swift
  @Dependency(\.connectivity) var connectivity
```

- [x] **Step 7: Send every published snapshot to the watch**

In the same file, the single publish call site is in plan 02's `publishSnapshot(_:)` helper. Swift 6 requires `connectivity` to be captured explicitly, so make two edits:
1. Add `connectivity` to the effect's capture list. `[clock, date, snapshotClient]` becomes `[clock, date, snapshotClient, connectivity]`.
2. Replace the substring `snapshotClient.publish(` with `snapshotClient.alsoSending(to: connectivity).publish(`.

With plan 02's code, the helper then reads:

```swift
  /// The only `snapshotClient.publish` call site: debounced 1 s by default and cancellable by `CancelID.publishSnapshot`.
  /// With `debounced: false` it publishes at once and cancels any pending debounced publish.
  private func publishSnapshot(_ inputs: WatchlistFeature.SnapshotInputs, debounced: Bool = true) -> Effect<Action> {
    .run { [clock, date, snapshotClient, connectivity] _ in
      if debounced {
        try await clock.sleep(for: .seconds(1))
      }
      await snapshotClient.alsoSending(to: connectivity).publish(WatchlistSnapshot.make(items: inputs.items, quotes: inputs.quotes, now: date.now))
    }
    .cancellable(id: CancelID.publishSnapshot, cancelInFlight: true)
  }
```

Verify:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && grep -c "snapshotClient.alsoSending(to: connectivity).publish(" Sources/AppFeature/AppFeature.swift && grep -c "snapshotClient.publish(" Sources/AppFeature/AppFeature.swift
```
Expected: `1`, then `0`. Also check the capture list: `grep -c "\[clock, date, snapshotClient, connectivity\]" Sources/AppFeature/AppFeature.swift` prints `1`.

- [x] **Step 8: Activate on launch**

In the same file, find `case .appDelegate(.didFinishLaunching):`. Plan 02's version publishes a snapshot on launch. Wrap that effect in `.merge` with an activation effect that captures `connectivity` explicitly (Swift 6). The case becomes:

```swift
          case .appDelegate(.didFinishLaunching):
            // Publish once on launch, so the widget has data even before any quote changes.
            return .merge(
              publishSnapshot(state.watchlist.snapshotInputs),
              .run { [connectivity] _ in await connectivity.activate() }
            )
```

If the case's `return` differs from `return publishSnapshot(state.watchlist.snapshotInputs)`, still wrap whatever it returns as the first argument of `.merge`. If it is `return .none`, write `return .run { [connectivity] _ in await connectivity.activate() }` instead.

Leave every other statement in that case unchanged. Verify with `grep -n -A 6 "case .appDelegate(.didFinishLaunching):" Sources/AppFeature/AppFeature.swift | grep -c "connectivity.activate()"`, and expect `1`.

- [ ] **Step 9: Run the new tests to verify they pass** — NOT RUN (code-only)

Run: the same command as Step 3.
Expected: PASS. `** TEST SUCCEEDED **`, with all 3 tests in `AppFeatureConnectivityTests` passing.

- [ ] **Step 10: Keep plan 02's AppFeature tests green** — NOT RUN (code-only; the `$0.connectivity = .noop` and `import Connectivity` edits to the 4 tests are done)

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:AppFeatureTests
```
Expected: PASS.

If any existing test fails with `Unimplemented: 'ConnectivityClient.activate'` or `Unimplemented: 'ConnectivityClient.send'`, it reaches the launch or publish path and now touches the watch. Plan 02's `didFinishLaunchingPublishesASnapshot()`, `backgroundPublishesImmediatelyAndCancelsTheDebouncedPublish()`, `becomingActiveRefreshesQuotesAndPublishesOneSnapshot()` and `burstsOfChangesPublishOnce()` are expected to be among them. Fix each one the same way:
1. Add `$0.connectivity = .noop` to that test's `withDependencies { … }` closure.
2. Add `import Connectivity` to the top of its file.
3. Re-run until the suite passes.

These are the only changes allowed to plan-02 tests in this task.

- [x] **Step 11: Remove the legacy singleton and its source entries**

Run:
```bash
cd /Users/ckai/code/Wait && grep -rn "Connectivity.shared\|final class Connectivity" --include='*.swift' Wait | grep -v "Wait/Packages/"
```
Expected: either no output, or a single line `Wait/Shared/Connectivity.swift:11:final class Connectivity: NSObject, ObservableObject {`.

- If any other file still references `Connectivity.shared`, delete those lines. They are leftovers from the deleted Waitlist screen.
- Then run `test -e Wait/Shared && git rm -r Wait/Shared`.

After plan 02's cutover, only the watch target (key `WaitWatch`, or `"WaitWatch Watch App"`; see Task 1 Step 6) still lists the file. If Task 1 Step 6 found that entry, it is a single list item under the watch target's `sources:`:

```yaml
      - path: Shared/Connectivity.swift
```

In `Wait/project.yml`, delete that one list item, plus any keys indented under it. If Task 1 Step 6 found no `Shared` line, there is nothing to delete. Either way, verify with `grep -n "Shared" Wait/project.yml` and expect no output.

- [ ] **Step 12: Regenerate and build the app** — NOT RUN (code-only; `xcodegen generate` ran, the build did not)

Run:
```bash
cd /Users/ckai/code/Wait/Wait && xcodegen generate && \
xcodebuild -project Wait.xcodeproj -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build
```
Expected: `Created project at /Users/ckai/code/Wait/Wait/Wait.xcodeproj`, then `** BUILD SUCCEEDED **`.

- [x] **Step 13: Commit**

```bash
cd /Users/ckai/code/Wait
git add -A Wait/Packages/WaitKit Wait/project.yml Wait/Wait.xcodeproj
git commit -m "$(cat <<'EOF'
feat(app): activate WatchConnectivity on launch and send each snapshot to the watch

Adds SnapshotClient.alsoSending(to:) in AppFeature and removes the legacy
Shared/Connectivity.swift singleton.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Watch app on WaitKit

**Files:**
- Move: `Wait/WaitWatch Watch App/` → `Wait/WaitWatch/`
- Delete: `Wait/WaitWatch/{ContentView,PriceHistoryDataSource,PriceHistoryNetworkClient,Size,Stock,StockCurrentQuote,StockCurrentQuoteDataSource,StockCurrentQuoteNetworkClient,StockRow,StockTypeSwitchRow,TimeSection,TradeAction}.swift`, and `Wait/WaitWatch/Info.plist` if present
- Replace: `Wait/WaitWatch/WaitWatchApp.swift`
- Create: `Wait/WaitWatch/{WatchlistListView,WatchlistRowView,WatchStockDetailView,WatchFormat}.swift`
- Modify: `Wait/project.yml` (the `WaitWatch` target and `packages:`)

- [x] **Step 1: Move the folder and delete the drifted copies**

```bash
cd /Users/ckai/code/Wait
git mv "Wait/WaitWatch Watch App" Wait/WaitWatch
git rm Wait/WaitWatch/ContentView.swift Wait/WaitWatch/PriceHistoryDataSource.swift Wait/WaitWatch/PriceHistoryNetworkClient.swift \
  Wait/WaitWatch/Size.swift Wait/WaitWatch/Stock.swift Wait/WaitWatch/StockCurrentQuote.swift \
  Wait/WaitWatch/StockCurrentQuoteDataSource.swift Wait/WaitWatch/StockCurrentQuoteNetworkClient.swift \
  Wait/WaitWatch/StockRow.swift Wait/WaitWatch/StockTypeSwitchRow.swift Wait/WaitWatch/TimeSection.swift Wait/WaitWatch/TradeAction.swift
test -f Wait/WaitWatch/Info.plist && git rm Wait/WaitWatch/Info.plist
ls Wait/WaitWatch
```
Expected: the last command lists exactly `Assets.xcassets`, `Preview Content` and `WaitWatchApp.swift`.

- [x] **Step 2: Point the watch target at WaitKit**

First find the watch target key. Plan 01 names it `WaitWatch`, but handle the older spelling too:

```bash
cd /Users/ckai/code/Wait/Wait && awk '/^targets:/{t=1; next} /^[A-Za-z]/{t=0} t && /^  "?WaitWatch( Watch App)?"?:/' project.yml
```
Expected: exactly one line, the watch key inside `targets:`. This is scoped on purpose, because the `WaitWatch` scheme key under `schemes:` has the same indentation.

- If it reads `  WaitWatch:`, no rename is needed.
- If it reads `  "WaitWatch Watch App":`, rename every reference to the target so they all say `WaitWatch`:
  - the target key itself (the block below replaces it);
  - in the `Wait` target's `dependencies:`, change `- target: "WaitWatch Watch App"` to `- target: WaitWatch`, keeping any `embed:`, `link:` or `codeSign:` keys under it exactly as they are;
  - in `schemes:`, make sure the `WaitWatch` scheme's `build.targets` maps `WaitWatch: all`, and that no scheme still names `"WaitWatch Watch App"`.

Now replace the entire watch target mapping under `targets:` with the block below, keeping the same two-space indentation as the other targets:

```yaml
  WaitWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - path: WaitWatch
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait.watchkitapp
        PRODUCT_NAME: WaitWatch
        DEVELOPMENT_TEAM: 5WDN96EM72
        CODE_SIGN_STYLE: Automatic
        GENERATE_INFOPLIST_FILE: "YES"
        INFOPLIST_KEY_CFBundleDisplayName: Wait
        INFOPLIST_KEY_WKApplication: "YES"
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.chenkai.wait
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: "NO"
        INFOPLIST_KEY_UISupportedInterfaceOrientations: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_ASSET_PATHS: "\"WaitWatch/Preview Content\""
        ENABLE_PREVIEWS: "YES"
        SKIP_INSTALL: "YES"
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "4"
        CURRENT_PROJECT_VERSION: "1"
        MARKETING_VERSION: "1.0"
    dependencies:
      - package: WaitKit
        product: Domain
      - package: WaitKit
        product: DesignSystem
      - package: WaitKit
        product: Connectivity
```

Then remove the `Money`, `Alamofire` and `SwiftyJSON` entries from the top-level `packages:` mapping. Also remove plan 01's comment line above them, `# Remote packages used only by the watch app until plan 03 rewrites it on top of WaitKit.`. If no other entries exist, the mapping ends up as:

```yaml
packages:
  WaitKit:
    path: Packages/WaitKit
```

Keep any other entry that isn't one of those three.

Verify:
```bash
cd /Users/ckai/code/Wait/Wait
grep -nE "Money|Alamofire|SwiftyJSON|WaitWatch Watch App|Remote packages used only by the watch" project.yml
grep -nE '^  WaitWatch:|target: WaitWatch' project.yml
```
Expected:
- The first command prints nothing.
- The second prints exactly three lines: the target key `  WaitWatch:` under `targets:`, the `      - target: WaitWatch` line under the `Wait` target, and the scheme key `  WaitWatch:` under `schemes:`.

- [x] **Step 3: Write the formatting helpers**

Create `Wait/WaitWatch/WatchFormat.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Domain
import Foundation

// MARK: - WatchFormat

enum WatchFormat {
  static func price(_ price: Decimal?) -> String {
    guard let price else {
      return "No quote"
    }
    return price.formatted(.currency(code: "USD"))
  }

  static func temperature(_ value: Double) -> String {
    "\(Int(value.rounded()))°"
  }

  /// `value` is a percent number (`-1.25` means −1.25 %).
  static func changePercent(_ value: Double?) -> String? {
    guard let value else {
      return nil
    }
    return (value / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
  }

  /// `distance` is `PriceLadder.distanceToBuy(from:)`: a percent number, ≥ 0 inside the buy band.
  static func distanceToBuy(_ distance: Double?) -> String? {
    guard let distance else {
      return nil
    }
    guard distance < 0 else {
      return "In buy band"
    }
    return "\((-distance / 100).formatted(.percent.precision(.fractionLength(1)))) drop to buy"
  }

}

#if DEBUG

  // MARK: - WatchPreview

  enum WatchPreview {
    static let snapshot = WatchlistSnapshot(
      generatedAt: .now,
      quotesAsOf: .now.addingTimeInterval(-300),
      rows: [
        WatchlistSnapshot.Row(
          symbol: "PINS",
          name: "Pinterest, Inc.",
          price: Decimal(string: "14.20"),
          changePercent: -1.8,
          status: .buyZone,
          temperature: 21,
          ladder: (try? PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33)) ?? .empty,
          isFavorite: true
        ),
        WatchlistSnapshot.Row(
          symbol: "NOW",
          name: "ServiceNow, Inc.",
          price: Decimal(string: "110.00"),
          changePercent: 0.6,
          status: .watch,
          temperature: 40.4,
          ladder: (try? PriceLadder(buyLow: 80, buyHigh: 90)) ?? .empty,
          isFavorite: false
        ),
      ]
    )

    @MainActor
    static func store() -> WatchSnapshotStore {
      let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self)
      continuation.yield(snapshot)
      return WatchSnapshotStore(connectivity: ConnectivityClient(activate: {}, send: { _ in }, snapshots: { stream }))
    }
  }
#endif
```

- [x] **Step 4: Write the row view**

Create `Wait/WaitWatch/WatchlistRowView.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchlistRowView

struct WatchlistRowView: View {
  let row: WatchlistSnapshot.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(row.symbol)
          .font(.headline)
        Spacer()
        if let temperature = row.temperature {
          Text(WatchFormat.temperature(temperature))
            .font(.headline.monospacedDigit())
        }
      }
      HStack {
        Text(WatchFormat.price(row.price))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        if let status = row.status {
          StatusPill(status: status, compact: true)
        }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
```

- [x] **Step 5: Write the list view**

Create `Wait/WaitWatch/WatchlistListView.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Domain
import SwiftUI

// MARK: - WatchlistListView

struct WatchlistListView: View {
  // MARK: Internal

  let store: WatchSnapshotStore

  var body: some View {
    Group {
      if store.isEmpty {
        ContentUnavailableView {
          Label("No stocks yet", systemImage: "iphone")
        } description: {
          Text("Open Wait on iPhone")
        }
      } else {
        list
      }
    }
    .navigationTitle("Wait")
    .navigationDestination(for: String.self) { symbol in
      if let row = store.row(symbol: symbol) {
        WatchStockDetailView(row: row)
      } else {
        Text("\(symbol) is no longer on your watchlist")
      }
    }
  }

  // MARK: Private

  private var list: some View {
    List {
      if !store.favorites.isEmpty {
        Section("Favorites") {
          rows(store.favorites)
        }
      }
      if !store.others.isEmpty {
        Section {
          rows(store.others)
        } header: {
          if !store.favorites.isEmpty {
            Text("Watchlist")
          }
        }
      }
      if let quotesAsOf = store.snapshot?.quotesAsOf {
        Section {
          Text("Quotes \(quotesAsOf.formatted(.relative(presentation: .named)))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func rows(_ rows: [WatchlistSnapshot.Row]) -> some View {
    ForEach(rows) { row in
      NavigationLink(value: row.symbol) {
        WatchlistRowView(row: row)
      }
    }
  }
}

#if DEBUG
  #Preview {
    let store = WatchPreview.store()
    NavigationStack {
      WatchlistListView(store: store)
    }
    .task { await store.start() }
  }

  #Preview("Empty") {
    NavigationStack {
      WatchlistListView(store: WatchSnapshotStore(connectivity: .noop))
    }
  }
#endif
```

- [x] **Step 6: Write the detail view**

Create `Wait/WaitWatch/WatchStockDetailView.swift`:

```swift
//
// Created by: Claude on 2026-11-22.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchStockDetailView

struct WatchStockDetailView: View {
  // MARK: Internal

  let row: WatchlistSnapshot.Row

  var body: some View {
    List {
      Section {
        header
      }
      if let distance = distanceText {
        Section("Buy") {
          Text(distance)
        }
      }
      Section("Ladder") {
        if row.ladder.rungs.isEmpty {
          Text("No target prices yet. Set them in Wait on iPhone.")
            .font(.footnote)
        } else {
          ForEach(row.ladder.rungs, id: \.rung) { rung in
            HStack {
              Text(rung.rung.title + (rung.isDerived ? " (derived)" : ""))
              Spacer()
              Text(rung.price.formatted(.currency(code: "USD")))
                .monospacedDigit()
            }
            .font(.footnote)
          }
        }
      }
    }
    .navigationTitle(row.symbol)
  }

  // MARK: Private

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.name)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text(WatchFormat.price(row.price))
        .font(.title3.monospacedDigit())
      if let change = WatchFormat.changePercent(row.changePercent) {
        Text(change)
          .font(.footnote.monospacedDigit())
          .foregroundStyle((row.changePercent ?? 0) < 0 ? Color.red : Color.green)
      }
      HStack {
        if let status = row.status {
          StatusPill(status: status, compact: true)
        }
        Spacer()
        if let temperature = row.temperature {
          Text(WatchFormat.temperature(temperature))
            .font(.headline.monospacedDigit())
        }
      }
    }
  }

  private var distanceText: String? {
    guard let price = row.price else {
      return nil
    }
    return WatchFormat.distanceToBuy(row.ladder.distanceToBuy(from: price))
  }
}

#if DEBUG
  #Preview {
    NavigationStack {
      WatchStockDetailView(row: WatchPreview.snapshot.rows[0])
    }
  }
#endif
```

- [x] **Step 7: Replace the app entry point**

Replace the whole contents of `Wait/WaitWatch/WaitWatchApp.swift` with:

```swift
//
// Created by: Kai Chen on 7/9/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import SwiftUI

// MARK: - WaitWatchApp

@main
struct WaitWatchApp: App {
  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        WatchlistListView(store: store)
      }
      .task {
        await store.start()
      }
    }
  }

  // MARK: Private

  @State private var store = WatchSnapshotStore(connectivity: .liveValue)
}
```

- [ ] **Step 8: Regenerate, resolve packages and build both schemes** — NOT RUN (code-only; xcodegen generate done, builds skipped)

Run:
```bash
cd /Users/ckai/code/Wait/Wait && xcodegen generate && \
xcodebuild -resolvePackageDependencies -project Wait.xcodeproj && \
xcodebuild -project Wait.xcodeproj -scheme WaitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -derivedDataPath build/DerivedData -skipMacroValidation -skipPackagePluginValidation build && \
xcodebuild -project Wait.xcodeproj -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath build/DerivedData -skipMacroValidation -skipPackagePluginValidation build
```
Expected: `Created project at …`, then `** BUILD SUCCEEDED **` twice.

Then check the generated watch Info.plist and the embedded copy:
```bash
cd /Users/ckai/code/Wait/Wait
plutil -p build/DerivedData/Build/Products/Debug-watchsimulator/WaitWatch.app/Info.plist | grep -E "WKApplication|WKCompanionAppBundleIdentifier|WKRunsIndependentlyOfCompanionApp|CFBundleIdentifier"
ls build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch
```
Expected:
- `"CFBundleIdentifier" => "com.chenkai.wait.watchkitapp"`
- `"WKApplication" => true` (or `1`)
- `"WKCompanionAppBundleIdentifier" => "com.chenkai.wait"`
- `"WKRunsIndependentlyOfCompanionApp" => false` (or `0`)
- the `ls` prints `WaitWatch.app`, which shows the phone app embeds the watch app.

- [ ] **Step 9: Prove the watch has no network code, keys or dropped packages** — PARTIAL (source grep clean; Package.resolved still lists the three packages until a real resolve, NOT RUN)

Run:
```bash
cd /Users/ckai/code/Wait/Wait && grep -rniE "apikey|twelvedata|alamofire|swiftyjson|import Money|URLSession" WaitWatch; \
grep -ciE '"identity" : "(money|alamofire|swiftyjson)"' Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```
Expected: the first command prints nothing, and the second prints `0`.

- [x] **Step 10: Commit**

```bash
cd /Users/ckai/code/Wait
git add -A Wait/WaitWatch Wait/project.yml Wait/Wait.xcodeproj
git commit -m "$(cat <<'EOF'
feat(watch): render the phone's watchlist snapshot with shared WaitKit types

Deletes the watch's drifted model copies, network clients and API keys, and drops the
project-level Money, Alamofire and SwiftyJSON packages.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Verify on paired simulators

No code changes. The goal is to see the phone's watchlist on the watch.

Run every step of this task **in one shell session**, because later steps use `PHONE_UDID` and `WATCH_UDID` from Step 1. If you open a new shell, run this first:

```bash
export PHONE_UDID=$(xcrun simctl list devices available | sed -n '/-- iOS 27.0 --/,/^--/p' | grep -E '^ +iPhone 17 \(' | grep -oE '[0-9A-F-]{36}' | head -1)
export WATCH_UDID=$(xcrun simctl list devices available | sed -n '/-- watchOS 27.0 --/,/^--/p' | grep 'Apple Watch Series 12 (42mm)' | grep -oE '[0-9A-F-]{36}' | head -1)
```

**Files:** none

- [ ] **Step 1: Find the simulators and pair them** — NOT RUN (code-only)

```bash
export PHONE_UDID=$(xcrun simctl list devices available | sed -n '/-- iOS 27.0 --/,/^--/p' | grep -E '^ +iPhone 17 \(' | grep -oE '[0-9A-F-]{36}' | head -1)
export WATCH_UDID=$(xcrun simctl list devices available | sed -n '/-- watchOS 27.0 --/,/^--/p' | grep 'Apple Watch Series 12 (42mm)' | grep -oE '[0-9A-F-]{36}' | head -1)
echo "phone=$PHONE_UDID watch=$WATCH_UDID"
xcrun simctl list pairs | grep -q "$WATCH_UDID" || xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID"
xcrun simctl list pairs | grep -A 2 "$WATCH_UDID"
```
Expected: both UDIDs print, and the pair listing shows the watch and the phone in one pair.

If `simctl pair` fails because the phone is already paired with another watch, remove that pair and pair again:
```bash
OLD_PAIR=$(xcrun simctl list pairs | grep -B 2 "$PHONE_UDID" | grep -oE '^[0-9A-F-]{36}' | head -1)
xcrun simctl unpair "$OLD_PAIR" && xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID"
```

- [ ] **Step 2: Build into a known folder, install the phone app and launch the watch app** — NOT RUN (code-only)

The phone app embeds the watch app (`Wait.app/Watch/WaitWatch.app`, checked in Task 7 Step 8). Installing the phone app on a paired phone simulator installs the watch app on the paired watch.

```bash
cd /Users/ckai/code/Wait/Wait
xcodebuild -project Wait.xcodeproj -scheme Wait -destination "platform=iOS Simulator,id=$PHONE_UDID" \
  -derivedDataPath build/DerivedData -skipMacroValidation -skipPackagePluginValidation build
xcrun simctl boot "$PHONE_UDID" 2>/dev/null; xcrun simctl boot "$WATCH_UDID" 2>/dev/null; open -a Simulator
xcrun simctl install "$PHONE_UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app
sleep 15
xcrun simctl launch "$WATCH_UDID" com.chenkai.wait.watchkitapp
```
Expected: `** BUILD SUCCEEDED **`, the install succeeds silently, and the launch prints `com.chenkai.wait.watchkitapp: <pid>`.

Fallback, only if the launch fails because the watch app isn't installed yet: install it directly, then launch again.
```bash
xcrun simctl install "$WATCH_UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch/WaitWatch.app
xcrun simctl launch "$WATCH_UDID" com.chenkai.wait.watchkitapp
```

Then take a screenshot:
```bash
xcrun simctl io "$WATCH_UDID" screenshot /tmp/wait-watch-empty.png
```
Open `/tmp/wait-watch-empty.png`: it shows "No stocks yet / Open Wait on iPhone".

- [ ] **Step 3: Seed a watchlist on the phone and launch it** — NOT RUN (code-only)

Launch the app once so plan 02's migration runs and writes its marker. Then terminate it and plant a two-item watchlist in the app group:

```bash
xcrun simctl launch "$PHONE_UDID" com.chenkai.wait; sleep 5; xcrun simctl terminate "$PHONE_UDID" com.chenkai.wait
GROUP_DIR=$(xcrun simctl get_app_container "$PHONE_UDID" com.chenkai.wait group.chenkai.wait.contents)
cat > "$GROUP_DIR/watchlist.json" <<'EOF'
[{"symbol":"AAPL","name":"Apple Inc.","ladder":{"buyLow":"150","buyHigh":"175","fair":"220","trim":"260"},"memo":"","isFavorite":true,"sortIndex":0,"checklist":[],"ladderHistory":[],"createdAt":785000000,"updatedAt":785000000},
 {"symbol":"MSFT","name":"Microsoft Corporation","ladder":{"buyHigh":"380"},"memo":"","isFavorite":false,"sortIndex":1,"checklist":[],"ladderHistory":[],"createdAt":785000000,"updatedAt":785000000}]
EOF
xcrun simctl launch "$PHONE_UDID" com.chenkai.wait
```
Expected: the phone shows AAPL under Favorites and MSFT under Watchlist. If plan 02's `WatchlistItem` JSON has keys this sample doesn't, add them from `Wait/Packages/WaitKit/Tests/PersistenceTests` fixtures. The decoder uses `decodeIfPresent` (overview §7.5), so missing optional keys are fine.

- [ ] **Step 4: Check the watch** — NOT RUN (code-only)

```bash
sleep 10; xcrun simctl io "$WATCH_UDID" screenshot /tmp/wait-watch-list.png
```
Expected: `/tmp/wait-watch-list.png` shows "Favorites: AAPL" and "Watchlist: MSFT". With a quote source configured (see Prerequisites), each row also shows a price, a `StatusPill` and a temperature such as `27°`, plus a "Quotes … ago" footer.
- If the watch still shows "No stocks yet", force a state change that publishes a new snapshot: relaunch the phone app (`xcrun simctl terminate "$PHONE_UDID" com.chenkai.wait && xcrun simctl launch "$PHONE_UDID" com.chenkai.wait`), or ask the user to toggle the star on MSFT. Wait 10 s and take the screenshot again. Pull-to-refresh is not enough: it publishes nothing when quotes don't change.
- WCSession delivery on simulators can take up to about 30 s.

- [ ] **Step 5: (manual: user) Tap through the detail screen** — SKIPPED (manual)

Ask the user to tap AAPL in the watch Simulator window and confirm the detail screen shows:
- name, price, change %, status and temperature
- a "Buy" line ("In buy band" or "x.x% drop to buy")
- the four ladder rungs

Wait for confirmation before Chunk 4.

---

## Chunk 4: Tooling, final verification and docs

### Task 9: Swift 6 SwiftFormat config (`--swiftversion 6.0`), SwiftLint excludes and gitignore

**Files:**
- Modify: `Wait/.swiftformat`
- Modify: `Wait/.swiftlint.yml`
- Modify: `.gitignore`

- [x] **Step 1: Update SwiftFormat**

In `Wait/.swiftformat`:
- Change the line `--swiftversion 5.0` to `--swiftversion 6.0`.
- Change the `--exclude` line to:

```
--exclude Tests/XCTestManifests.swift,Tests/BadConfig,Snapshots,Pods,Generated,Wait/Generated,Packages/WaitKit/.build,Packages/WaitKit/.swiftpm,build
```

- [x] **Step 2: Update SwiftLint**

In `Wait/.swiftlint.yml`, replace the `excluded:` block with the block below, and add the `deployment_target:` block directly after it:

```yaml
excluded: # paths to ignore during linting.
  - Pods
  - Wait/Generated
  - Packages/WaitKit/.build
  - Packages/WaitKit/.swiftpm
  - build

deployment_target:
  iOS_deployment_target: "17.0"
  iOSApplicationExtension_deployment_target: "17.0"
  watchOS_deployment_target: "10.0"
```

- [x] **Step 3: Ignore the package's own resolution file**

Plan 01 normally adds both lines already. Append only the ones that are missing:

```bash
cd /Users/ckai/code/Wait
grep -qxF 'Wait/Packages/WaitKit/Package.resolved' .gitignore || echo 'Wait/Packages/WaitKit/Package.resolved' >> .gitignore
grep -qxF 'Wait/Packages/WaitKit/.swiftpm/' .gitignore || echo 'Wait/Packages/WaitKit/.swiftpm/' >> .gitignore
grep -n "Packages/WaitKit" .gitignore
```
Expected: each of the two lines appears exactly once.

Then run:
```bash
cd /Users/ckai/code/Wait && git rm --cached --ignore-unmatch Wait/Packages/WaitKit/Package.resolved && git rm -r --cached --ignore-unmatch Wait/Packages/WaitKit/.swiftpm && git status --short
```
Expected: `Wait/.swiftformat` and `Wait/.swiftlint.yml` are modified. `.gitignore` is modified only if a line was appended. If they had been tracked, `Wait/Packages/WaitKit/Package.resolved` and `.swiftpm` show as deleted (`D`).

- [x] **Step 4: Lint**

Run: `cd /Users/ckai/code/Wait/Wait && swiftlint lint --quiet | grep -c " error: "`
Expected: `0`.

If the count is not 0, run `swiftlint lint --quiet | grep " error: "`.
- If more than 30 errors are in files this plan didn't create or modify, stop and report the list to the user. That is pre-existing debt, not something to fix here.
- Otherwise, fix each reported line in place (lint fixes only, no behavior changes) and re-run until it prints `0`.

Warnings are allowed.

- [ ] **Step 5: (optional) Format check** — NOT RUN (SwiftFormat not installed)

Only if SwiftFormat is installed (`brew install swiftformat`): run `cd /Users/ckai/code/Wait/Wait && swiftformat --lint .` and apply `swiftformat .` to files this plan created. The step passes whether or not SwiftFormat is installed.

- [x] **Step 6: Commit**

```bash
cd /Users/ckai/code/Wait
git add -A .gitignore Wait/.swiftformat Wait/.swiftlint.yml Wait/Packages/WaitKit
git commit -m "$(cat <<'EOF'
chore(tooling): Swift 6 SwiftFormat config, SwiftLint package excludes and deployment targets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Final verification of the iOS side

No code changes unless a check fails. A failing check means stop and fix it before Task 11, using superpowers:systematic-debugging.

**Files:** none

- [ ] **Step 1: Run all package tests**

Run:
```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build the app and the watch**

Run:
```bash
cd /Users/ckai/code/Wait/Wait && xcodebuild -project Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation build && \
xcodebuild -project Wait.xcodeproj -scheme WaitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build
```
Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm the project regenerates cleanly**

Run: `cd /Users/ckai/code/Wait/Wait && xcodegen generate && git status --short Wait.xcodeproj project.yml`
Expected: no output. The committed project matches `project.yml`.

- [ ] **Step 4: Run the secret scan**

Run: `cd /Users/ckai/code/Wait && ./scripts/check-secrets.sh; echo "exit=$?"`
Expected: the last line is `exit=0`.

- [ ] **Step 5: Run the leftover guards**

Run:
```bash
cd /Users/ckai/code/Wait
git ls-files "Wait/WaitWatch Watch App" Wait/Shared | wc -l
git grep -n "Connectivity.shared" -- '*.swift' | wc -l
grep -nE "Money|Alamofire|SwiftyJSON|Shake|SwiftyBeaver" Wait/project.yml Wait/Packages/WaitKit/Package.swift | wc -l
```
Expected: `0`, `0`, `0`.

---

### Task 11: Rewrite CLAUDE.md for the iOS side and refresh the WaitKit README

**Files:**
- Modify: `CLAUDE.md`
- Create or replace: `Wait/Packages/WaitKit/README.md`

- [ ] **Step 1: Check the real names the docs mention**

The text in Steps 3–4 names things plans 01–02 created. Check each name against the code before writing:

```bash
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit
grep -n "platforms:" Package.swift
grep -nE "case (useCache|reload|cacheOnly)" Sources/MarketDataClient/CachePolicy.swift
grep -rn "publishSnapshot" Sources/AppFeature/AppFeature.swift
grep -rnE "\.seconds\(1\)|milliseconds\(1000\)" Sources/AppFeature/AppFeature.swift
grep -n "LegacyMigration" Sources/AppFeature/AppDelegate.swift || grep -rn "LegacyMigration" /Users/ckai/code/Wait/Wait/Wait/*.swift
test -d Sources/MarketDataClient/TwelveData && echo "upstream=twelveData" || echo "upstream=backend"
grep -n "static func cached\|static func twelveData\|static func backend" Sources/MarketDataClient/*.swift Sources/MarketDataClient/*/*.swift
```

Expected:
- `platforms: [.iOS(.v17), .watchOS(.v10)]`.
- All three cases `useCache`, `reload` and `cacheOnly`.
- At least one `publishSnapshot` line and one 1-second duration in `AppFeature.swift`.
- A `LegacyMigration` call inside the AppDelegate's lazy store. Plan 02 puts `AppDelegate` in `Packages/WaitKit/Sources/AppFeature/AppDelegate.swift`. The second location, the app target `Wait/Wait/*.swift`, is only searched if the first grep finds nothing.
- `upstream=twelveData` (plan 04 not yet run) or `upstream=backend` (plan 04 done).
- `cached` plus the adapter matching that upstream.

If any name differs (say, a policy has another name or the debounce isn't 1 s), use the real name or value wherever Step 3 or 4 mentions it. If something is missing entirely (no `LegacyMigration` call, say), stop and ask the user. This plan doesn't own that code.

- [ ] **Step 2: Keep any server section**

Run: `cd /Users/ckai/code/Wait && grep -n "^## " CLAUDE.md`

If the output contains a heading that starts with `## Backend` (plan 04 writes ``## Backend (`server/`)`` when it ran before this plan), copy that whole section, heading included, from the heading up to the next `## ` heading or the end of the file. Keep it for Step 3.

- [ ] **Step 3: Write the new CLAUDE.md**

Replace the contents of `/Users/ckai/code/Wait/CLAUDE.md` with the text below.
- If Step 2 found a `## Backend` section, paste it unchanged, heading included, between `## Architecture` and `## Code style`.
- The **Market data** bullet below is the Twelve Data version. If Step 1 printed `upstream=backend`, replace that bullet with the backend version given right after this block.

~~~markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Wait ("Great Stock Takes Time") is a SwiftUI stock-watchlist app.
- **The ladder:** for each stock the user sets a price ladder (buy low, buy high, fair, trim, sell).
- **What the app shows:** where the current price sits on that ladder, as a status (DEEP BUY, BUY ZONE, WATCH, AT/ABOVE FAIR, TRIM, SELL) and a 0–100 temperature.
- **Targets:** an iOS 17 app, a WidgetKit extension and a watchOS 10 app.
- **CI** runs on Bitrise. Its config lives in Bitrise, not in this repo; see `docs/ci/bitrise-checklist.md`.
- **Plans and shared contracts** live in `docs/superpowers/plans/`. Start with `2026-11-22-wait-00-overview.md`, the source of truth for names, paths and wire formats.

## Commands

The Xcode project is generated by XcodeGen from `Wait/project.yml`, and the generated `Wait/Wait.xcodeproj` is committed. Never edit the project by hand: change `project.yml` and regenerate. Everything except the three thin app targets lives in the local Swift package `Wait/Packages/WaitKit`.

```sh
# Regenerate the project after any project.yml change
cd Wait && xcodegen generate

# Build the iOS app (also builds the widget and the embedded watch app)
xcodebuild -project Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build

# Build the watch app
xcodebuild -project Wait/Wait.xcodeproj -scheme WaitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build

# Run every package test target
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation

# Run one test target, suite or Swift Testing test (test ids end in "()")
#   ... -only-testing:ConnectivityTests
#   ... -only-testing:DomainTests/PriceLadderTests/validatesOrder()

# Lint (configs live in Wait/). SwiftFormat is optional: brew install swiftformat
cd Wait && swiftlint
cd Wait && swiftformat .

# Secret scan (also a Bitrise step)
./scripts/check-secrets.sh
```

- **Helper scripts** (repo root):
  - `scripts/test-waitkit.sh [Target[/Suite]]` runs package tests, all of them with no argument. It prints only errors, failing tests and the summary, and exits with `xcodebuild`'s code.
  - `scripts/build-app.sh [WaitWatch]` builds the `Wait` scheme for the iPhone 17 simulator, or the scheme you pass (such as `WaitWatch`).
  - Plans 04–06 use both scripts.
- **Sandbox:** run `xcodebuild`, `xcodegen` and the helper scripts outside any agent sandbox. SwiftPM's manifest sandbox can't nest, and it fails with `sandbox_apply: Operation not permitted`.
- **Macros:** `-skipMacroValidation` is required on the command line for the TCA and swift-dependencies macros.
- **No `swift test`:** it doesn't work, because the feature targets use iOS-only SwiftUI. Always use the `WaitKit-Package` scheme.
- **Test style:** new tests use Swift Testing. TCA tests are `@MainActor` and use `TestStore`. Fixtures live in `Tests/<Target>Tests/Fixtures/`.
- **Secrets:** keys go in `Wait/Config/Secrets.xcconfig`, which is gitignored; copy `Wait/Config/Secrets.example.xcconfig` to create it. `Wait/Config/Base.xcconfig` includes it. Never commit a key.

## Architecture

### Targets
- **Xcode targets:**
  - `Wait` (app) links `AppFeature`.
  - `WaitWidgetExtension` links `Domain`, `DesignSystem` and `Persistence`.
  - `WaitWatch` links `Domain`, `DesignSystem` and `Connectivity`.
  - The app embeds the watch app, so a watch compile error fails the iOS build.
- **WaitKit library targets** (Swift 6 language mode; dependency graph in `Wait/Packages/WaitKit/README.md`):
  - Core: `Domain` (value types and ladder math), `Logging`, `DesignSystem`.
  - `Persistence`: `@Shared` files in the app group, mutation helpers, `SnapshotStore`, `SnapshotClient`, `LegacyMigration`.
  - Clients: `MarketDataClient` (caching decorator plus upstream adapter) and `Connectivity` (WCSession).
  - Features: `ChecklistFeature`, `StockChartFeature`, `StockDetailsFeature`, `WatchlistFeature`, `SettingsFeature`, `AppFeature`.
  - Plans 04–06 add `APIClient`, `SyncClient` and `NotificationClient`.

### Data flow
- **Watchlist:** the source of truth is `@Shared(.watchlist)`, an `IdentifiedArrayOf<WatchlistItem>` stored as `watchlist.json` in the app group `group.chenkai.wait.contents`.
  - When there is no group container (package tests, unsigned builds), it falls back to Documents.
  - Mutate it only through the `Persistence` helpers (`update`, `add`, `remove`, `reorder`). They stamp `updatedAt`, truncated to milliseconds.
- **Upgrade migration:** `LegacyMigration` runs on the first launch after the upgrade, from the lazy store of the `AppDelegate` in `Sources/AppFeature/AppDelegate.swift`.
  - It converts the old Documents files (`stocks`, `checklist-<SYMBOL>`, `checklist-items.json`) and writes `migration-v1.done`.
  - Old files are left in place.
- **Market data:** `\.marketData` is `MarketDataClient.cached(.twelveData(...))`, a caching decorator around the Twelve Data stopgap adapter in `Sources/MarketDataClient/TwelveData/`. The key lives in `Secrets.xcconfig`. Plan 04 replaces this adapter with the backend.
  - The decorator applies market-hours TTLs, coalesces requests, falls back to stale data, and cools down after a 429.
  - Screens read `.cacheOnly`, then `.useCache`. Pull-to-refresh uses `.reload`. A chart fetches only its selected range.
- **Snapshot fan-out:** `AppFeature` debounces watchlist and quote changes by 1 s, then publishes a `WatchlistSnapshot` through `snapshotClient.alsoSending(to: connectivity)`, which:
  1. writes `snapshot.json` to the app group,
  2. calls `WidgetCenter.reloadAllTimelines()`,
  3. calls `WCSession.updateApplicationContext` for the watch. `ConnectivityEngine` keeps only the newest unsent payload.
- **Widget:** reads `snapshot.json`; it makes no network calls. Rows deep-link to `wait://stock/<SYMBOL>`.
- **Watch:** `WatchSnapshotStore` (in `Connectivity`) consumes `ConnectivityClient.snapshots()`.
  - The stream yields the last received context first, then newer ones; the latest `generatedAt` wins.
  - The watch never touches the network and holds no keys.
  - On simulators, pair the watch and iPhone first: `xcrun simctl pair <watch> <phone>`.

### Ladder
- `PriceLadder` (in `Domain`): validates that anchors are positive and non-decreasing. With only a buy band, it derives fair as `buyHigh × 10 / 7`.
- Temperature: interpolated linearly between knots, with tails at 0.5× the lowest anchor and 1.5× the highest.
- Status: decided by comparing the price with the anchors as `Decimal`.
- Spec and test vectors:
  - The algorithm is in overview §7.2.
  - `shared/ladder-test-vectors.json` is shared with the server's tests. Change it only together with both test suites.
- Prices are `Decimal` and are encoded as decimal strings. Never construct a `Decimal` from a `Double` literal.

### TCA conventions (TCA 1.26)
- **Reducers:** `@Reducer` and `@ObservableState`. Navigation uses `StackState` plus `.forEach`. Sheets use `@Presents` plus `.ifLet`.
- **Views:** take `@Bindable var store`. `WithViewStore` is gone.
- **Effects:** report results through success/failure action pairs, never `Result<_, any Error>`.
- **Debounce:** `continuousClock.sleep` plus `.cancellable(id:cancelInFlight:)`.
- **Dependency keys:** `\.marketData`, `\.snapshotClient`, `\.connectivity`, and later `\.apiClient`, `\.identity`, `\.keychain`, `\.syncClient`, `\.notifications`. Every client is a `@DependencyClient` with an unimplemented `testValue`. Tests override what they use; use `.noop` where one exists.

## Code style

The tools enforce this style through `Wait/.swiftformat` (Swift 6.0) and `Wait/.swiftlint.yml`:

- 2-space indent. `case` is indented inside `switch`. No explicit `self`. Implicit returns. Line length is 180.
- SwiftFormat's `organizeDeclarations` and `markTypes` rules are on:
  - Each type is preceded by `// MARK: - TypeName`.
  - Members are grouped under `// MARK: Lifecycle`, `// MARK: Public`, `// MARK: Internal` and `// MARK: Private`, in that order.
  - Protocol conformances go in extensions marked `// MARK: ProtocolName`.
- File header:
  ```
  //
  // Created by: <name> on <date>.
  // Copyright © 2021 Wait. All rights reserved.
  //
  ```
~~~

Backend version of the **Market data** bullet. Use it only if Step 1 printed `upstream=backend`:

~~~markdown
- **Market data:** `\.marketData` is `MarketDataClient.cached(.backend(...))`, a caching decorator around `Sources/MarketDataClient/Backend/`. Only our server holds provider keys; the app holds none.
~~~

Check with `grep -n "Market data" /Users/ckai/code/Wait/CLAUDE.md`: exactly one line, and it names the upstream Step 1 found.

- [ ] **Step 4: Write the WaitKit README**

Create or replace `/Users/ckai/code/Wait/Wait/Packages/WaitKit/README.md` with:

~~~markdown
# WaitKit

All of Wait's code except the three thin Xcode targets (`Wait`, `WaitWidgetExtension`, `WaitWatch`, defined in `Wait/project.yml`).
- Platforms: iOS 17 and watchOS 10.
- `swift-tools-version: 6.1`; every target uses Swift 6 language mode.

## Targets

| Target | Depends on | watchOS | Linked by |
|---|---|---|---|
| `Domain` | – | ✓ | widget, watch, everything |
| `Logging` | – (os) | ✓ | features and clients |
| `DesignSystem` | Domain | ✓ | widget, watch, features |
| `Persistence` | Domain, Logging, Sharing, IdentifiedCollections, Dependencies | ✓ | widget, features |
| `MarketDataClient` | Domain, Logging, Dependencies, DependenciesMacros | – | features |
| `Connectivity` | Domain, Dependencies, DependenciesMacros | ✓ | watch, AppFeature |
| `ChecklistFeature` | Domain, Persistence, DesignSystem, TCA | – | WatchlistFeature, SettingsFeature |
| `StockChartFeature` | Domain, MarketDataClient, DesignSystem, TCA | – | StockDetailsFeature |
| `StockDetailsFeature` | Domain, Persistence, MarketDataClient, StockChartFeature, DesignSystem, TCA | – | WatchlistFeature |
| `WatchlistFeature` | StockDetailsFeature, ChecklistFeature, Persistence, MarketDataClient, DesignSystem, TCA | – | AppFeature |
| `SettingsFeature` | ChecklistFeature, DesignSystem, TCA | – | AppFeature |
| `AppFeature` | WatchlistFeature, SettingsFeature, Persistence, Connectivity, TCA | – | app |
| `APIClient` (plan 04) | Domain, Dependencies, DependenciesMacros | – | MarketDataClient, SyncClient |
| `SyncClient` (plan 05) | Domain, Persistence, APIClient, Logging, Dependencies | – | AppFeature, SettingsFeature |
| `NotificationClient` (plan 06) | Logging, Dependencies, DependenciesMacros | – | AppFeature, SettingsFeature |

The last three rows exist only after their plan has run. Each target has a matching `<Target>Tests` test target.

## Testing

```sh
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation [-only-testing:ConnectivityTests]
```

- **No `swift test`:** it doesn't work, because the feature targets use iOS-only SwiftUI.
- **Test style:** Swift Testing (`@Suite`, `@Test`, `#expect`). TCA tests are `@MainActor` `TestStore` tests that override every dependency they touch.
- **Fixtures:**
  - Per-target fixtures live in `Tests/<Target>Tests/Fixtures/`.
  - The ladder vectors live outside the package, at `shared/ladder-test-vectors.json`. Tests find them through `#filePath` because the server reads the same file.

## Adding a target

1. Add the `.target` and its `.testTarget` to `Package.swift`. Add a `.library` product only if an Xcode target links it.
2. If an Xcode target links it, add `- package: WaitKit` / `product: <Name>` to that target's `dependencies` in `Wait/project.yml`, then run `cd Wait && xcodegen generate`.
3. Clients are `@DependencyClient` structs. Give each one an unimplemented `testValue`, a `previewValue`, and a `DependencyValues` accessor.
4. Keep watchOS-compatible targets (see the table) free of UIKit and iOS-only APIs.
~~~

- [ ] **Step 5: Commit**

```bash
cd /Users/ckai/code/Wait
git add CLAUDE.md Wait/Packages/WaitKit/README.md
git commit -m "$(cat <<'EOF'
docs: describe the WaitKit, widget and watch architecture in CLAUDE.md and the package README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Bitrise update checklist (manual: user)

**Files:**
- Create: `docs/ci/bitrise-checklist.md`

- [ ] **Step 1: Write the checklist**

Create `/Users/ckai/code/Wait/docs/ci/bitrise-checklist.md`:

~~~markdown
# Bitrise update checklist

The Bitrise workflow lives in the Bitrise dashboard, not in this repo. After plans 01–03 the old workflow can no longer build. Apply every item, then trigger a build on the branch.

- [ ] **Stack:** choose an Xcode stack ≥ 16.3 (TCA 1.26 needs swift-tools 6.1). Xcode 27 is preferred, to match local development.
- [ ] **Flags:** add `-skipMacroValidation -skipPackagePluginValidation` to every `xcodebuild` invocation (Xcode Archive, Xcode Test, Script steps).
- [ ] **Destinations:** use the stack's simulators, e.g. `platform=iOS Simulator,name=iPhone 17,OS=27.0` and `platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0`. The old `iPhone 15` destination is gone.
- [ ] **Schemes:**
  - Build the `Wait` scheme of `Wait/Wait.xcodeproj`.
  - Remove every step that uses the deleted `Color` scheme or the deleted "Unused Code" (periphery) target.
- [ ] **Tests:** replace the old test step with a Script step:
  ```sh
  cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation
  ```
- [ ] **Watch:** optionally add a Script step that builds the `WaitWatch` scheme. The `Wait` build already compiles the watch app, because the app embeds it.
- [ ] **Secrets:**
  - Add a Script step **before** the build that writes the gitignored xcconfig from Bitrise Secrets:
    ```sh
    printf 'TWELVE_DATA_API_KEY = %s\n' "$TWELVE_DATA_API_KEY" > Wait/Config/Secrets.xcconfig
    ```
    After plan 04, write `WAIT_API_BASE_URL = https:/$()/<host>` instead.
  - Store the value as a Bitrise Secret, never in `bitrise.yml`.
- [ ] **Secret scan:** add a Script step `./scripts/check-secrets.sh`, and fail the build when it exits non-zero.
- [ ] **XcodeGen:** nothing is needed in CI, because the generated project is committed. Optionally add `brew install xcodegen && cd Wait && xcodegen generate && git diff --exit-code Wait.xcodeproj` to catch a stale project.
- [ ] **Server (after plan 04):** add a Script step `test -d server && (cd server && npm ci && npm run typecheck && npm test)`, using a Node 22 step or stack.
- [ ] **Bitrise APM:** if the workflow still references the Bitrise APM token plist that plan 01 removed, delete that step, and rotate the token in Bitrise.
~~~

- [ ] **Step 2: Commit**

```bash
cd /Users/ckai/code/Wait
git add docs/ci/bitrise-checklist.md
git commit -m "$(cat <<'EOF'
docs(ci): add the Bitrise update checklist for the WaitKit, XcodeGen and TCA 1.26 move

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: (manual: user) Apply the checklist in Bitrise**

Print the checklist and ask the user to apply it in the Bitrise dashboard and trigger a build of this branch. Wait for the user to confirm a green build, or to paste the failing step's log. Then finish with superpowers:finishing-a-development-branch.
