//
// Created by: Claude on 2026-11-23.
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
        noteFailure(partial.underlying, at: now)
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
  private var inFlight: [String: Flight] = [:]
  private var cooldownUntil: Date?

  /// One shared upstream fetch and the callers waiting on it. The fetch is cancelled once the last waiter is gone.
  private struct Flight {
    let id = UUID()
    var task: Task<Void, Never>?
    var waiters: [UUID: CheckedContinuation<Data, any Error>] = [:]
  }

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

  /// Joins the fetch already running for `key`, or starts it. Each waiter resumes on its own: a cancelled waiter throws
  /// `CancellationError` at once without disturbing the others, and the last one leaving cancels the shared fetch.
  private func coalesced(key: String, _ work: @escaping @Sendable () async throws -> Data) async throws -> Data {
    let waiterID = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        // Checked and registered in one synchronous step, so `onCancel`'s hop into the actor always sees the waiter.
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          join(key: key, waiterID: waiterID, continuation: continuation, work: work)
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(key: key, waiterID: waiterID) }
    }
  }

  private func join(
    key: String,
    waiterID: UUID,
    continuation: CheckedContinuation<Data, any Error>,
    work: @escaping @Sendable () async throws -> Data
  ) {
    if var flight = inFlight[key] {
      flight.waiters[waiterID] = continuation
      inFlight[key] = flight
      return
    }
    var flight = Flight()
    flight.waiters[waiterID] = continuation
    let flightID = flight.id
    flight.task = Task {
      let result: Result<Data, any Error>
      do {
        result = try await .success(work())
      } catch {
        result = .failure(error)
      }
      finish(key: key, flightID: flightID, result: result)
    }
    inFlight[key] = flight
  }

  private func finish(key: String, flightID: UUID, result: Result<Data, any Error>) {
    guard let flight = inFlight[key], flight.id == flightID else {
      return // every waiter already left and the fetch was cancelled
    }
    inFlight[key] = nil
    for continuation in flight.waiters.values {
      continuation.resume(with: result)
    }
  }

  private func cancelWaiter(key: String, waiterID: UUID) {
    guard var flight = inFlight[key], let continuation = flight.waiters.removeValue(forKey: waiterID) else {
      return // the fetch already finished
    }
    continuation.resume(throwing: CancellationError())
    if flight.waiters.isEmpty {
      flight.task?.cancel()
      inFlight[key] = nil
    } else {
      inFlight[key] = flight
    }
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
