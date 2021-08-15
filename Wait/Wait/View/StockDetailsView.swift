// Created by kai_chen on 5/16/21.

import Model
import Size
import SwiftDate
import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  // MARK: Internal

  @State var stock: Stock

  @ObservedObject var stockOverviewDatSource = StockOverviewDataSource()

  @State var stockIsFavorited: Bool = true
  @State var memo: String = ""
  @State var isEditingPrice = false

  var searchStock: SearchStockResult {
    SearchStockResult(
      symbol: stock.symbol,
      name: stock.name,
      exchange: "",
      country: "",
      currency: "US"
    )
  }

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
            StockStatsView(title: "Market Cap", value: stockOverviewDatSource.stockOverview.marketCap.formattedCurrency(format: .short))
            StockStatsView(title: "Avg Div", value: stockOverviewDatSource.stockOverview.dividendPerShare)
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            StockStatsView(title: "PE", value: stockOverviewDatSource.stockOverview.PERatio)
            StockStatsView(title: "PB", value: stockOverviewDatSource.stockOverview.PBRatio)
          }
          .font(.subheadline)
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          HStack {
            Text("Valuation")
              .font(.title)

            Spacer()

            Button("edit") {
              isEditingPrice.toggle()
            }
            .sheet(isPresented: $isEditingPrice, content: {
              StockExpectedPriceInputView(
                searchStock: searchStock,
                stock: $stock,
                isPresented: $isEditingPrice
              )
            })
          }

          SwiftUIValuationChartViewController(stock: stock)
            .frame(height: 120)
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Checklist")
            .font(.title)

          ForEach(ChecklistItem.allItems) { item in
            Checklist(item: item)
          }
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

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Version")
            .font(.title)

          Text("Last edited: " + stock.lastUpdatedTime.toFormat("MMM dd, yyyy"))
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
      stockOverviewDatSource.fetchStockOverview(stock: stock)
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
    let stock = Stock.empty
    StockDetailsView(stock: stock)
  }
}
