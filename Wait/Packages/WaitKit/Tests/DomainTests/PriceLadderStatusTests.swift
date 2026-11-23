//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceLadderStatusTests {
  @Test func vectorsStatuses() throws {
    let vectors = try LadderVectors.load()
    for testCase in vectors.evaluations {
      let ladder = try vectors.ladder(testCase.ladder)
      #expect(ladder.status(at: dec(testCase.price)).rawValue == testCase.status, "\(testCase.ladder) @ \(testCase.price)")
    }
  }

  @Test func ranks() {
    #expect(LadderStatus.deepBuy.rank == 0)
    #expect(LadderStatus.buyZone.rank == 1)
    #expect(LadderStatus.watch.rank == 2)
    #expect(LadderStatus.atOrAboveFair.rank == 3)
    #expect(LadderStatus.trim.rank == 4)
    #expect(LadderStatus.sell.rank == 5)
    #expect(LadderStatus.noAnchors.rank == nil)
  }

  @Test func titles() {
    #expect(LadderStatus.atOrAboveFair.title == "At/Above Fair")
    #expect(LadderStatus.buyZone.title == "Buy Zone")
  }

  @Test func distanceToBuy() throws {
    let ladder = try PriceLadder(buyHigh: 90)
    #expect(ladder.distanceToBuy(from: 100) == -10)
    #expect(ladder.distanceToBuy(from: 90) == 0)
    #expect(try PriceLadder(fair: 10).distanceToBuy(from: 5) == nil)
  }
}
