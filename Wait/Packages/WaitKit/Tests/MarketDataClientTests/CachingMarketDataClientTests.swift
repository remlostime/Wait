//
// Created by: Claude on 2026-11-23.
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
    #expect(quotes.allSatisfy { $0.isStale })
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

  @Test func nonRateLimitPartialResultKeepsTheQuotesAndSkipsTheCooldown() async throws {
    let upstream = FakeUpstream(batchLimit: 8, batchError: .network("HTTP 500"))
    let client = make(upstream, now: MutableNow(fridayOpen))
    let symbols = (0 ..< 10).map { "S\($0)" }
    let first = try await client.quotes(symbols, .useCache)
    #expect(first.map(\.symbol) == Array(symbols.prefix(8)))
    _ = try await client.quotes(symbols, .reload) // no cooldown: the next call reaches the upstream again
    #expect(upstream.quoteCalls.count == 2)
  }

  @Test func cancellingOneOfTwoCoalescedWaitersLeavesTheOtherWithItsValue() async throws {
    let upstream = FakeUpstream(delay: .milliseconds(400))
    let client = make(upstream, now: MutableNow(fridayOpen))
    let first = Task { try await client.series("AAPL", .oneYear, .useCache) }
    try await Task.sleep(for: .milliseconds(30))
    let second = Task { try await client.series("AAPL", .oneYear, .useCache) }
    try await Task.sleep(for: .milliseconds(30))
    let clock = ContinuousClock()
    let start = clock.now
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(start.duration(to: clock.now) < .milliseconds(200)) // promptly, not after the 400 ms fetch
    let series = try await second.value
    #expect(series.symbol == "AAPL")
    #expect(upstream.seriesCalls == 1)
    #expect(upstream.cancelledCalls == 0)
  }

  @Test func cancellingTheOnlyWaiterCancelsTheUpstreamFetch() async throws {
    let upstream = FakeUpstream(delay: .seconds(5))
    let client = make(upstream, now: MutableNow(fridayOpen))
    let task = Task { try await client.series("AAPL", .oneYear, .useCache) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    for _ in 0 ..< 100 where upstream.cancelledCalls == 0 {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(upstream.cancelledCalls == 1)
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
