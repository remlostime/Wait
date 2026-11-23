//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SyncChange

/// One pending local change: an upsert of `item`, or a tombstone when `item` is nil.
public struct SyncChange: Equatable, Sendable {
  // MARK: Public

  public let symbol: String
  public let item: WatchlistItem?
  /// `item.updatedAt`, or the tombstone date.
  public let stamp: Date

  public var isDeletion: Bool {
    item == nil
  }

  public static func upsert(_ item: WatchlistItem) -> SyncChange {
    SyncChange(symbol: item.symbol, item: item, stamp: item.updatedAt)
  }

  public static func deletion(symbol: String, at date: Date) -> SyncChange {
    SyncChange(symbol: symbol, item: nil, stamp: date)
  }
}

// MARK: - RemoteWatchlistItem

/// A server row mapped into Domain types. `item.updatedAt` is the server's `clientUpdatedAt`.
public struct RemoteWatchlistItem: Equatable, Sendable {
  // MARK: Lifecycle

  public init(item: WatchlistItem, isDeleted: Bool, version: Int) {
    self.item = item
    self.isDeleted = isDeleted
    self.version = version
  }

  // MARK: Public

  public let item: WatchlistItem
  public let isDeleted: Bool
  public let version: Int

  public var symbol: String {
    item.symbol
  }

  public var stamp: Date {
    item.updatedAt
  }
}

// MARK: - SyncReport

public struct SyncReport: Equatable, Sendable {
  // MARK: Lifecycle

  public init(pushed: Int = 0, pulled: Int = 0, applied: Int = 0, rounds: Int = 0) {
    self.pushed = pushed
    self.pulled = pulled
    self.applied = applied
    self.rounds = rounds
  }

  // MARK: Public

  public static let empty = SyncReport()

  /// Changes sent to the server.
  public var pushed: Int
  /// Rows received from the server, echoes included.
  public var pulled: Int
  /// Remote rows that were newer than the local copy and replaced or deleted it.
  public var applied: Int
  /// HTTP round trips.
  public var rounds: Int

  public static func + (lhs: SyncReport, rhs: SyncReport) -> SyncReport {
    SyncReport(
      pushed: lhs.pushed + rhs.pushed,
      pulled: lhs.pulled + rhs.pulled,
      applied: lhs.applied + rhs.applied,
      rounds: lhs.rounds + rhs.rounds
    )
  }

  public static func += (lhs: inout SyncReport, rhs: SyncReport) {
    lhs = lhs + rhs
  }
}
