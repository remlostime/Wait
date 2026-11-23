//
// Created by: Claude on 2026-11-23.
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
