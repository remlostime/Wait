//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import IdentifiedCollections
import Persistence

// MARK: - SyncPlanner

/// Which local changes the server hasn't acknowledged yet (overview §8.5, "Pending changes").
/// The first sync after migrating needs no special case: `acknowledged` starts empty, so every item is pending.
public enum SyncPlanner {
  /// The sync endpoint's symbol pattern (`SYNC_SYMBOL_PATTERN` in `server/src/schemas/watchlist.ts`).
  /// A symbol outside it would make the server reject the whole batch with a 400 on every sync, so it stays local-only.
  public static func isSyncable(_ symbol: String) -> Bool {
    symbol.wholeMatch(of: /[A-Z0-9][A-Z0-9.\-]{0,14}/) != nil
  }

  /// An item is local-only when its symbol is outside the pattern, or when a ladder anchor can't survive the wire format
  /// (`SyncMapping.isRepresentable`): one such item would make the server reject the whole batch on every sync.
  public static func isSyncable(_ item: WatchlistItem) -> Bool {
    isSyncable(item.symbol) && SyncMapping.isRepresentable(item.ladder)
  }

  /// Symbols (items or tombstones) that `pendingChanges` leaves out, sorted. `SyncEngine` logs them.
  /// A tombstone only needs a syncable symbol, because its fields are placeholders.
  public static func unsyncableSymbols(items: IdentifiedArrayOf<WatchlistItem>, state: SyncState) -> [String] {
    Set(items.filter { !isSyncable($0) }.map(\.symbol))
      .union(state.tombstones.keys.filter { !isSyncable($0) })
      .sorted()
  }

  /// One change per symbol: whichever of the item and the tombstone is newer (the item wins a tie).
  /// Unsyncable symbols are skipped. Sorted oldest stamp first, then by symbol.
  public static func pendingChanges(items: IdentifiedArrayOf<WatchlistItem>, state: SyncState) -> [SyncChange] {
    var latest: [String: SyncChange] = [:]
    for item in items {
      latest[item.symbol] = .upsert(item)
    }
    for (symbol, date) in state.tombstones {
      if let existing = latest[symbol], SyncStamp.milliseconds(existing.stamp) >= SyncStamp.milliseconds(date) {
        continue
      }
      latest[symbol] = .deletion(symbol: symbol, at: date)
    }
    return latest.values
      .filter { isPending($0, state: state) }
      .sorted { lhs, rhs in
        let left = SyncStamp.milliseconds(lhs.stamp)
        let right = SyncStamp.milliseconds(rhs.stamp)
        return left == right ? lhs.symbol < rhs.symbol : left < right
      }
  }

  // MARK: Private

  private static func isPending(_ change: SyncChange, state: SyncState) -> Bool {
    let isSendable = change.item.map(isSyncable) ?? isSyncable(change.symbol)
    return isSendable && !SyncStamp.same(state.acknowledged[change.symbol], change.stamp)
  }
}
