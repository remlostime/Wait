//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Persistence

// MARK: - MergeResult

public struct MergeResult: Equatable, Sendable {
  public var items: IdentifiedArrayOf<WatchlistItem>
  public var state: SyncState
  /// Remote rows that were strictly newer than the local copy (or brand new) and changed local data.
  public var applied: Int
}

// MARK: - SyncMerger

/// Overview §8.5, client steps 2–3. Remote rows are written directly, never through the Persistence mutation
/// helpers, because those stamp `updatedAt = now` and would turn every remote row into a new local edit.
public enum SyncMerger {
  /// Step 2: every change sent in a request that returned 200 is acknowledged at the stamp that was sent.
  public static func acknowledge(_ sent: [SyncChange], in state: SyncState) -> SyncState {
    var state = state
    for change in sent {
      state.acknowledged[change.symbol] = change.stamp
    }
    return state
  }

  /// Step 3. A remote row is applied when there's no local copy, or when its stamp is ≥ the newest local stamp
  /// (the item's `updatedAt` or the tombstone). On a tie the server wins (plan 05 deviation 2). An older row only
  /// matters when it is a clamped echo of our own content (see `adoptClampedEcho`).
  public static func apply(
    _ remote: [RemoteWatchlistItem],
    to items: IdentifiedArrayOf<WatchlistItem>,
    state: SyncState
  ) -> MergeResult {
    var items = items
    var state = state
    var applied = 0

    for row in remote {
      let local = items[id: row.symbol]
      let tombstone = state.tombstones[row.symbol]
      let localStamp = [local?.updatedAt, tombstone].compactMap { $0 }.map(SyncStamp.milliseconds).max()
      let remoteStamp = SyncStamp.milliseconds(row.stamp)

      if let localStamp, remoteStamp < localStamp {
        adoptClampedEcho(row, local: local, tombstone: tombstone, items: &items, state: &state)
        continue
      }
      let isNewer = localStamp.map { remoteStamp > $0 } ?? true

      if row.isDeleted {
        guard local != nil || tombstone != nil else { continue }
        if local != nil, isNewer { applied += 1 }
        items.remove(id: row.symbol)
        state.tombstones[row.symbol] = row.stamp
      } else {
        var incoming = row.item
        if let local {
          incoming.createdAt = local.createdAt
        }
        if isNewer, incoming != local { applied += 1 }
        items[id: row.symbol] = incoming
        state.tombstones[row.symbol] = nil
      }
      state.acknowledged[row.symbol] = row.stamp
    }

    return MergeResult(items: items, state: state, applied: applied)
  }

  // MARK: Private

  /// The server clamps client stamps to now + 5 min (overview §8.5), and the client clamps outgoing stamps the same way
  /// (`SyncMapping.changeDTO`). When a row echoes our own content with an earlier stamp, the local copy takes the server's
  /// stamp, so later last-write-wins comparisons agree with the server. Any other older row is ignored.
  private static func adoptClampedEcho(
    _ row: RemoteWatchlistItem,
    local: WatchlistItem?,
    tombstone: Date?,
    items: inout IdentifiedArrayOf<WatchlistItem>,
    state: inout SyncState
  ) {
    if row.isDeleted {
      guard local == nil, tombstone != nil else {
        return
      }
      state.tombstones[row.symbol] = row.stamp
    } else {
      guard let local, hasSameContent(local, row.item) else {
        return
      }
      var adopted = local
      adopted.updatedAt = row.stamp
      items[id: row.symbol] = adopted
    }
    state.acknowledged[row.symbol] = row.stamp
  }

  private static func hasSameContent(_ local: WatchlistItem, _ remote: WatchlistItem) -> Bool {
    var comparable = remote
    comparable.createdAt = local.createdAt
    comparable.updatedAt = local.updatedAt
    return comparable == local
  }
}
