//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DecimalCoding

/// Prices travel as decimal strings (overview D20). These helpers read a string or a number and always write a string.
public enum DecimalCoding {
  // MARK: Public

  public static let posix = Locale(identifier: "en_US_POSIX")

  /// Parses a plain decimal literal such as `"175.50"`, `"-3"` or `"1e-3"`. Returns nil for anything else.
  public static func parse(_ string: String) -> Decimal? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    guard
      !trimmed.isEmpty,
      trimmed.range(of: #"^-?\d+(\.\d+)?([eE][-+]?\d+)?$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    return Decimal(string: trimmed, locale: posix)
  }

  /// `Decimal.description` is locale-independent ("175.5").
  public static func string(_ value: Decimal) -> String {
    value.description
  }
}

public extension Decimal {
  var doubleValue: Double {
    NSDecimalNumber(decimal: self).doubleValue
  }

  /// Rounds half-up to `scale` fractional digits.
  func rounded(scale: Int) -> Decimal {
    var input = self
    var result = Decimal()
    NSDecimalRound(&result, &input, scale, .plain)
    return result
  }
}

public extension KeyedDecodingContainer {
  func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
    guard contains(key), try !decodeNil(forKey: key) else {
      return nil
    }
    if let string = try? decode(String.self, forKey: key) {
      guard let value = DecimalCoding.parse(string) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a decimal: \(string)")
      }
      return value
    }
    return try decode(Decimal.self, forKey: key)
  }

  func decodeDecimal(forKey key: Key) throws -> Decimal {
    guard let value = try decodeDecimalIfPresent(forKey: key) else {
      throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing decimal \(key.stringValue)"))
    }
    return value
  }
}

public extension KeyedEncodingContainer {
  mutating func encodeDecimal(_ value: Decimal, forKey key: Key) throws {
    try encode(DecimalCoding.string(value), forKey: key)
  }

  mutating func encodeDecimalIfPresent(_ value: Decimal?, forKey key: Key) throws {
    if let value {
      try encodeDecimal(value, forKey: key)
    }
  }
}
