//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - PriceInputTests

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

  @Test func acceptsWellFormedGroupingOnly() {
    let fr = Locale(identifier: "fr_FR")
    #expect(PriceInput.parse("1,234.5", locale: us) == .some(dec("1234.5")))
    #expect(PriceInput.parse("1,234,567", locale: us) == .some(dec("1234567")))
    #expect(PriceInput.parse("1.234,5", locale: de) == .some(dec("1234.5")))
    #expect(PriceInput.parse("1\u{202F}234,5", locale: fr) == .some(dec("1234.5")))
    #expect(PriceInput.parse(".5", locale: us) == .some(dec("0.5")))
    #expect(PriceInput.parse("5.", locale: us) == .some(dec("5")))
  }

  @Test func rejectsMisplacedGroupingSeparators() {
    #expect(PriceInput.parse("12.50", locale: de) == nil) // "." is grouping in de_DE, not a decimal point
    #expect(PriceInput.parse("1.2", locale: de) == nil)
    #expect(PriceInput.parse("1,5", locale: us) == nil)
    #expect(PriceInput.parse("1,23,456", locale: us) == nil)
    #expect(PriceInput.parse("1234,567", locale: us) == nil)
    #expect(PriceInput.parse(",5", locale: us) == nil)
    #expect(PriceInput.parse("1,234.", locale: us) == nil)
  }

  @Test func rejectsNonASCIIDigits() {
    #expect(PriceInput.parse("12\u{0661}", locale: us) == nil) // Arabic-Indic digit one
    #expect(PriceInput.parse("\u{0661}\u{0662}", locale: us) == nil)
  }

  @Test func formats() {
    #expect(PriceInput.format(dec("1234.5"), locale: us) == "1234.5")
    #expect(PriceInput.format(dec("1234.5"), locale: de) == "1234,5")
    #expect(PriceInput.format(dec("16"), locale: us) == "16")
    #expect(PriceInput.format(nil, locale: us) == "")
  }
}
