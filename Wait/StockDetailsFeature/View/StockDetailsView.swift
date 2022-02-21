// Created by kai_chen on 5/16/21.

import CacheService
import Checklist
import ComposableArchitecture
import Model
import Size
import StockCharts
import SwiftUI

// MARK: - StockDetailsView

public struct StockDetailsView: View {
  // MARK: Lifecycle

  public init(stock: Stock) {
    _stock = State(initialValue: stock)
  }

  // MARK: Public

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        chartView

        Divider()
          .padding()

        statsView
          .padding()

        valuationView
          .padding()

        checklistView
          .padding()

        memoView
          .padding()

        versionView
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
    }
    .onChange(of: stockIsFavorited, perform: { value in
      stockFavoriteAction(value)
    })
  }

  // MARK: Internal

  @State var stock: Stock

  @ObservedObject var stockOverviewDatSource = StockOverviewDataSource(networkClient: DefaultStockOverviewNetworkClient())

  @State var stockIsFavorited: Bool = true
  @State var isEditingPrice = false

  @State var checklistItems = ChecklistItem.allItems

  var checkedItemCounts: Int {
    var counts = 0
    for item in checklistItems {
      counts += item.isChecked ? 1 : 0
    }

    return counts
  }

  var searchStock: SearchStockResult {
    SearchStockResult(
      symbol: stock.symbol,
      name: stock.name,
      exchange: "",
      country: "",
      currency: "US"
    )
  }

  // MARK: Private

  private var chartView: some View {
    SwiftUIChartViewController(symbol: stock.symbol)
      .frame(minHeight: 256.0)
  }

  private var statsView: some View {
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
  }

  private var valuationView: some View {
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
        .onChange(of: stock.expectedPrice, perform: { _ in
          StockCache.shared.saveStock(stock)
        })
      }

      Text("Stock Price: \(stock.expectedPrice.amountDoubleValue)")

      SwiftUIValuationChartViewController(stock: $stock)
        .frame(height: 120)
    }
  }



  private var checklistView: some View {
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
          ChecklistContentView(
            store: Store<ChecklistRootState, ChecklistRootAction>.init(
              initialState: ChecklistRootState(
                rootState: ChecklistState(checklistItems: checklistItems)
              ),
              reducer: ChecklistRootReducerBuilder.build(),
              environment: ChecklistRootEnvironment()
            ),
            checklistItems: $checklistItems
          )
        }
      }
    }
  }

  private var memoView: some View {
    VStack(alignment: .leading, spacing: 12.0) {
      HStack {
        Text("Memo")
          .font(.title)

        Spacer()

        Button("Save") {
          StockCache.shared.saveStock(stock)
        }
      }

      TextField("Write some notes...", text: $stock.memo, onCommit: {
        StockCache.shared.saveStock(stock)
      })
    }
  }

  private var versionView: some View {
    VStack(alignment: .leading, spacing: 12.0) {
      Text("Version")
        .font(.title)

      ForEach(stock.updatedHistory) { history in
        Text(history.formattedHistory)
      }
    }
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
