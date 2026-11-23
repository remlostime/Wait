//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI
import Testing

@Suite struct DesignSystemTests {
  @Test func everyStatusHasASymbol() {
    for status in LadderStatus.allCases {
      #expect(!status.symbolName.isEmpty)
    }
    #expect(Set(LadderStatus.allCases.map(\.symbolName)).count == LadderStatus.allCases.count)
  }

  @Test func temperatureBadgeLabel() {
    #expect(TemperatureBadge.label(for: Temperature(value: 21.4)) == "21°")
    #expect(TemperatureBadge.label(for: nil) == "—")
  }

  @Test func changeColorUsesTheSign() {
    #expect(Palette.change(-0.5) == Palette.stockDown)
    #expect(Palette.change(0.5) == Palette.stockUp)
    #expect(Palette.change(nil) == Color.secondary)
  }

  @Test func spacingScale() {
    #expect(Spacing.xs < Spacing.s)
    #expect(Spacing.s < Spacing.l)
  }
}
