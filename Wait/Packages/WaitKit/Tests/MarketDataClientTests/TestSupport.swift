//
// Created by: Claude on 2026-11-23.
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

  /// `batchLimit` imitates a free tier: a request for more symbols returns the first `batchLimit` quotes in a `PartialQuotesError`,
  /// which carries `batchError` (a 429 by default).
  init(delay: Duration = .zero, batchLimit: Int? = nil, batchError: MarketDataError = .rateLimited(retryAfter: .seconds(60))) {
    self.delay = delay
    self.batchLimit = batchLimit
    self.batchError = batchError
  }

  // MARK: Internal

  let delay: Duration
  let batchLimit: Int?
  let batchError: MarketDataError

  /// How many upstream calls were cancelled while they slept.
  var cancelledCalls: Int {
    lock.withLock { recordedCancellations }
  }

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
        try await self.pause()
        if let error {
          throw error
        }
        if let limit = self.batchLimit, symbols.count > limit {
          throw PartialQuotesError(quotes: symbols.prefix(limit).map { Quote(symbol: $0, price: 100, asOf: fridayOpen) }, underlying: self.batchError)
        }
        return symbols.map { Quote(symbol: $0, price: 100, asOf: fridayOpen) }
      },
      series: { symbol, range, _ in
        let error = self.lock.withLock {
          self.recordedSeriesCalls += 1
          return self.scriptedError
        }
        try await self.pause()
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
  private var recordedCancellations = 0
  private var recordedQuoteCalls: [[String]] = []
  private var recordedSeriesCalls = 0
  private var scriptedError: MarketDataError?

  private func pause() async throws {
    guard delay > .zero else {
      return
    }
    do {
      try await Task.sleep(for: delay)
    } catch {
      lock.withLock { recordedCancellations += 1 }
      throw error
    }
  }
}
