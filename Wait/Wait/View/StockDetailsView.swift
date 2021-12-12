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

  var checkedItemCounts: Int {
    var counts = 0
    for item in checklistItems {
      counts += item.isChecked ? 1 : 0
    }

    return counts
  }

  @State var checklistItems = ChecklistItem.allItems

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
            VStack {
              StockStatsView(title: "Mkt Cap", value: stockOverviewDatSource.stockOverview.marketCap.formattedCurrency(format: .short))
              Divider()
            }

            VStack {
              StockStatsView(title: "Avg Div", value: stockOverviewDatSource.stockOverview.dividendPerShare)
              Divider()
            }
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            VStack {
              StockStatsView(title: "PE", value: stockOverviewDatSource.stockOverview.PERatio)
              Divider()
            }

            VStack {
              StockStatsView(title: "PB", value: stockOverviewDatSource.stockOverview.PBRatio)
              Divider()
            }
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            VStack {
              StockStatsView(title: "PEG", value: stockOverviewDatSource.stockOverview.PEGRatio)
              Divider()
            }

            VStack {
              StockStatsView(title: "Profit Margin", value: stockOverviewDatSource.stockOverview.profitMargin)
              Divider()
            }
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            VStack {
              StockStatsView(title: "52 Wk High", value: stockOverviewDatSource.stockOverview.weekHigh52)
              Divider()
            }

            VStack {
              StockStatsView(title: "52 Wk Low", value: stockOverviewDatSource.stockOverview.weekLow52)
              Divider()
            }
          }
          .font(.subheadline)

          HStack(spacing: 12.0) {
            VStack {
              StockStatsView(title: "ROE", value: stockOverviewDatSource.stockOverview.returnOnEquity)
              Divider()
            }

            VStack {
              StockStatsView(title: "ROA", value: stockOverviewDatSource.stockOverview.returnOnAssets)
              Divider()
            }
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
            .onChange(of: stock, perform: { _ in
              StockCache.shared.saveStock(stock)
            })
          }

          SwiftUIValuationChartViewController(stock: stock)
            .frame(height: 120)
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Checklist")
            .font(.title)

          HStack {
            if checkedItemCounts < ChecklistItem.allItems.count {
              Text("\(checkedItemCounts) / \(ChecklistItem.allItems.count) Done")
                .font(.subheadline)
            } else {
              Text("All Done")
                .foregroundColor(.accentColor)
            }

            Spacer()

            NavigationLink("Let's check") {
              ChecklistContentView(checklistItems: $checklistItems)
            }
          }
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Memo")
            .font(.title)

          TextField("Write some notes...", text: $memo, onCommit: {
            stock = stock.with(memo: memo)
            StockCache.shared.saveStock(stock)
          })
        }
        .padding()

        VStack(alignment: .leading, spacing: 12.0) {
          Text("Version")
            .font(.title)

          ForEach(stock.updatedHistory) { history in
            Text(history.formattedHistory)
          }
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
