//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderRung

public struct LadderRung: Equatable, Sendable {
  public let rung: PriceLadder.Rung
  public let price: Decimal
  /// True for the synthesized fair (`(buyHigh ?? buyLow) × 10 / 7`).
  public let isDerived: Bool
}

// MARK: - LadderKnot

public struct LadderKnot: Equatable, Sendable {
  public let price: Double
  public let score: Double
}

public extension PriceLadder {
  /// Only when a buy band exists and fair, trim and sell are all absent (overview §7.2 step 2).
  var derivedFair: Decimal? {
    guard fair == nil, trim == nil, sell == nil, let band = buyHigh ?? buyLow else {
      return nil
    }
    return band * 10 / 7
  }

  var effectiveFair: Decimal? {
    fair ?? derivedFair
  }

  /// Present anchors in rung order, with the derived fair in place of a missing fair.
  var rungs: [LadderRung] {
    Rung.allCases.compactMap { rung in
      if let value = value(for: rung) {
        return LadderRung(rung: rung, price: value, isDerived: false)
      }
      if rung == .fair, let derived = derivedFair {
        return LadderRung(rung: .fair, price: derived, isDerived: true)
      }
      return nil
    }
  }

  /// Anchor knots plus synthetic tails `(0.5 × lowest, 0)` and `(1.5 × highest, 100)`, stable-sorted by price.
  func knots() -> [LadderKnot] {
    let anchors = rungs.map { LadderKnot(price: $0.price.doubleValue, score: $0.rung.score) }
    guard let lowest = anchors.map(\.price).min(), let highest = anchors.map(\.price).max() else {
      return []
    }
    let all = anchors + [LadderKnot(price: lowest * 0.5, score: 0), LadderKnot(price: highest * 1.5, score: 100)]
    return all.enumerated()
      .sorted { ($0.element.price, $0.offset) < ($1.element.price, $1.offset) }
      .map(\.element)
  }

  /// Piecewise-linear, clamped. On duplicate knots the first matching segment wins. Nil when there are no anchors.
  func temperature(at price: Decimal) -> Temperature? {
    let knots = knots()
    guard let first = knots.first, let last = knots.last else {
      return nil
    }
    let p = price.doubleValue
    if p <= first.price {
      return Temperature(value: first.score)
    }
    if p >= last.price {
      return Temperature(value: last.score)
    }
    for (a, b) in zip(knots, knots.dropFirst()) where a.price <= p && p <= b.price {
      guard b.price != a.price else {
        return Temperature(value: a.score)
      }
      return Temperature(value: a.score + (p - a.price) / (b.price - a.price) * (b.score - a.score))
    }
    return Temperature(value: last.score)
  }

  /// Price vs anchors, compared as Decimal (overview §7.2 step 5).
  func status(at price: Decimal) -> LadderStatus {
    guard !isEmpty else {
      return .noAnchors
    }
    if let sell, price >= sell {
      return .sell
    }
    if let trim, price >= trim {
      return .trim
    }
    if let fair = effectiveFair, price >= fair {
      return .atOrAboveFair
    }
    if let buyLow, price <= buyLow {
      return .deepBuy
    }
    if let buyHigh, price <= buyHigh {
      return .buyZone
    }
    return .watch
  }

  /// `(buyHigh − price) / price × 100`. A value ≥ 0 means the price is inside the buy band.
  func distanceToBuy(from price: Decimal) -> Double? {
    guard let buyHigh, price > 0 else {
      return nil
    }
    return ((buyHigh - price) / price * 100).doubleValue
  }
}
