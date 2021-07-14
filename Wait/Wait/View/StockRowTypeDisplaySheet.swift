//
// Created by: kai_chen on 7/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import PartialSheet
import Size
import SwiftUI

// MARK: - StockRowTypeDisplaySheet

struct StockRowTypeDisplaySheet: View {
  @EnvironmentObject var sheetManager: PartialSheetManager
  @Binding var stockRowDetailType: StockRowDetailType

  var body: some View {
    VStack(alignment: .leading, spacing: Size.verticalPadding16) {
      Text("Holdings Display Data")
        .font(.headline)

      Divider()

      ForEach(StockRowDetailType.allCases) { type in
        Button(action: {
          stockRowDetailType = type
          self.sheetManager.closePartialSheet()
        }, label: {
          HStack {
            Text(type.rawValue)
              .foregroundColor(.primary)
            if stockRowDetailType == type {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        })
      }
    }
    .padding()
  }
}

// MARK: - StockRowTypeDisplaySheet_Previews

struct StockRowTypeDisplaySheet_Previews: PreviewProvider {
  static var previews: some View {
    StockRowTypeDisplaySheet(stockRowDetailType: .constant(.price))
  }
}
