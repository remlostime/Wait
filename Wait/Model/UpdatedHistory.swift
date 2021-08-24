//
// Created by: kai_chen on 8/24/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftDate

public struct UpdatedHistory: Codable, Identifiable {
  public let updatedTime: Date
  public let notes: [String]
  public var id = UUID()

  public init(updatedTime: Date = Date(), notes: [String]) {
    self.updatedTime = updatedTime
    self.notes = notes
  }
}

public extension UpdatedHistory {
  var formattedHistory: String {
    var history = self.updatedTime.toFormat("MMM dd, yyyy: ")
    if notes.isEmpty || notes.count == 1 {
      history += notes.first ?? ""
    } else {
      for note in notes {
        history += "\n" + "* \(note)"
      }
    }

    return history
  }
}
