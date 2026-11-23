//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - PriceLadderValidationTests

@Suite struct PriceLadderValidationTests {
  @Test func vectorsValidation() throws {
    let vectors = try LadderVectors.load()
    #expect(vectors.version == 1)
    for testCase in vectors.validation {
      do throws(LadderValidationError) {
        _ = try vectors.ladder(testCase.ladder)
        #expect(testCase.valid, "expected \(testCase.ladder) to be invalid")
      } catch {
        #expect(!testCase.valid, "unexpected error \(error)")
        switch error {
          case let .nonPositive(rung):
            #expect(testCase.error?.kind == "nonPositive")
            #expect(testCase.error?.rung == rung.rawValue)
          case let .outOfOrder(lower, upper):
            #expect(testCase.error?.kind == "outOfOrder")
            #expect(testCase.error?.lower == lower.rawValue)
            #expect(testCase.error?.upper == upper.rawValue)
        }
      }
    }
  }

  @Test func equalAdjacentAnchorsAreAllowed() throws {
    let ladder = try PriceLadder(buyLow: 50, buyHigh: 50)
    #expect(ladder.buyLow == 50)
    #expect(ladder.buyHigh == 50)
  }

  @Test func rejectsNegative() {
    #expect(throws: LadderValidationError.nonPositive(.sell)) {
      try PriceLadder(buyHigh: 10, sell: -1)
    }
  }

  @Test func emptyLadder() {
    #expect(PriceLadder.empty.isEmpty)
    #expect(PriceLadder.empty.value(for: .fair) == nil)
  }

  @Test func encodesDecimalStringsAndOmitsMissingRungs() throws {
    let ladder = try PriceLadder(buyHigh: dec("0.0075"), trim: dec("175.5"))
    let json = try String(decoding: JSONEncoder().encode(ladder), as: UTF8.self)
    #expect(json.contains(#""buyHigh":"0.0075""#))
    #expect(json.contains(#""trim":"175.5""#))
    #expect(!json.contains("buyLow"))
  }

  @Test func decodesStringsOrNumbersAndRoundTrips() throws {
    let fromNumber = try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyHigh":3.133}"#.utf8))
    let fromString = try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyHigh":"3.133"}"#.utf8))
    #expect(fromString.buyHigh == dec("3.133"))
    #expect(abs((fromNumber.buyHigh?.doubleValue ?? 0) - 3.133) < 1e-9)
    let roundTrip = try JSONDecoder().decode(PriceLadder.self, from: JSONEncoder().encode(fromString))
    #expect(roundTrip == fromString)
  }

  @Test func decodingAnInvertedLadderThrows() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyLow":"20","buyHigh":"10"}"#.utf8))
    }
  }
}
