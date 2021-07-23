// Created by kai_chen on 5/4/21.

import Charts
import Combine
import Model
import PartialSheet
import Size
import SkeletonUI
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

  @EnvironmentObject var sheetManager: PartialSheetManager
  @Binding var stockRowDetailType: StockRowDetailType

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
                let image = buildPriceChartImage(chartData: chartData)
      {
        Image(uiImage: image)
          .resizable()
          .frame(width: 80.0, height: 32.0)
          .scaledToFit()
      } else {
        Image(uiImage: nil)
          .frame(width: 80.0, height: 32.0)
          .skeleton(with: true)
      }

      Spacer(minLength: Size.horizontalPadding24)

      Button(buttonText) {
        self.sheetManager.showPartialSheet {
          StockRowTypeDisplaySheet(stockRowDetailType: $stockRowDetailType)
        }
      }
      .padding(EdgeInsets(top: Size.verticalPadding8, leading: Size.horizontalPadding16, bottom: Size.verticalPadding8, trailing: Size.horizontalPadding16))
      .background(stockRowDetailType == .actionStatus ? stock.actionColor : stock.priceColor)
      .cornerRadius(5.0)
      .buttonStyle(PlainButtonStyle())
    }
    .padding(.vertical, Size.baseLayoutUnit8)
    .onAppear {
      priceHistoryDataSource.fetchData(for: [.day])
    }
    .onDisappear {
//      if let chartData = priceHistoryDataSource.chartData[.day],
//         let image = buildPriceChartImage(chartData: chartData)
//      {
//        let stockImage = PriceChartImage(image: image)
//        StockChartImageCache.shared.saveImage(symbol: stock.symbol, image: stockImage)
//        StockCache.shared.removeStock(stock)
//        let newStock = stock.with(priceChartImage: stockImage)
//        StockCache.shared.saveStock(newStock)
//      }
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
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock.empty
    StockRow(stockRowDetailType: .constant(.price), stock: stock)
  }
}
