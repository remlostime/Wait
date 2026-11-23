//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation

// MARK: - SyncMappingError

public enum SyncMappingError: Error, Equatable, Sendable {
  case invalidTimestamp(String)
  case invalidDecimal(String)
  case invalidLadder(String)
  case invalidChecklistID(String)
}

// MARK: - SyncMapping

/// Domain ↔ wire mapping for `POST /api/watchlist/sync`. Outgoing values are clamped to the server limits
/// (overview §8.4), because one oversized item fails the whole batch with a 400 and would block sync for good.
enum SyncMapping {
  // MARK: Internal

  static let maxMemoUTF16 = 10_000
  static let maxNameUTF16 = 500
  static let maxChecklistItems = 100
  static let maxLadderHistory = 200
  static let anchorFractionDigits = 6
  /// The server's decimal pattern allows 12 integer digits and 6 fraction digits (`^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$`).
  static let maxAnchor = Decimal(string: "999999999999.999999", locale: Locale(identifier: "en_US_POSIX"))!

  /// Whether every anchor of `ladder` survives the wire format: rounded to 6 decimals it must still be greater than 0
  /// and fit the 12-integer-digit pattern. The server rejects the *whole batch* otherwise (a positive anchor below
  /// 0.0000005 goes out as `"0"` and fails `INVALID_LADDER`; a 13-digit one fails the schema), and the same batch would
  /// be retried forever. `SyncPlanner` therefore keeps an item with such a ladder local-only, and `changeDTO` drops such
  /// history revisions.
  static func isRepresentable(_ ladder: PriceLadder) -> Bool {
    PriceLadder.Rung.allCases.allSatisfy { rung in
      guard let anchor = ladder.value(for: rung) else {
        return true
      }
      let rounded = roundedForWire(anchor)
      return rounded > 0 && rounded <= maxAnchor
    }
  }

  /// Matches the server's clamp (overview §8.5, server step 2).
  static let maxClockSkew: TimeInterval = 5 * 60

  /// `now` is the device clock. A stamp more than 5 minutes ahead of it (left over from a clock that has since been
  /// corrected) goes out clamped, and `SyncMerger` then adopts the clamped stamp the server echoes back.
  static func changeDTO(_ change: SyncChange, now: Date) -> WatchlistChangeDTO {
    let wireStamp = SyncStamp.string(from: min(change.stamp, now.addingTimeInterval(maxClockSkew)))
    guard let item = change.item else {
      return WatchlistChangeDTO(
        symbol: change.symbol, name: change.symbol, ladder: LadderDTO(), memo: "", isFavorite: false, sortIndex: 0,
        checklist: [], ladderHistory: [], clientUpdatedAt: wireStamp, deleted: true
      )
    }
    return WatchlistChangeDTO(
      symbol: item.symbol,
      name: sanitize(item.name, toUTF16: maxNameUTF16),
      ladder: ladderDTO(item.ladder),
      memo: sanitize(item.memo, toUTF16: maxMemoUTF16),
      isFavorite: item.isFavorite,
      sortIndex: item.sortIndex,
      checklist: item.checklist.prefix(maxChecklistItems).map {
        ChecklistItemDTO(id: $0.id.uuidString, name: sanitize($0.name, toUTF16: maxNameUTF16), isChecked: $0.isChecked)
      },
      ladderHistory: item.ladderHistory.filter { isRepresentable($0.ladder) }.suffix(maxLadderHistory).map {
        LadderRevisionDTO(date: SyncStamp.string(from: $0.date), ladder: ladderDTO($0.ladder))
      },
      clientUpdatedAt: wireStamp,
      deleted: false
    )
  }

