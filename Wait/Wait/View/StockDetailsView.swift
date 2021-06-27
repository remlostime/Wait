// Created by kai_chen on 5/16/21.

import Model
import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  var stock: Stock

  @ObservedObject var stockOverviewNetworkClient = StockOverviewNetworkClient()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        SwiftUIChartViewController()
          .frame(minHeight: 320.0)

        Divider()
          .padding()

        // TODO(kai) - fill the real data
        VStack(alignment: .leading, spacing: 12.0) {
          Text("Stats")
            .font(.title)

          HStack(spacing: 12.0) {
            StockStatsView(title: "Market Cap", value: stockOverviewNetworkClient.stockOverview.marketCap)
            StockStatsView(title: "Avg Div", value: stockOverviewNetworkClient.stockOverview.dividendPerShare)
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            StockStatsView(title: "PE", value: stockOverviewNetworkClient.stockOverview.PERatio)
            StockStatsView(title: "PB", value: stockOverviewNetworkClient.stockOverview.PBRatio)
          }
          .font(.subheadline)
        }
        .padding()

        Divider()
          .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Analysis")
            .font(.title)

          HStack(spacing: 12.0) {
            StockStatsView(title: "Action", value: action)
            StockStatsView(title: "Expected", value: stock.expectedPrice.formattedCurrency)
          }

          HStack(spacing: 12.0) {
            StockStatsView(title: "Current", value: stock.comparedToCurrentPriceRate)
            StockStatsView(title: "Expected", value: stock.expectedPrice.formattedCurrency)
          }
        }
        .padding()

        Spacer()
      }
      .multilineTextAlignment(.leading)
      .navigationTitle(stock.name)
    }
    .onAppear {
      stockOverviewNetworkClient.fetchStockOverview(stock: stock)
    }
  }

  var action: String {
    stock.currentPrice > stock.expectedPrice ? "Wait" : "Buy"
  }
}

// MARK: - StockDetailsView_Previews

struct StockDetailsView_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      symbol: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0,
      changePercent: "1.8%",
      priceChartImage: nil
    )

    StockDetailsView(stock: stock)
  }
}
