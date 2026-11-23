//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Domain
import Foundation

// MARK: - WatchFormat

enum WatchFormat {
  static func price(_ price: Decimal?) -> String {
    guard let price else {
      return "No quote"
    }
    return price.formatted(.currency(code: "USD"))
  }

  static func temperature(_ value: Double) -> String {
    "\(Int(value.rounded()))°"
  }

  /// `value` is a percent number (`-1.25` means −1.25 %).
  static func changePercent(_ value: Double?) -> String? {
    guard let value else {
      return nil
    }
    return (value / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
  }

  /// `distance` is `PriceLadder.distanceToBuy(from:)`: a percent number, ≥ 0 inside the buy band.
  /// `status` picks the wording inside the band: `.deepBuy` (at or below `buyLow`) reads "Deep buy", like `LadderStatus.title`.
  static func distanceToBuy(_ distance: Double?, status: LadderStatus?) -> String? {
    guard let distance else {
      return nil
    }
    guard distance < 0 else {
      return status == .deepBuy ? "Deep buy" : "In buy band"
    }
    return "\((-distance / 100).formatted(.percent.precision(.fractionLength(1)))) drop to buy"
  }
}

#if DEBUG

  // MARK: - WatchPreview

  enum WatchPreview {
    static let snapshot = WatchlistSnapshot(
      generatedAt: .now,
      quotesAsOf: .now.addingTimeInterval(-300),
      rows: [
        WatchlistSnapshot.Row(
          symbol: "PINS",
          name: "Pinterest, Inc.",
          price: Decimal(string: "14.20"),
          changePercent: -1.8,
          status: .buyZone,
          temperature: 21,
          ladder: (try? PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33)) ?? .empty,
          isFavorite: true
        ),
        WatchlistSnapshot.Row(
          symbol: "NOW",
          name: "ServiceNow, Inc.",
          price: Decimal(string: "110.00"),
          changePercent: 0.6,
          status: .watch,
          temperature: 40.4,
          ladder: (try? PriceLadder(buyLow: 80, buyHigh: 90)) ?? .empty,
          isFavorite: false
        ),
      ]
    )

    @MainActor
    static func store() -> WatchSnapshotStore {
      let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self)
      continuation.yield(snapshot)
      return WatchSnapshotStore(connectivity: ConnectivityClient(activate: {}, send: { _ in }, snapshots: { stream }))
    }
  }
#endif
