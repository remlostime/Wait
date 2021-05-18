// Created by kai_chen on 5/17/21.

import Foundation

public enum TimeSection: Int, CaseIterable, Codable {
  case day
  case week
  case month
  case all

  // MARK: Internal

  var timeSectionDescription: String {
    switch self {
      case .day:
        return "1D"
      case .week:
        return "1W"
      case .month:
        return "1M"
      case .all:
        return "All"
    }
  }

  var dateLabelDescription: String {
    switch self {
      case .day:
        return "Today"
      case .week:
        return "Week"
      case .month:
        return "Month"
      case .all:
        return "All"
    }
  }
}
