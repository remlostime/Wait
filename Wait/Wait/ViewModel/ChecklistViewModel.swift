//
// Created by: kai_chen on 12/7/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Model
import SwiftUI

class ChecklistViewModel: ObservableObject {
  @Published var backgroundColor = Color("Gray")
  @Published var isChecked: Bool = false

  func updateBackgroundColorForTranslation(_ translation: Double) {
    switch translation {
      case ...(-0.5):
        backgroundColor = Color("Red")
      case 0.5...:
        backgroundColor = Color("Green")
      default:
        backgroundColor = Color("Gray")
    }
  }

  func updateDecisionStateForTranslation(
    _ translation: Double,
    andPredictedEndLocationX x: CGFloat,
    inBounds bounds: CGRect
  ) {
    switch (translation, x) {
      case (...(-0.6), ..<0):
        isChecked = false
      case (0.6..., bounds.width...):
        isChecked = true
      default:
        isChecked = false
    }
  }

  func reset() {
    backgroundColor = Color("Gray")
  }
}
