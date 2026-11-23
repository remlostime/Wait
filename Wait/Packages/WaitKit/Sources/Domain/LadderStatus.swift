//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderStatus

/// Raw values are the wire strings shared with the server (overview §7.1).
public enum LadderStatus: String, Codable, CaseIterable, Sendable {
  case deepBuy = "DEEP_BUY"
  case buyZone = "BUY_ZONE"
  case watch = "WATCH"
  case atOrAboveFair = "AT_OR_ABOVE_FAIR"
  case trim = "TRIM"
  case sell = "SELL"
  case noAnchors = "NO_ANCHORS"

  // MARK: Public

  /// 0 (cheapest) … 5 (richest). Nil for `noAnchors`.
  public var rank: Int? {
    switch self {
      case .deepBuy: 0
      case .buyZone: 1
      case .watch: 2
      case .atOrAboveFair: 3
      case .trim: 4
      case .sell: 5
      case .noAnchors: nil
    }
  }

  public var title: String {
    switch self {
      case .deepBuy: "Deep Buy"
      case .buyZone: "Buy Zone"
      case .watch: "Watch"
      case .atOrAboveFair: "At/Above Fair"
      case .trim: "Trim"
      case .sell: "Sell"
      case .noAnchors: "No Anchors"
    }
  }

  public var isBuyZone: Bool {
    self == .deepBuy || self == .buyZone
  }
}
