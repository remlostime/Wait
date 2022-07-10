// Created by kai_chen on 5/4/21.

import Combine
import SwiftUI

// MARK: - StockRowDetailType
/*

enum StockRowDetailType: String, CaseIterable {
  case price = "Price"
  case priceChange = "Price Change"
  case actionStatus = "Action Status"
}

// MARK: Identifiable

extension StockRowDetailType: Identifiable {
  var id: Self {
    self
  }
}

// MARK: - StockRow

struct StockRow: View {
  // MARK: Lifecycle

  init(stockRowDetailType: Binding<StockRowDetailType>, stock: Stock) {
    _stock = State<Stock>(initialValue: stock)
    _stockRowDetailType = stockRowDetailType
    _priceHistoryDataSource = StateObject(wrappedValue: PriceHistoryDataSource(symbol: stock.symbol))
  }

  // MARK: Internal

  @Binding var stockRowDetailType: StockRowDetailType
  @State var showDisplaySheet: Bool = false

  @State var stock: Stock

  @StateObject var priceHistoryDataSource: PriceHistoryDataSource

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

      Button(buttonText) {
        showDisplaySheet = true
      }
      .confirmationDialog("Display Data", isPresented: $showDisplaySheet, titleVisibility: .visible, actions: {
        ForEach(StockRowDetailType.allCases) { type in
          Button(type.rawValue) {
            stockRowDetailType = type
          }
        }

        Button("Cancel", role: .cancel) {
          showDisplaySheet = false
        }
      })
      .padding(EdgeInsets(top: Size.verticalPadding8, leading: Size.horizontalPadding16, bottom: Size.verticalPadding8, trailing: Size.horizontalPadding16))
      .background(stockRowDetailType == .actionStatus ? stock.actionColor : stock.priceColor)
      .cornerRadius(5.0)
      .buttonStyle(PlainButtonStyle())
    }
    .padding(.vertical, Size.baseLayoutUnit8)
    .onAppear {
      priceHistoryDataSource.fetchData(for: [.day])
    }
  }

  // MARK: Private

  private var buttonText: String {
    let buttonText: String
    switch stockRowDetailType {
      case .price:
        buttonText = stock.currentPrice.formattedCurrency
      case .priceChange:
        buttonText = stock.formattedChangePercent
      case .actionStatus:
        buttonText = stock.tradeAction.rawValue
    }

    return buttonText
  }
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock.empty
    StockRow(stockRowDetailType: .constant(.price), stock: stock)
  }
}
*/
