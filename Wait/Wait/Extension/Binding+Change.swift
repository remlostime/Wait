//
// Created by: kai_chen on 6/25/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftUI

extension Binding {
  func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
    Binding(
      get: { self.wrappedValue },
      set: { newValue in
        self.wrappedValue = newValue
        handler(newValue)
      }
    )
  }
}
