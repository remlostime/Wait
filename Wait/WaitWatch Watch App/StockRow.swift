//
// Created by: Kai Chen on 7/10/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import SwiftUI

// MARK: - StockRow

struct StockRow: View {
  // MARK: Lifecycle

  init(stockRowDetailType: Binding<StockRowDetailType>) {
    _stockRowDetailType = stockRowDetailType
  }

  // MARK: Internal

  @Binding var stockRowDetailType: StockRowDetailType
  @State var showDisplaySheet: Bool = false

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("Symbol")
          .font(.title3)
        Text("name")
          .font(.subheadline)
          .lineLimit(1)
          .foregroundColor(.secondary)
      }
      .frame(alignment: .leading)

      Spacer()

      Text(buttonText)
    }
    .padding(.vertical, Size.baseLayoutUnit8)
    .onAppear {
//      priceHistoryDataSource.fetchData(for: [.day])
    }
  }

  // MARK: Private

  private var buttonText: String {
    let buttonText: String
    switch stockRowDetailType {
      case .price:
        buttonText = "Price"
      case .priceChange:
        buttonText = "Price Change"
      case .actionStatus:
        buttonText = "Action"
    }

    return buttonText
  }
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    StockRow(stockRowDetailType: .constant(.price))
  }
}
