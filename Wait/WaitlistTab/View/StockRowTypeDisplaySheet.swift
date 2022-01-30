//
// Created by: kai_chen on 7/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Size
import SwiftUI

// MARK: - StockRowTypeDisplaySheet

struct StockRowTypeDisplaySheet: View {
  @Binding var stockRowDetailType: StockRowDetailType

  var body: some View {
    VStack(alignment: .leading, spacing: Size.verticalPadding16) {
      Text("Holdings Display Data")
        .font(.title2)
        .frame(maxWidth: .infinity, alignment: .center)

      Divider()

      ForEach(StockRowDetailType.allCases) { type in
        Button(action: {
          stockRowDetailType = type
        }, label: {
          HStack {
            Text(type.rawValue)
              .foregroundColor(.primary)
            Spacer()
            if stockRowDetailType == type {
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