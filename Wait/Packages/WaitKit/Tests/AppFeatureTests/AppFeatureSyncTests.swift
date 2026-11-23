//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import AppFeature
import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import SyncClient
import Testing

/// Holds a fake sync open until the test calls `open()`.
private actor SyncGate {
  // MARK: Internal

  func wait() async {
    guard !isOpen else {
      return
    }
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
  func aNewerTriggerDoesNotCancelARunningSyncSoEveryRunReportsBack() async {
    @Shared(.watchlist) var items
    $items.withLock { $0 = [Self.item("AAPL")] }
    let syncs = LockIsolated(0)
    let gate = SyncGate()
    let clock = TestClock()
    let store = makeStore(syncs: syncs, clock: clock) {
      await gate.wait()
      return SyncReport(rounds: 1)
    }

    await store.send(.scenePhaseChanged(.active))
    while syncs.value < 1 { await Task.yield() }
    // An edit while the first run is still in flight: its debounce fires and joins the run (the engine is single-flight).
    await store.send(.watchlist(.favoriteSwiped(symbol: "AAPL")))
    await clock.advance(by: .seconds(2))
    while syncs.value < 2 { await Task.yield() }
    await gate.open()

    await store.receive(\.syncFinished)
    await store.receive(\.syncFinished)
    #expect(syncs.value == 2)
  }

  @Test
  func anImmediateSyncReplacesAPendingDebounce() async {
    @Shared(.watchlist) var items
    $items.withLock { $0 = [Self.item("AAPL")] }
    let syncs = LockIsolated(0)
    let clock = TestClock()
    let store = makeStore(syncs: syncs, clock: clock)

    await store.send(.watchlist(.favoriteSwiped(symbol: "AAPL")))
    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)
    await clock.advance(by: .seconds(5))

    #expect(syncs.value == 1)
  }

  @Test
  func aSyncThatAppliedRowsLoadsOnlyTheMissingQuotes() async {
    @Shared(.watchlist) var items
    $items.withLock { $0 = [Self.item("AAPL"), Self.item("MSFT")] }
    var state = AppFeature.State()
    state.watchlist.quotes["AAPL"] = Quote(symbol: "AAPL", price: 100, asOf: Date(timeIntervalSince1970: 1_795_186_800))
    let msft = Quote(symbol: "MSFT", price: 300, asOf: Date(timeIntervalSince1970: 1_795_186_800))
    let requested = LockIsolated<[[String]]>([])
    let store = makeStore(
      syncs: LockIsolated(0), state: state,
      quotes: { symbols, _ in
        requested.withValue { $0.append(symbols) }
        return [msft]
      },
      result: { SyncReport(pulled: 1, applied: 1, rounds: 1) }
    )

    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)
    await store.receive(\.watchlist.symbolQuotesLoaded)

    #expect(requested.value == [["MSFT"]])
    #expect(store.state.watchlist.quotes["MSFT"] == msft)
  }

  @Test
  func aSyncThatAppliedNothingLoadsNoQuotes() async {
    @Shared(.watchlist) var items
    $items.withLock { $0 = [Self.item("AAPL")] }
    let requested = LockIsolated<[[String]]>([])
    let store = makeStore(
      syncs: LockIsolated(0),
      quotes: { symbols, _ in
        requested.withValue { $0.append(symbols) }
        return []
      },
      result: { SyncReport(pushed: 1, pulled: 1, applied: 0, rounds: 1) }
    )

    await store.send(.watchlist(.delegate(.refreshRequested)))
    await store.receive(\.syncFinished)
    await store.skipInFlightEffects(strict: false)

    #expect(requested.value.isEmpty)
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
    state: AppFeature.State = AppFeature.State(),
    quotes: @escaping @Sendable ([String], CachePolicy) async throws -> [Quote] = { _, _ in [] },
    result: @escaping @Sendable () async throws -> SyncReport = { SyncReport(rounds: 1) }
  ) -> TestStoreOf<AppFeature> {
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = Date(timeIntervalSince1970: 1_795_186_900)
      $0.marketData.quotes = quotes
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
