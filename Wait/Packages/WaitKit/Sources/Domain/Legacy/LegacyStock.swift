//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LegacyMoney

/// Decodes Flight-School `Money<USD>`. That type encoded as `{"amount": <number|string>, "currencyCode": "USD"}` and decoded single values too.
public struct LegacyMoney: Decodable, Sendable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: CodingKeys.self), keyed.contains(.amount) {
      amount = try keyed.decodeDecimal(forKey: .amount)
      return
    }
    let single = try decoder.singleValueContainer()
    if let string = try? single.decode(String.self) {
      guard let value = DecimalCoding.parse(string) else {
        throw DecodingError.dataCorruptedError(in: single, debugDescription: "Not a decimal: \(string)")
      }
      amount = value
    } else {
      amount = try single.decode(Decimal.self)
    }
  }

  // MARK: Public

  public let amount: Decimal

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case amount
  }
}

// MARK: - LegacyPriceHistory

public struct LegacyPriceHistory: Decodable, Sendable {
  public let date: Date
  public let price: LegacyMoney
}

// MARK: - LegacyStock

/// The legacy `Model.Stock` as written to `Documents/stocks`. `currentQuote` is ignored.
public struct LegacyStock: Decodable, Sendable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    symbol = try c.decode(String.self, forKey: .symbol)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    expectedPrice = try c.decodeIfPresent(LegacyMoney.self, forKey: .expectedPrice)
    memo = try c.decodeIfPresent(String.self, forKey: .memo)
    expectedPriceHistory = try c.decodeIfPresent([LegacyPriceHistory].self, forKey: .expectedPriceHistory)
  }

  // MARK: Public

  public let symbol: String
  public let name: String?
  public let expectedPrice: LegacyMoney?
  public let memo: String?
  public let expectedPriceHistory: [LegacyPriceHistory]?

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, expectedPrice, memo, expectedPriceHistory
  }
}

// MARK: - WatchlistItem + Legacy

public extension WatchlistItem {
  /// Overview §7.6:
  /// - `expectedPrice` becomes `buyHigh`, rounded to 4 decimal places. A value ≤ 0 gives an empty ladder.
  /// - Each history entry becomes `LadderRevision(buyHigh:)`.
  /// - `isFavorite` is false.
  /// - `createdAt` is the first history date, otherwise `now`. All dates are truncated to milliseconds (D21).
  init?(legacy: LegacyStock, index: Int, checklist: [ChecklistItem], now: Date) {
    let symbol = legacy.symbol.trimmingCharacters(in: .whitespaces)
    guard !symbol.isEmpty, symbol != "Empty" else {
      return nil
    }
    let history: [LadderRevision] = (legacy.expectedPriceHistory ?? []).compactMap { entry in
      let price = entry.price.amount.rounded(scale: 4)
      guard price > 0, let ladder = try? PriceLadder(buyHigh: price) else {
        return nil
      }
      return LadderRevision(date: entry.date, ladder: ladder)
    }
    let buyHigh = legacy.expectedPrice.map { $0.amount.rounded(scale: 4) }
    let ladder = buyHigh.flatMap { $0 > 0 ? try? PriceLadder(buyHigh: $0) : nil } ?? .empty
    let stamp = now.truncatedToMilliseconds
    self.init(
      symbol: symbol,
      name: legacy.name ?? symbol,
      ladder: ladder,
      memo: legacy.memo ?? "",
      isFavorite: false,
      sortIndex: index,
      checklist: checklist,
      ladderHistory: Array(history.suffix(LadderRevision.maxCount)),
      createdAt: legacy.expectedPriceHistory?.first?.date ?? stamp,
      updatedAt: stamp
    )
  }
}

// MARK: - LegacyStockMapper

public enum LegacyStockMapper {
  /// Skips `"Empty"`, keeps the first occurrence of each mapped symbol (trimmed, upper-cased), and assigns `sortIndex` by output position.
  /// `checklists` is keyed by that same mapped symbol (from the `checklist-<SYMBOL>` files).
  public static func items(
    from stocks: [LegacyStock],
    checklists: [String: [ChecklistItem]],
    template: [ChecklistItem],
    now: Date
  ) -> [WatchlistItem] {
    var seen = Set<String>()
    var result: [WatchlistItem] = []
    for stock in stocks {
      let key = mappedSymbol(stock.symbol)
      guard !seen.contains(key) else {
        continue
      }
      guard let item = WatchlistItem(legacy: stock, index: result.count, checklist: checklists[key] ?? template, now: now) else {
        continue
      }
      seen.insert(key)
      result.append(item)
    }
    return result
  }

  /// The symbol a legacy row maps to: trimmed and upper-cased. Use it for dedupe and checklist lookups.
  public static func mappedSymbol(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespaces).uppercased()
  }
}
