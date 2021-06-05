// Created by kai_chen on 5/4/21.

import PartialSheet
import SwiftUI

// MARK: - StockRow

struct StockRow: View {
  // MARK: Internal

  @EnvironmentObject var sheetManager: PartialSheetManager
  @Binding var stockRowDetailType: StockRowDetailType

  let stock: Stock

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

      Spacer()

      Image(systemName: "plus")

      Spacer()

      Button(buttonText) {
        self.sheetManager.showPartialSheet {} content: {
          List {
            Button("Price") {
              stockRowDetailType = .price
              self.sheetManager.closePartialSheet()
            }

            Button("Price Change") {
              stockRowDetailType = .priceChange
              self.sheetManager.closePartialSheet()
            }

            Button("Action Status") {
              stockRowDetailType = .actionStatus
              self.sheetManager.closePartialSheet()
            }
          }
        }
      }
      .foregroundColor(isNegativeNumber(stock.changePercent) ? .stockRed : .stockGreen)
      .buttonStyle(PlainButtonStyle())
    }
    .padding()
  }

  // MARK: Private

  private var buttonText: String {
    let buttonText: String
    switch stockRowDetailType {
      case .price:
        buttonText = stock.currentPrice.formattedCurrency
      case .priceChange:
        buttonText = stock.changePercent
      case .actionStatus:
        // todo(kai) - update the right action
        buttonText = "Wait"
    }

    return buttonText
  }

  private func isNegativeNumber(_ number: String) -> Bool {
    guard !number.isEmpty else {
      return false
    }

    return number.first == "-"
  }
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      symbol: "fb",
      name: "Facebook Inc - Class A Share",
      currentPrice: 100.0,
      expectedPrice: 200.0,
      changePercent: "1.8%"
    )

    StockRow(stockRowDetailType: .constant(.price), stock: stock)
  }
}
