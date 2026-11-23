//
// Created by: Claude on 2026-11-23.
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
