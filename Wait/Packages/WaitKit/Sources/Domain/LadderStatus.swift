//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderStatus

public enum LadderStatus: String, Codable, CaseIterable, Sendable {
  case deepBuy = "DEEP_BUY"
  case buyZone = "BUY_ZONE"
  case watch = "WATCH"
  case atOrAboveFair = "AT_OR_ABOVE_FAIR"
  case trim = "TRIM"
  case sell = "SELL"
  case noAnchors = "NO_ANCHORS"
}
