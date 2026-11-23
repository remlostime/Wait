//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - TemperatureBand

public enum TemperatureBand: String, CaseIterable, Sendable {
  case freezing
  case cold
  case neutral
  case warm
  case hot

  // MARK: Public

  public var title: String {
    switch self {
      case .freezing: "Freezing"
      case .cold: "Cold"
      case .neutral: "Neutral"
      case .warm: "Warm"
      case .hot: "Hot"
    }
  }
}

// MARK: - Temperature

/// 0 means cold/cheap and 100 means hot/expensive. Interpolated from the ladder knots.
public struct Temperature: Equatable, Sendable {
  // MARK: Lifecycle

  public init(value: Double) {
    self.value = value
  }

  // MARK: Public

  public let value: Double

  public var band: TemperatureBand {
    switch value {
      case ..<20: .freezing
      case ..<40: .cold
      case ..<60: .neutral
      case ..<80: .warm
      default: .hot
    }
  }

  /// Whole-degree label, e.g. "27°".
  public var formatted: String {
    "\(Int(value.rounded()))°"
  }
}
