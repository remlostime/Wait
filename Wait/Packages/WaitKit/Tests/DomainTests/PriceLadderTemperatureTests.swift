//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - PriceLadderTemperatureTests

@Suite struct PriceLadderTemperatureTests {
  @Test func vectorsKnots() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.knots {
      let ladder = try vectors.ladder(testCase.ladder)
      let knots = ladder.knots()
      #expect(knots.count == testCase.knots.count, "\(testCase.ladder)")
      for (actual, expected) in zip(knots, testCase.knots) {
        #expect(abs(actual.price - expected[0]) < 0.001, "\(testCase.ladder) price \(actual.price) vs \(expected[0])")
        #expect(abs(actual.score - expected[1]) < 0.001)
      }
      if let derived = testCase.derivedFair {
        let value = try #require(ladder.derivedFair)
        #expect(abs(value.doubleValue - derived) < 0.001)
      } else {
        #expect(ladder.derivedFair == nil)
      }
    }
  }

  @Test func vectorsTemperatures() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.evaluations {
      let ladder = try vectors.ladder(testCase.ladder)
      let temperature = ladder.temperature(at: dec(testCase.price))
      if let expected = testCase.temperature {
        let actual = try #require(temperature, "\(testCase.ladder) @ \(testCase.price)")
        #expect(abs(actual.value - expected) <= 0.05, "\(testCase.ladder) @ \(testCase.price): \(actual.value) vs \(expected)")
        #expect(actual.band.rawValue == testCase.band)
      } else {
        #expect(temperature == nil)
        #expect(testCase.band == nil)
      }
    }
  }

  @Test func derivedFairUsesTenSevenths() throws {
    let ladder = try PriceLadder(buyHigh: 175)
    #expect(ladder.derivedFair == Decimal(250))
    #expect(ladder.effectiveFair == Decimal(250))
    #expect(ladder.rungs.map(\.rung) == [.buyHigh, .fair])
    #expect(ladder.rungs.last?.isDerived == true)
  }

  @Test func noDerivedFairWhenAnUpperAnchorExists() throws {
    let ladder = try PriceLadder(buyHigh: 100, trim: 150)
    #expect(ladder.derivedFair == nil)
    #expect(ladder.effectiveFair == nil)
  }

  @Test func bandBoundaries() {
    #expect(Temperature(value: 19.99).band == .freezing)
    #expect(Temperature(value: 20).band == .cold)
    #expect(Temperature(value: 40).band == .neutral)
    #expect(Temperature(value: 60).band == .warm)
    #expect(Temperature(value: 80).band == .hot)
  }
}
