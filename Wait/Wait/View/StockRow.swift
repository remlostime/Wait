// Created by kai_chen on 5/4/21.

import Charts
import Combine
import Kingfisher
import Model
import PartialSheet
import Size
import SwiftUI

// MARK: - StockRowDetailType

enum StockRowDetailType {
  case price
  case priceChange
  case actionStatus
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

  @EnvironmentObject var sheetManager: PartialSheetManager
  @Binding var stockRowDetailType: StockRowDetailType

  @State var stock: Stock

  @ObservedObject var priceHistoryDataSource: PriceHistoryDataSource

  var body: some View {
    HStack {
      KFImage(URL(string: "https://assets.brandfetch.io/297077ad416c47d.png"))
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)

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

//      if let priceChartImage = stock.priceChartImage {
//        if let image = priceChartImage.image {
      //          Image(uiImage: image)
      //        }
      //      }

      if let chartData = priceHistoryDataSource.chartData[.day] {
        if let image = buildPriceChartImage(chartData: chartData) {
          Image(uiImage: image)
        }
      }

      Spacer(minLength: Size.horizontalPadding24)

      Button(buttonText) {
        self.sheetManager.showPartialSheet {
          VStack(alignment: .leading, spacing: Size.verticalPadding16) {
            Text("Holdings Display Data")

            Divider()

            Text("Price")
              .onTapGesture {
                stockRowDetailType = .price
                self.sheetManager.closePartialSheet()
              }

            Text("Price Change")
              .onTapGesture {
                stockRowDetailType = .priceChange
                self.sheetManager.closePartialSheet()
              }

            Text("Action Status")
              .onTapGesture {
                stockRowDetailType = .actionStatus
                self.sheetManager.closePartialSheet()
              }
          }
          .padding()
        }
      }
      .foregroundColor(isNegativeNumber(stock.changePercent) ? .stockRed : .stockGreen)
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
        buttonText = stock.changePercent
      case .actionStatus:
        buttonText = stock.tradeAction.rawValue
    }

    return buttonText
  }

  private func buildPriceChartImage(chartData: ChartData?) -> UIImage? {
    guard let chartData = chartData else {
      return nil
    }

    let chart = LineChartView(frame: CGRect(x: 0, y: 0, width: 80.0, height: 32.0))
    chart.setScaleEnabled(false)
    chart.xAxis.avoidFirstLastClippingEnabled = true
    chart.minOffset = 0
    chart.highlightPerTapEnabled = false
    chart.pinchZoomEnabled = false
    chart.legend.enabled = false
    chart.xAxis.enabled = false
    chart.leftAxis.enabled = false
    chart.rightAxis.enabled = false
    chart.isOpaque = false

    chart.data = chartData
    let image = chart.getChartImage(transparent: true)

    return image
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
      changePercent: "1.8%",
      priceChartImage: nil
    )

    StockRow(stockRowDetailType: .constant(.price), stock: stock)
  }
}
