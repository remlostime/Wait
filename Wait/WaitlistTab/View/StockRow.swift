// Created by kai_chen on 5/4/21.

import CacheService
import Charts
import Combine
import Model
import Size
import StockCharts
import SwiftUI

// MARK: - StockRowDetailType

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
    priceHistoryDataSource = PriceHistoryDataSource(symbol: stock.symbol)
  }

  // MARK: Internal

  @Binding var stockRowDetailType: StockRowDetailType
  @State var showDisplaySheet: Bool = false

  @State var stock: Stock

  @ObservedObject var priceHistoryDataSource: PriceHistoryDataSource

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

      Spacer(minLength: Size.horizontalPadding24)

      if let image = StockChartImageCache.shared.getImage(symbol: stock.symbol)?.image {
        Image(uiImage: image)
          .resizable()
          .frame(width: 80.0, height: 32.0)
          .scaledToFit()
      } else if let chartData = priceHistoryDataSource.chartData[.day],
                let image = chartData.buildChartImage()
      {
        Image(uiImage: image)
          .resizable()
          .frame(width: 80.0, height: 32.0)
          .scaledToFit()
      }

      Spacer(minLength: Size.horizontalPadding24)

      Button(buttonText) {
        showDisplaySheet = true
      }
      .sheet(isPresented: $showDisplaySheet, onDismiss: {
        showDisplaySheet = false
      }, content: {
        StockRowTypeDisplaySheet(stockRowDetailType: $stockRowDetailType)
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