  static func remote(_ dto: WatchlistItemDTO) throws(SyncMappingError) -> RemoteWatchlistItem {
    guard let updatedAt = SyncStamp.date(from: dto.clientUpdatedAt) else {
      throw .invalidTimestamp(dto.clientUpdatedAt)
    }
    let ladder = try parseLadder(dto.ladder, symbol: dto.symbol)
    var checklist: [ChecklistItem] = []
    for entry in dto.checklist {
      guard let id = UUID(uuidString: entry.id) else { throw .invalidChecklistID(entry.id) }
      checklist.append(ChecklistItem(id: id, name: entry.name, isChecked: entry.isChecked))
    }
    // History is informational, so an unreadable entry is dropped instead of rejecting the whole row.
    let history: [LadderRevision] = dto.ladderHistory.compactMap { entry in
      guard
        let date = SyncStamp.date(from: entry.date),
        let revisionLadder = try? parseLadder(entry.ladder, symbol: dto.symbol)
      else {
        return nil
      }
      return LadderRevision(date: date, ladder: revisionLadder)
    }
    let item = WatchlistItem(
      symbol: dto.symbol,
      name: dto.name,
      ladder: ladder,
      memo: dto.memo,
      isFavorite: dto.isFavorite,
      sortIndex: dto.sortIndex,
      checklist: checklist,
      ladderHistory: history,
      createdAt: history.first?.date ?? updatedAt,
      updatedAt: updatedAt
    )
    return RemoteWatchlistItem(item: item, isDeleted: dto.deleted, version: dto.version)
  }

  /// Test helper: turns a change into the row the server would echo back.
  static func itemDTO(from change: WatchlistChangeDTO, version: Int) -> WatchlistItemDTO {
    WatchlistItemDTO(
      symbol: change.symbol, name: change.name, ladder: change.ladder, memo: change.memo, isFavorite: change.isFavorite,
      sortIndex: change.sortIndex, checklist: change.checklist, ladderHistory: change.ladderHistory,
      clientUpdatedAt: change.clientUpdatedAt, deleted: change.deleted, version: version
    )
  }

  // MARK: Private

  private static let posix = Locale(identifier: "en_US_POSIX")

  private static func ladderDTO(_ ladder: PriceLadder) -> LadderDTO {
    LadderDTO(
      buyLow: decimalString(ladder.buyLow),
      buyHigh: decimalString(ladder.buyHigh),
      fair: decimalString(ladder.fair),
      trim: decimalString(ladder.trim),
      sell: decimalString(ladder.sell)
    )
  }

  private static func parseLadder(_ dto: LadderDTO, symbol: String) throws(SyncMappingError) -> PriceLadder {
    do {
      return try PriceLadder(
        buyLow: decimal(dto.buyLow),
        buyHigh: decimal(dto.buyHigh),
        fair: decimal(dto.fair),
        trim: decimal(dto.trim),
        sell: decimal(dto.sell)
      )
    } catch let error as SyncMappingError {
      throw error
    } catch {
      throw .invalidLadder(symbol)
    }
  }

  private static func decimal(_ text: String?) throws(SyncMappingError) -> Decimal? {
    guard let text else {
      return nil
    }
    guard let value = Decimal(string: text, locale: posix) else { throw .invalidDecimal(text) }
    return value
  }

  /// Rounded to 6 fraction digits (NUMERIC(18,6)). `Decimal.description` doesn't depend on the locale.
  private static func decimalString(_ value: Decimal?) -> String? {
    guard let value else {
      return nil
    }
    return roundedForWire(value).description
  }

  private static func roundedForWire(_ value: Decimal) -> Decimal {
    var value = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, anchorFractionDigits, .plain)
    return rounded
  }

  /// Removes U+0000 (Postgres `text`/`jsonb` can't store it, so the server answers 400 for the whole batch), then clamps.
  /// Stripping comes first so a NUL never uses up part of the length budget.
  private static func sanitize(_ text: String, toUTF16 limit: Int) -> String {
    let stripped = text.unicodeScalars.contains("\u{0}") ? String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\u{0}" })) : text
    return clamp(stripped, toUTF16: limit)
  }

  /// Truncates by whole grapheme clusters so the UTF-16 length (what the server's `.length` counts) stays ≤ `limit`.
  private static func clamp(_ text: String, toUTF16 limit: Int) -> String {
    guard text.utf16.count > limit else {
      return text
    }
    var count = 0
    var end = text.startIndex
    for index in text.indices {
      let width = text[index].utf16.count
      if count + width > limit { break }
      count += width
      end = text.index(after: index)
    }
    return String(text[..<end])
  }
}
