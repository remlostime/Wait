//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient

// MARK: - StockChartFeature

/// Loads one range at a time: 1Y on appear, other ranges only when selected. The legacy screen fetched all five ranges on every visit.
@Reducer
public struct StockChartFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(symbol: String, range: ChartRange = .oneYear) {
      self.symbol = symbol
      self.range = range
    }

    // MARK: Public

    public let symbol: String
    public var range: ChartRange
    public var series: [ChartRange: PriceSeries] = [:]
    public var loading: Set<ChartRange> = []
    public var failed: [ChartRange: MarketDataError] = [:]
    public var selectedIndex: Int?

    public var points: [PricePoint] {
      series[range]?.points ?? []
    }

    public var selectedPoint: PricePoint? {
      guard let selectedIndex, points.indices.contains(selectedIndex) else {
        return nil
      }
      return points[selectedIndex]
    }
  }

  public enum Action {
    case task
    case rangeSelected(ChartRange)
    case retryTapped
    /// The raw x value from `chartXSelection`; the reducer rounds it to the nearest point.
    case selectionChanged(Double?)
    /// Cache-first result. It fills the chart but keeps `loading`, because the fresh request is still running.
    case cachedSeriesLoaded(ChartRange, PriceSeries)
    case seriesLoaded(ChartRange, PriceSeries)
    case seriesFailed(ChartRange, MarketDataError)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .task:
          return load(&state, range: state.range, policy: .useCache)

        case let .rangeSelected(range):
          state.range = range
          state.selectedIndex = nil
          guard state.series[range] == nil else {
            return .none
          }
          return load(&state, range: range, policy: .useCache)

        case .retryTapped:
          return load(&state, range: state.range, policy: .reload)

        case let .selectionChanged(raw):
          state.selectedIndex = ChartGeometry.nearestIndex(raw, count: state.points.count)
          return .none

        case let .cachedSeriesLoaded(range, series):
          state.series[range] = series
          return .none

        case let .seriesLoaded(range, series):
          state.loading.remove(range)
          state.failed[range] = nil
          state.series[range] = series
          return .none

        case let .seriesFailed(range, error):
          state.loading.remove(range)
          state.failed[range] = error
          return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID: Hashable {
    case load(ChartRange)
  }

  @Dependency(\.marketData) private var marketData

  /// For `.useCache`, cached data goes out first (`.cachedSeriesLoaded`), then the possibly network-backed result.
  private func load(_ state: inout State, range: ChartRange, policy: CachePolicy) -> Effect<Action> {
    // No in-flight guard: a cancelled load (view disappeared) would leave `range` in `loading` and block every later load.
    // `cancelInFlight` already supersedes a still-running request.
    state.loading.insert(range)
    state.failed[range] = nil
    let symbol = state.symbol
    return .run { [marketData] send in
      if policy == .useCache, let cached = try? await marketData.series(symbol, range, .cacheOnly) {
        await send(.cachedSeriesLoaded(range, cached))
      }
      do {
        try await send(.seriesLoaded(range, marketData.series(symbol, range, policy)))
      } catch {
        try await send(.seriesFailed(range, MarketDataError(error))) // rethrows cancellation
      }
    }
    .cancellable(id: CancelID.load(range), cancelInFlight: true)
  }
}
