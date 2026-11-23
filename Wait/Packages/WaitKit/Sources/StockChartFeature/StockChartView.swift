//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import ComposableArchitecture
import DesignSystem
import Domain
import MarketDataClient
import SwiftUI

// MARK: - StockChartView

/// Contents:
/// - An ordinal x-axis labeled with dates.
/// - An area gradient under the line.
/// - Dashed ladder rungs. Derived rungs use a dot pattern.
/// - `chartXSelection` scrubbing.
/// - A segmented range picker.
public struct StockChartView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<StockChartFeature>, ladder: PriceLadder) {
    self.store = store
    self.ladder = ladder
  }

  // MARK: Public

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      header
      chart
        .frame(height: 220)
      Picker("Range", selection: Binding(get: { store.range }, set: { store.send(.rangeSelected($0)) })) {
        ForEach(ChartRange.allCases, id: \.self) { range in
          Text(range.title).tag(range)
        }
      }
      .pickerStyle(.segmented)
    }
    .task { await store.send(.task).finish() }
  }

  // MARK: Private

  private let store: StoreOf<StockChartFeature>
  private let ladder: PriceLadder

  @ViewBuilder private var header: some View {
    let points = store.points
    if let shown = store.selectedPoint ?? points.last {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(shown.close, format: .currency(code: "USD"))
          .font(.title2.monospacedDigit().weight(.semibold))
          .contentTransition(.numericText())
        HStack(spacing: Spacing.s) {
          if let change = ChartGeometry.changePercent(points) {
            Text(change / 100, format: .percent.precision(.fractionLength(2)))
              .foregroundStyle(Palette.change(change))
          }
          Text(store.selectedPoint.map { label(for: $0.date) } ?? store.range.title)
            .foregroundStyle(.secondary)
          if let delay = store.series[store.range]?.delayedMinutes {
            Text("Delayed \(delay) min").foregroundStyle(.secondary)
          }
          if store.series[store.range]?.isStale == true {
            Label("Cached", systemImage: "clock.arrow.circlepath").foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }
    } else {
      Text(store.symbol).font(.title2.weight(.semibold)).redacted(reason: .placeholder)
    }
  }

  @ViewBuilder private var chart: some View {
    let points = store.points
    let rungs = ladder.rungs
    if let domain = ChartGeometry.yDomain(points: points, rungs: rungs.map(\.price)) {
      let color = ChartGeometry.trend(points) == .up ? Palette.stockUp : Palette.stockDown
      Chart {
        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
          AreaMark(
            x: .value("Index", index),
            yStart: .value("Base", domain.lowerBound),
            yEnd: .value("Close", point.close.doubleValue)
          )
          .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
          .interpolationMethod(.monotone)

          LineMark(x: .value("Index", index), y: .value("Close", point.close.doubleValue))
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
        }

        ForEach(rungs.filter { domain.contains($0.price.doubleValue) }, id: \.rung) { rung in
          RuleMark(y: .value(rung.rung.title, rung.price.doubleValue))
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: rung.isDerived ? [2, 4] : [4, 4]))
            .annotation(position: .top, alignment: .leading) {
              Text(rung.isDerived ? "\(rung.rung.title) (derived)" : rung.rung.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }

        if let index = store.selectedIndex, let point = store.selectedPoint {
          RuleMark(x: .value("Selected", index))
            .foregroundStyle(.secondary.opacity(0.5))
          PointMark(x: .value("Selected", index), y: .value("Close", point.close.doubleValue))
            .foregroundStyle(color)
        }
      }
      .chartYScale(domain: domain)
      .chartXScale(domain: 0 ... max(points.count - 1, 1))
      .chartXAxis {
        AxisMarks(values: ChartGeometry.axisLabelIndices(count: points.count)) { value in
          AxisGridLine()
          AxisValueLabel {
            if let index = value.as(Int.self), points.indices.contains(index) {
              Text(label(for: points[index].date))
            }
          }
        }
      }
      .chartYAxis { AxisMarks(position: .trailing) }
      .chartXSelection(value: Binding(get: { store.selectedIndex }, set: { store.send(.selectionChanged($0)) }))
      .accessibilityLabel("\(store.symbol) price chart, \(store.range.title)")
    } else if store.loading.contains(store.range) {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ContentUnavailableView {
        Label("No chart data", systemImage: "chart.xyaxis.line")
      } description: {
        Text(store.failed[store.range]?.userMessage ?? "Nothing to show yet.")
      } actions: {
        Button("Retry") { store.send(.retryTapped) }
      }
    }
  }

  private func label(for date: Date) -> String {
    switch store.range {
      case .oneDay: date.formatted(.dateTime.hour().minute())
      case .oneWeek: date.formatted(.dateTime.weekday(.abbreviated).day())
      case .oneMonth: date.formatted(.dateTime.month(.abbreviated).day())
      case .oneYear: date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
      case .fiveYears: date.formatted(.dateTime.year())
    }
  }
}

#Preview {
  StockChartView(
    store: Store(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData = .previewValue
    },
    ladder: (try? PriceLadder(buyHigh: 106, fair: 118)) ?? .empty
  )
  .padding()
}
