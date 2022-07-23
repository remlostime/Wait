//
// Created by: Kai Chen on 7/23/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

enum TimeSection: Int, CaseIterable, Codable, Identifiable {
  case day
  case week
  case month
  case year
  case all

  // MARK: Public

  public var id: Int {
    rawValue
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
