// Created by kai_chen on 5/17/21.

import Foundation

// MARK: - TimeSection

public enum TimeSection: Int, CaseIterable, Codable, Identifiable {
  case day
  case week
  case month
  case year
  case all

  // MARK: Public

  public var id: Int {
    rawValue
  }
}

public extension TimeSection {
  var timeSectionDescription: String {
    switch self {
      case .day:
        return "1D"
      case .week:
        return "1W"
      case .month:
        return "1M"
      case .year:
        return "1Y"
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
      case .year:
        return "Year"
      case .all:
        return "All"
    }
  }

  var dataSize: Int {
    switch self {
      case .day:
        return 80
      case .week:
        return 130
      case .month:
        return 31
      case .year:
        return 365
      case .all:
        return 365
    }
  }

  var dataInterval: String {
    switch self {
      case .day:
        return "5min"
      case .week:
        return "15min"
      case .month:
        return "1day"
      case .year:
        return "1day"
      case .all:
        return "1week"
    }
  }

  var dateFormatter: DateFormatter {
    // Date format - http://www.sdfonlinetester.info
    let dateFormatter = DateFormatter()
    switch self {
      case .day, .week:
        dateFormatter.dateFormat = "yyyy-mm-dd HH:mm:ss"
      case .month, .year, .all:
        dateFormatter.dateFormat = "yyyy-mm-dd"
    }

    return dateFormatter
  }
}
