//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

public extension LadderStatus {
  var tint: Color {
    switch self {
      case .deepBuy: Palette.stockUp
      case .buyZone: Palette.stockUp.opacity(0.85)
      case .watch: .gray
      case .atOrAboveFair: Palette.warning
      case .trim: .orange
      case .sell: Palette.stockDown
      case .noAnchors: .secondary
    }
  }

  var symbolName: String {
    switch self {
      case .deepBuy: "arrow.down.circle.fill"
      case .buyZone: "checkmark.circle.fill"
      case .watch: "eye"
      case .atOrAboveFair: "equal.circle"
      case .trim: "scissors"
      case .sell: "arrow.up.circle.fill"
      case .noAnchors: "questionmark.circle"
    }
  }
}

public extension TemperatureBand {
  var tint: Color {
    switch self {
      case .freezing: .blue
      case .cold: .teal
      case .neutral: .gray
      case .warm: .orange
      case .hot: .red
    }
  }
}
