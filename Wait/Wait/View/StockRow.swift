// Created by kai_chen on 5/4/21.

import Charts
import Combine
import PartialSheet
import SwiftUI
import Model

// MARK: - StockRow

struct StockRow: View {
  // MARK: Internal

  @EnvironmentObject var sheetManager: PartialSheetManager
  @Binding var stockRowDetailType: StockRowDetailType

  @State var stock: Stock

  // TODO(kai) - fix this init symbol issue
  @ObservedObject var priceHistoryDataSource = PriceHistoryDataSource(symbol: "")

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
    .onAppear {
      priceHistoryDataSource.symbol = stock.symbol
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
        // todo(kai) - update the right action
        buttonText = "Wait"
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
