// Created by kai_chen on 5/16/21.

import Model
import Size
import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  // MARK: Internal

  var stock: Stock

  @ObservedObject var stockOverviewNetworkClient = StockOverviewNetworkClient()

  @State var stockIsFavorited: Bool = true
  @State var memo: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        SwiftUIChartViewController(symbol: stock.symbol)
          .frame(minHeight: 256.0)

        Divider()
          .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Stats")
            .font(.title)

          HStack(spacing: 12.0) {
            StockStatsView(title: "Market Cap", value: stockOverviewNetworkClient.stockOverview.marketCap.formattedCurrency(format: .short))
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
          Text("Valuation")
            .font(.title)

          SwiftUIValuationChartViewController(stock: stock)
            .frame(height: 120)
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Memo")
            .font(.title)

          TextField("Write some notes...", text: $memo, onCommit: {
            StockCache.shared.removeStock(stock)
            let newStock = stock.with(memo: memo)
            StockCache.shared.saveStock(newStock)
          })
        }
        .padding()
      }
      .multilineTextAlignment(.leading)
      .navigationTitle(stock.name)
      .navigationBarItems(trailing:
        Button(action: { stockIsFavorited.toggle() }, label: {
          if stockIsFavorited {
            Image(systemName: "star.fill")
              .foregroundColor(.banana)
          } else {
            Image(systemName: "star")
          }
        })
      )
    }
    .onAppear {
      stockOverviewNetworkClient.fetchStockOverview(stock: stock)
      memo = stock.memo
    }
    .onChange(of: stockIsFavorited, perform: { value in
      stockFavoriteAction(value)
    })
  }

  // MARK: Private

  private var companyDomain: String {
    let names = stock.name.split(separator: " ")
    guard let firstName = names.first else {
      return ""
    }
    return String(firstName) + ".com"
  }

  private func stockFavoriteAction(_ isFavorited: Bool) {
    if isFavorited {
      StockCache.shared.saveStock(stock)
    } else {
      StockCache.shared.removeStock(stock)
    }
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
