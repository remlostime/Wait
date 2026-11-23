//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WireDates

/// ISO 8601 UTC with milliseconds, which is what the server emits via `toISOString()` (overview §9).
/// Decoding also accepts whole seconds.
public enum WireDates {
  // MARK: Public

  public static func string(from date: Date) -> String {
    fractional.format(date)
  }

  public static func date(from string: String) -> Date? {
    (try? fractional.parse(string)) ?? (try? whole.parse(string))
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      guard let parsed = WireDates.date(from: raw) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(raw)")
      }
      return parsed
    }
    return decoder
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(WireDates.string(from: date))
    }
    return encoder
  }

  // MARK: Private

  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let whole = Date.ISO8601FormatStyle()
}
