//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderValidationError

public enum LadderValidationError: Error, Equatable, Sendable {
  case nonPositive(PriceLadder.Rung)
  case outOfOrder(lower: PriceLadder.Rung, upper: PriceLadder.Rung)
}

// MARK: - PriceLadder

/// The user's price anchors (overview §7.2). Present anchors must be > 0 and non-decreasing in rung order.
public struct PriceLadder: Hashable, Sendable {
  // MARK: Lifecycle

  public init(
    buyLow: Decimal? = nil,
    buyHigh: Decimal? = nil,
    fair: Decimal? = nil,
    trim: Decimal? = nil,
    sell: Decimal? = nil
  ) throws(LadderValidationError) {
    let ordered: [(Rung, Decimal?)] = [(.buyLow, buyLow), (.buyHigh, buyHigh), (.fair, fair), (.trim, trim), (.sell, sell)]
    var previous: (rung: Rung, value: Decimal)?
    for (rung, value) in ordered {
      guard let value else {
        continue
      }
      guard value > 0 else {
        throw .nonPositive(rung)
      }
      if let previous, value < previous.value {
        throw .outOfOrder(lower: previous.rung, upper: rung)
      }
      previous = (rung, value)
    }
    self.init(unchecked: buyLow, buyHigh, fair, trim, sell)
  }

  private init(unchecked buyLow: Decimal?, _ buyHigh: Decimal?, _ fair: Decimal?, _ trim: Decimal?, _ sell: Decimal?) {
    self.buyLow = buyLow
    self.buyHigh = buyHigh
    self.fair = fair
    self.trim = trim
    self.sell = sell
  }

  // MARK: Public

  public enum Rung: String, CaseIterable, Codable, Sendable {
    case buyLow
    case buyHigh
    case fair
    case trim
    case sell

    // MARK: Public

    public var score: Double {
      switch self {
        case .buyLow: 10
        case .buyHigh: 30
        case .fair: 50
        case .trim: 80
        case .sell: 95
      }
    }

    public var title: String {
      switch self {
        case .buyLow: "Buy low"
        case .buyHigh: "Buy high"
        case .fair: "Fair"
        case .trim: "Trim"
        case .sell: "Sell"
      }
    }
  }

  public static let empty = PriceLadder(unchecked: nil, nil, nil, nil, nil)

  public private(set) var buyLow: Decimal?
  public private(set) var buyHigh: Decimal?
  public private(set) var fair: Decimal?
  public private(set) var trim: Decimal?
  public private(set) var sell: Decimal?

  public var isEmpty: Bool {
    buyLow == nil && buyHigh == nil && fair == nil && trim == nil && sell == nil
  }

  public func value(for rung: Rung) -> Decimal? {
    switch rung {
      case .buyLow: buyLow
      case .buyHigh: buyHigh
      case .fair: fair
      case .trim: trim
      case .sell: sell
    }
  }
}

// MARK: Codable

extension PriceLadder: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        buyLow: container.decodeDecimalIfPresent(forKey: .buyLow),
        buyHigh: container.decodeDecimalIfPresent(forKey: .buyHigh),
        fair: container.decodeDecimalIfPresent(forKey: .fair),
        trim: container.decodeDecimalIfPresent(forKey: .trim),
        sell: container.decodeDecimalIfPresent(forKey: .sell)
      )
    } catch let error as LadderValidationError {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ladder: \(error)"))
    }
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeDecimalIfPresent(buyLow, forKey: .buyLow)
    try container.encodeDecimalIfPresent(buyHigh, forKey: .buyHigh)
    try container.encodeDecimalIfPresent(fair, forKey: .fair)
    try container.encodeDecimalIfPresent(trim, forKey: .trim)
    try container.encodeDecimalIfPresent(sell, forKey: .sell)
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
