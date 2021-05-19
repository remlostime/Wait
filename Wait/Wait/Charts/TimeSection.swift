// Created by kai_chen on 5/17/21.

import Foundation

public enum TimeSection: Int, CaseIterable, Codable {
  case day
  case week
  case month
  case all
}

extension TimeSection {
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

  var priceHistoryAPIParams: [String: String] {
    switch self {
      case .day:
        return ["function": "TIME_SERIES_INTRADAY", "interval": "5min"]
      case .week:
        return ["function": "TIME_SERIES_DAILY"]
      case .month:
        return ["function": "TIME_SERIES_DAILY"]
      case .all:
        return ["function": "TIME_SERIES_WEEKLY"]
    }
  }

  var priceHistoryResourceKey: String {
    switch self {
      case .day:
        return "Time Series (5min)"
      case .week:
        return "Time Series (Daily)"
      case .month:
        return "Time Series (Daily)"
      case .all:
        return "Weekly Time Series"
    }
  }

  var dateFormatter: DateFormatter {
    let dateFormatter = DateFormatter()

    switch self {
      case .day:
        dateFormatter.dateFormat = "yyyy-mm-dd hh:mm:ss"
      case .week, .month, .all:
        dateFormatter.dateFormat = "yyyy-mm-dd"
    }

    return dateFormatter
  }
}
