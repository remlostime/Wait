//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

@Suite struct PriceInputTests {
  let us = Locale(identifier: "en_US")
  let de = Locale(identifier: "de_DE")

  @Test func parsesGroupedUSInput() {
    #expect(PriceInput.parse("1,234.50", locale: us) == .some(dec("1234.50")))
    #expect(PriceInput.parse("$12", locale: us) == .some(dec("12")))
    #expect(PriceInput.parse(" 0.0075 ", locale: us) == .some(dec("0.0075")))
  }

  @Test func parsesGermanDecimalComma() {
    #expect(PriceInput.parse("0,75", locale: de) == .some(dec("0.75")))
    #expect(PriceInput.parse("1.234,5", locale: de) == .some(dec("1234.5")))
  }

  @Test func emptyIsSomeNil() {
    let result = PriceInput.parse("   ", locale: us)
    #expect(result != nil)
    #expect(result! == nil)
  }

  @Test func invalidIsNil() {
    #expect(PriceInput.parse("abc", locale: us) == nil)
    #expect(PriceInput.parse("-5", locale: us) == nil)
    #expect(PriceInput.parse("1.2.3", locale: us) == nil)
  }

  @Test func formats() {
    #expect(PriceInput.format(dec("1234.5"), locale: us) == "1234.5")
    #expect(PriceInput.format(dec("1234.5"), locale: de) == "1234,5")
    #expect(PriceInput.format(dec("16"), locale: us) == "16")
    #expect(PriceInput.format(nil, locale: us) == "")
  }
}
