//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - ChartTrend

public enum ChartTrend: Equatable, Sendable {
  case up
  case down
}

// MARK: - ChartGeometry

/// Pure chart math, kept separate from the view so it can be tested. The x-axis is ordinal: the point index, labeled with dates (overview D11).
public enum ChartGeometry {
  /// Nil for no points. Rungs within the closes −15%…+15% widen the domain. Padding is 10% of max(span, 2% of high, 0.0001). The lower bound is ≥ 0.
  public static func yDomain(points: [PricePoint], rungs: [Decimal]) -> ClosedRange<Double>? {
    let closes = points.map(\.close.doubleValue)
    guard let minClose = closes.min(), let maxClose = closes.max() else {
      return nil
    }
    let window = (minClose * 0.85) ... (maxClose * 1.15)
    var low = minClose
    var high = maxClose
    for rung in rungs.map(\.doubleValue) where window.contains(rung) {
      low = min(low, rung)
      high = max(high, rung)
    }
    let pad = max(high - low, high * 0.02, 0.0001) * 0.1
    return max(0, low - pad) ... (high + pad)
  }

  public static func nearestIndex(_ raw: Int?, count: Int) -> Int? {
    guard let raw, count > 0 else {
      return nil
    }
    return min(max(raw, 0), count - 1)
  }

  public static func trend(_ points: [PricePoint]) -> ChartTrend {
    guard let first = points.first, let last = points.last else {
      return .up
    }
    return last.close >= first.close ? .up : .down
  }

  /// Percent change from the first point to the last.
  public static func changePercent(_ points: [PricePoint]) -> Double? {
    guard let first = points.first, let last = points.last, first.close > 0 else {
      return nil
    }
    return ((last.close - first.close) / first.close * 100).doubleValue
  }

  public static func axisLabelIndices(count: Int, desired: Int = 4) -> [Int] {
    guard count > 0 else {
      return []
    }
    guard count > desired else {
      return Array(0 ..< count)
    }
    let step = Double(count - 1) / Double(desired - 1)
    return (0 ..< desired).map { Int((Double($0) * step).rounded()) }
  }
}
