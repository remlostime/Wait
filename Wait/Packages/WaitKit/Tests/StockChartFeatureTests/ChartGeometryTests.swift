//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import StockChartFeature
import Testing

func points(_ closes: [String]) -> [PricePoint] {
  closes.enumerated().map { PricePoint(date: Date(timeIntervalSince1970: Double($0.offset) * 86400), close: Decimal(string: $0.element)!) }
}

@Suite struct ChartGeometryTests {
  @Test func emptyPointsHaveNoDomain() {
    // The legacy chart trapped here (Int.max) when it had no data.
    #expect(ChartGeometry.yDomain(points: [], rungs: [10]) == nil)
  }

  @Test func subDollarDomainIsTight() throws {
    let domain = try #require(ChartGeometry.yDomain(points: points(["0.5"]), rungs: []))
    #expect(abs(domain.lowerBound - 0.499) < 1e-9)
    #expect(abs(domain.upperBound - 0.501) < 1e-9)
  }

  @Test func nearbyRungsExtendTheDomainAndFarOnesDont() throws {
    let near = try #require(ChartGeometry.yDomain(points: points(["10", "12"]), rungs: [13]))
    #expect(abs(near.lowerBound - 9.7) < 1e-9)
    #expect(abs(near.upperBound - 13.3) < 1e-9)
    let far = try #require(ChartGeometry.yDomain(points: points(["10", "12"]), rungs: [30]))
    #expect(abs(far.lowerBound - 9.8) < 1e-9)
    #expect(abs(far.upperBound - 12.2) < 1e-9)
  }

  @Test func lowerBoundNeverGoesNegative() throws {
    let domain = try #require(ChartGeometry.yDomain(points: points(["1", "100"]), rungs: []))
    #expect(domain.lowerBound == 0)
  }

  @Test func nearestIndexClamps() {
    #expect(ChartGeometry.nearestIndex(7, count: 2) == 1)
    #expect(ChartGeometry.nearestIndex(-3, count: 2) == 0)
    #expect(ChartGeometry.nearestIndex(nil, count: 2) == nil)
    #expect(ChartGeometry.nearestIndex(0, count: 0) == nil)
  }

  @Test func nearestIndexRoundsToTheClosestPoint() {
    #expect(ChartGeometry.nearestIndex(2.4, count: 5) == 2)
    #expect(ChartGeometry.nearestIndex(2.6, count: 5) == 3)
    #expect(ChartGeometry.nearestIndex(-1, count: 5) == 0)
    #expect(ChartGeometry.nearestIndex(9.7, count: 5) == 4)
    #expect(ChartGeometry.nearestIndex(.nan, count: 5) == nil)
  }

  @Test func trendAndChange() {
    #expect(ChartGeometry.trend(points(["10", "12"])) == .up)
    #expect(ChartGeometry.trend(points(["12", "10"])) == .down)
    #expect(ChartGeometry.changePercent(points(["10", "12"])) == 20)
    #expect(ChartGeometry.changePercent([]) == nil)
  }

  @Test func axisLabelIndices() {
    #expect(ChartGeometry.axisLabelIndices(count: 10) == [0, 3, 6, 9])
    #expect(ChartGeometry.axisLabelIndices(count: 3) == [0, 1, 2])
    #expect(ChartGeometry.axisLabelIndices(count: 0) == [])
  }
}
