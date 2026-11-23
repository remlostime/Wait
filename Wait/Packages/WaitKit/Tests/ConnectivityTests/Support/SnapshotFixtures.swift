//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotFixtures

enum SnapshotFixtures {
  static let generatedAt = Date(timeIntervalSince1970: 1_763_800_000)

  static func row(_ index: Int, isFavorite: Bool = false) throws -> WatchlistSnapshot.Row {
    WatchlistSnapshot.Row(
      symbol: "SYM\(index)",
      name: "Company \(index) Holdings Incorporated",
      price: Decimal(string: "3.133"),
      changePercent: -1.25,
      status: .buyZone,
      temperature: 27.5,
      ladder: try PriceLadder(buyLow: Decimal(string: "2.5"), buyHigh: Decimal(string: "3.2"), fair: 5),
      isFavorite: isFavorite
    )
  }

  static func snapshot(rowCount: Int, generatedAt: Date = generatedAt) throws -> WatchlistSnapshot {
    WatchlistSnapshot(
      generatedAt: generatedAt,
      quotesAsOf: generatedAt.addingTimeInterval(-60),
      rows: try (0 ..< rowCount).map { try row($0, isFavorite: $0 == 0) }
    )
  }
}
