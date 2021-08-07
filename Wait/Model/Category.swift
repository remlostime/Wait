//
// Created by: kai_chen on 8/7/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - StockCategory

public enum StockCategory: Int, CaseIterable {
  case waitlist
  case research
}

// MARK: CustomStringConvertible

extension StockCategory: CustomStringConvertible {
  public var description: String {
    switch self {
      case .waitlist:
        return "Waitlist"
      case .research:
        return "Research"
    }
  }
}

// MARK: Identifiable, Hashable

extension StockCategory: Identifiable, Hashable {
  public var id: Int {
    rawValue
  }
}

// MARK: Codable

extension StockCategory: Codable {}
