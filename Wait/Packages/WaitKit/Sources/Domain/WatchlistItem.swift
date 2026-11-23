//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WatchlistItem

/// One watched stock. Quotes are not stored here. `updatedAt` is the last-write-wins clock (overview §8.5). The init truncates both dates to milliseconds (D21).
public struct WatchlistItem: Equatable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    ladder: PriceLadder = .empty,
    memo: String = "",
    isFavorite: Bool = false,
    sortIndex: Int = 0,
    checklist: [ChecklistItem] = [],
    ladderHistory: [LadderRevision] = [],
    createdAt: Date,
    updatedAt: Date
  ) {
    self.symbol = symbol.uppercased()
    self.name = name
    self.ladder = ladder
    self.memo = memo
    self.isFavorite = isFavorite
    self.sortIndex = sortIndex
    self.checklist = checklist
    self.ladderHistory = ladderHistory
    self.createdAt = createdAt.truncatedToMilliseconds
    self.updatedAt = updatedAt.truncatedToMilliseconds
  }

  // MARK: Public

  public let symbol: String
  public var name: String
  public var ladder: PriceLadder
  public var memo: String
  public var isFavorite: Bool
  public var sortIndex: Int
  public var checklist: [ChecklistItem]
  /// Oldest first, at most `LadderRevision.maxCount` entries.
  public var ladderHistory: [LadderRevision]
  public var createdAt: Date
  public var updatedAt: Date

  public var id: String {
    symbol
  }

  public var checkedCount: Int {
    checklist.filter(\.isChecked).count
  }
}

// MARK: Codable

extension WatchlistItem: Codable {
  // MARK: Lifecycle

  /// Every field except `symbol` is optional, so the format can grow without breaking old files.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let symbol = try c.decode(String.self, forKey: .symbol).uppercased()
    let createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSinceReferenceDate: 0)
    try self.init(
      symbol: symbol,
      name: c.decodeIfPresent(String.self, forKey: .name) ?? symbol,
      ladder: c.decodeIfPresent(PriceLadder.self, forKey: .ladder) ?? .empty,
      memo: c.decodeIfPresent(String.self, forKey: .memo) ?? "",
      isFavorite: c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false,
      sortIndex: c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0,
      checklist: c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? [],
      ladderHistory: c.decodeIfPresent([LadderRevision].self, forKey: .ladderHistory) ?? [],
      createdAt: createdAt,
      updatedAt: c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(name, forKey: .name)
    try c.encode(ladder, forKey: .ladder)
    try c.encode(memo, forKey: .memo)
    try c.encode(isFavorite, forKey: .isFavorite)
    try c.encode(sortIndex, forKey: .sortIndex)
    try c.encode(checklist, forKey: .checklist)
    try c.encode(ladderHistory, forKey: .ladderHistory)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(updatedAt, forKey: .updatedAt)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, ladder, memo, isFavorite, sortIndex, checklist, ladderHistory, createdAt, updatedAt
  }
}
