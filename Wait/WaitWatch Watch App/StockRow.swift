//
// Created by: Kai Chen on 7/10/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import SwiftUI

// MARK: - StockRow

struct StockRow: View {
  // MARK: Lifecycle

  init(stockRowDetailType: Binding<StockRowDetailType>, stock: Stock) {
    _stockRowDetailType = stockRowDetailType
    self.stock = stock
  }

  // MARK: Internal

  @Binding var stockRowDetailType: StockRowDetailType
  @State var showDisplaySheet: Bool = false

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(stock.symbol)
          .font(.title3)
        Text(stock.name)
          .font(.subheadline)
          .lineLimit(1)
          .foregroundColor(.secondary)
      }
      .frame(alignment: .leading)

      Spacer()

      Text(buttonText)
        .foregroundColor(stockRowDetailType == .actionStatus ? Color.green : Color.red)
    }
    .padding(.vertical, Size.baseLayoutUnit8)
  }
  
  private let stock: Stock

  // MARK: Private

  private var buttonText: String {
    let buttonText: String
    switch stockRowDetailType {
      case .price:
        buttonText = "\(stock.currentPrice.amountDoubleValue)"
      case .priceChange:
        buttonText = stock.changePercent
      case .actionStatus:
        buttonText = stock.tradeAction.rawValue
    }

    return buttonText
  }
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    StockRow(stockRowDetailType: .constant(.price), stock: .init(symbol: "faf", name: "adf", expectedPrice: .init(100), currentQuote: .init(symbol: "adfs", name: "df", open: .init(10), high: .init(10), low: .init(10), close: .init(10), volume: "ff", datetime: .now, percentChange: "dsf"), expectedPriceHistory: []))
  }
}
