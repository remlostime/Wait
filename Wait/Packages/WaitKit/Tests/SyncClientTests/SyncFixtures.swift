//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
@testable import SyncClient

/// 2026-11-20T15:00:00.000Z plus `milliseconds`.
func stamp(_ milliseconds: Int64 = 0) -> Date {
  SyncStamp.date(milliseconds: 1_795_186_800_000 + milliseconds)
}

func makeItem(
  _ symbol: String,
  memo: String = "",
  isFavorite: Bool = false,
  sortIndex: Int = 0,
  ladder: PriceLadder = .empty,
  updatedAt: Date = stamp()
) -> WatchlistItem {
  WatchlistItem(
    symbol: symbol,
    name: "\(symbol) Inc.",
    ladder: ladder,
    memo: memo,
    isFavorite: isFavorite,
    sortIndex: sortIndex,
    checklist: [],
    ladderHistory: [],
    createdAt: stamp(),
    updatedAt: updatedAt
  )
}

func remote(_ item: WatchlistItem, deleted: Bool = false, version: Int = 1) -> RemoteWatchlistItem {
  RemoteWatchlistItem(item: item, isDeleted: deleted, version: version)
}
