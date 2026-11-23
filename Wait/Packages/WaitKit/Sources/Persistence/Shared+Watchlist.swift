//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Sharing

// MARK: - WatchlistSection

public enum WatchlistSection: Hashable, Sendable {
  case favorites
  case others
}

public extension Shared where Value == IdentifiedArrayOf<WatchlistItem> {
  func update(_ symbol: String, now: Date, _ body: (inout WatchlistItem) -> Void) {
    withLock { items in
      guard var item = items[id: symbol] else {
        return
      }
      body(&item)
      item.updatedAt = now.truncatedToMilliseconds
      items[id: symbol] = item
    }
  }

  /// Appends at the end of the list (`max(sortIndex) + 1`). Returns false if the symbol is already present.
  @discardableResult
  func add(_ item: WatchlistItem, now: Date) -> Bool {
    @Shared<SyncState>(.syncState) var syncState
    $syncState.withLock { $0.tombstones[item.symbol] = nil }
    return withLock { items in
      guard items[id: item.symbol] == nil else {
        return false
      }
      var appended = item
      appended.sortIndex = (items.map(\.sortIndex).max() ?? -1) + 1
      appended.updatedAt = now.truncatedToMilliseconds
      items.append(appended)
      return true
    }
  }

  func remove(_ symbol: String, now: Date) {
    if wrappedValue[id: symbol] != nil {
      @Shared<SyncState>(.syncState) var syncState
      $syncState.withLock { $0.tombstones[symbol] = now.truncatedToMilliseconds }
    }
    withLock { items in
      _ = items.remove(id: symbol)
    }
  }

  /// SwiftUI `onMove` semantics inside one section. The section's existing `sortIndex` slots are reused, so the other section is untouched.
  func reorder(section: WatchlistSection, from source: IndexSet, to destination: Int, now: Date) {
    withLock { items in
      let sectionItems = items
        .filter { section == .favorites ? $0.isFavorite : !$0.isFavorite }
        .sorted { $0.sortIndex < $1.sortIndex }
      let slots = sectionItems.map(\.sortIndex)
      let moving = source.sorted().map { sectionItems[$0] }
      var reordered = sectionItems.enumerated().filter { !source.contains($0.offset) }.map(\.element)
      let insertAt = destination - source.filter { $0 < destination }.count
      reordered.insert(contentsOf: moving, at: max(0, min(insertAt, reordered.count)))
      let stamp = now.truncatedToMilliseconds
      for (slot, item) in zip(slots, reordered) where item.sortIndex != slot {
        items[id: item.symbol]?.sortIndex = slot
        items[id: item.symbol]?.updatedAt = stamp
      }
    }
  }
}

public extension Shared where Value == WatchlistItem {
  /// For features holding a single derived `Shared<WatchlistItem>`, such as details or checklist.
  func update(now: Date, _ body: (inout WatchlistItem) -> Void) {
    withLock { item in
      body(&item)
      item.updatedAt = now.truncatedToMilliseconds
    }
  }
}
