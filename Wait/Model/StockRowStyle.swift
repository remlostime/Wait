//
// Created by: kai_chen on 10/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

public enum StockRowStyle: String, CaseIterable, Identifiable {
  public var id: String {
    self.rawValue
  }

  case card
  case row
}
