//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - PriceInput

/// Parses user-typed prices in the user's locale and formats ladder values back for editing.
public enum PriceInput {
  /// A grouping separator is only accepted in a well-formed position (`1,234.5`, `1.234,5`); `12.50` in de_DE is invalid, not 1250.
  /// `nil` means invalid. `.some(nil)` means the field is empty. Negative values are invalid.
  public static func parse(_ text: String, locale: Locale) -> Decimal?? {
    var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if string.isEmpty {
      return .some(nil)
    }
    for symbol in ["$", locale.currencySymbol ?? ""] where !symbol.isEmpty {
      string = string.replacingOccurrences(of: symbol, with: "")
    }
    let decimalSeparator = locale.decimalSeparator ?? "."
    let groupingSeparator = locale.groupingSeparator ?? ","
    for space in [" ", "\u{00A0}", "\u{202F}"] {
      string = string.replacingOccurrences(of: space, with: "")
    }
    let decimal = NSRegularExpression.escapedPattern(for: decimalSeparator)
    let grouping = NSRegularExpression.escapedPattern(for: groupingSeparator)
    let plain = "^[0-9]*(\(decimal)[0-9]*)?$"
    let grouped = "^[0-9]{1,3}(\(grouping)[0-9]{3})+(\(decimal)[0-9]+)?$"
    let canGroup = !groupingSeparator.isEmpty && groupingSeparator != decimalSeparator
    if canGroup, string.range(of: grouped, options: .regularExpression) != nil {
      string = string.replacingOccurrences(of: groupingSeparator, with: "")
    } else if string.range(of: plain, options: .regularExpression) == nil {
      return nil
    }
    if decimalSeparator != "." {
      string = string.replacingOccurrences(of: decimalSeparator, with: ".")
    }
    guard
      string.range(of: "[0-9]", options: .regularExpression) != nil,
      let value = Decimal(string: string, locale: DecimalCoding.posix)
    else {
      return nil
    }
    return value
  }

  /// No grouping, 0–4 fraction digits, in the given locale. Empty string for nil.
  public static func format(_ value: Decimal?, locale: Locale) -> String {
    guard let value else {
      return ""
    }
    return value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 4)))
  }
}
