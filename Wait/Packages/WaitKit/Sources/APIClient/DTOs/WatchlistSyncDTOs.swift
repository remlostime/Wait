//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderDTO

/// Unset rungs are always sent as explicit `null` and are accepted as null or missing.
public struct LadderDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(buyLow: String? = nil, buyHigh: String? = nil, fair: String? = nil, trim: String? = nil, sell: String? = nil) {
    self.buyLow = buyLow
    self.buyHigh = buyHigh
    self.fair = fair
    self.trim = trim
    self.sell = sell
  }

  // MARK: Public

  public var buyLow: String?
  public var buyHigh: String?
  public var fair: String?
  public var trim: String?
  public var sell: String?

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(buyLow, forKey: .buyLow)
    try container.encode(buyHigh, forKey: .buyHigh)
    try container.encode(fair, forKey: .fair)
    try container.encode(trim, forKey: .trim)
    try container.encode(sell, forKey: .sell)
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

// MARK: - ChecklistItemDTO

public struct ChecklistItemDTO: Codable, Equatable, Sendable {
  public init(id: String, name: String, isChecked: Bool) {
    self.id = id
    self.name = name
    self.isChecked = isChecked
  }

  public var id: String
  public var name: String
  public var isChecked: Bool
}

// MARK: - LadderRevisionDTO

public struct LadderRevisionDTO: Codable, Equatable, Sendable {
  public init(date: String, ladder: LadderDTO) {
    self.date = date
    self.ladder = ladder
  }

  public var date: String
  public var ladder: LadderDTO
}

// MARK: - WatchlistChangeDTO

/// `ItemChange` in overview §8.4.
public struct WatchlistChangeDTO: Codable, Equatable, Sendable {
  public init(
    symbol: String,
    name: String,
    ladder: LadderDTO,
    memo: String,
    isFavorite: Bool,
    sortIndex: Int,
    checklist: [ChecklistItemDTO],
    ladderHistory: [LadderRevisionDTO],
    clientUpdatedAt: String,
    deleted: Bool
  ) {
    self.symbol = symbol
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.clientUpdatedAt = clientUpdatedAt
    self.deleted = deleted
  }

  public var symbol: String
  public var name: String
  public var ladder: LadderDTO
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItemDTO]
  public var ladderHistory: [LadderRevisionDTO]
  public var clientUpdatedAt: String
  public var deleted: Bool
}

// MARK: - WatchlistItemDTO

/// `ItemDTO` in overview §8.4: an `ItemChange` plus the server `version`.
public struct WatchlistItemDTO: Codable, Equatable, Sendable {
  public init(
    symbol: String,
    name: String,
    ladder: LadderDTO,
    memo: String,
    isFavorite: Bool,
    sortIndex: Int,
    checklist: [ChecklistItemDTO],
    ladderHistory: [LadderRevisionDTO],
    clientUpdatedAt: String,
    deleted: Bool,
    version: Int
  ) {
    self.symbol = symbol
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.clientUpdatedAt = clientUpdatedAt
    self.deleted = deleted
    self.version = version
  }

  public var symbol: String
  public var name: String
  public var ladder: LadderDTO
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItemDTO]
  public var ladderHistory: [LadderRevisionDTO]
  public var clientUpdatedAt: String
  public var deleted: Bool
  public var version: Int
}

// MARK: - SyncRequestDTO

public struct SyncRequestDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(cursor: String?, changes: [WatchlistChangeDTO]) {
    self.cursor = cursor
    self.changes = changes
  }

  // MARK: Public

  public var cursor: String?
  public var changes: [WatchlistChangeDTO]

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cursor, forKey: .cursor)
    try container.encode(changes, forKey: .changes)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case cursor
    case changes
  }
}

// MARK: - SyncResponseDTO

public struct SyncResponseDTO: Codable, Equatable, Sendable {
  public init(changes: [WatchlistItemDTO], cursor: String, hasMore: Bool) {
    self.changes = changes
    self.cursor = cursor
    self.hasMore = hasMore
  }

  public var changes: [WatchlistItemDTO]
  public var cursor: String
  public var hasMore: Bool
}
