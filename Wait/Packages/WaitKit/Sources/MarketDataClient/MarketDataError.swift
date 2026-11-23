//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - PartialQuotesError

/// An upstream `quotes` call got some quotes before a later chunk failed. `CachingMarketDataClient` keeps the quotes,
/// starts the cooldown when `underlying` is a rate limit, and fills the rest from stale entries.
public struct PartialQuotesError: Error, Sendable {
  public init(quotes: [Quote], underlying: MarketDataError) {
    self.quotes = quotes
    self.underlying = underlying
  }

  public init(quotes: [Quote], retryAfter: Duration?) {
    self.init(quotes: quotes, underlying: .rateLimited(retryAfter: retryAfter))
  }

  public let quotes: [Quote]
  public let underlying: MarketDataError

  /// Non-nil only when `underlying` is a rate limit that carries a retry delay.
  public var retryAfter: Duration? {
    if case let .rateLimited(retryAfter) = underlying { retryAfter } else { nil }
  }
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
        self = error.underlying
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
