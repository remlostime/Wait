//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - MarketTypesCodingTests

@Suite struct MarketTypesCodingTests {
  @Test func quoteRoundTripsWithDecimalStrings() throws {
    let quote = Quote(symbol: "AAPL", price: dec("189.98"), previousClose: dec("187.66"), changePercent: 1.23, volume: 1000, asOf: fridayOpen)
    let data = try JSONEncoder().encode(quote)
    #expect(String(decoding: data, as: UTF8.self).contains(#""price":"189.98""#))
    #expect(try JSONDecoder().decode(Quote.self, from: data) == quote)
  }

  @Test func malformedDecimalStringThrows() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(Quote.self, from: Data(#"{"symbol":"X","price":"abc","asOf":0}"#.utf8))
    }
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(PriceLadder.self, from: Data(#"{"buyHigh":"abc"}"#.utf8))
    }
  }

  @Test func decimalParsingRejectsNonASCIIDigits() {
    #expect(DecimalCoding.parse("12") == dec("12"))
    #expect(DecimalCoding.parse("12\u{0661}") == nil) // Arabic-Indic digit one
  }

  @Test func quoteMarkedStale() {
    let quote = Quote(symbol: "AAPL", price: 1, asOf: fridayOpen)
    #expect(quote.with(isStale: true).isStale)
    #expect(quote.with(isStale: true).price == 1)
  }

  @Test func seriesRoundTrips() throws {
    let series = PriceSeries(symbol: "AAPL", range: .oneDay, points: [PricePoint(date: fridayOpen, close: dec("0.0075"))], asOf: fridayOpen, delayedMinutes: 15)
    #expect(try JSONDecoder().decode(PriceSeries.self, from: JSONEncoder().encode(series)) == series)
  }

  @Test func seriesWithoutOptionalFieldsDecodes() throws {
    let json = #"{"symbol":"AAPL","range":"1Y","points":[],"asOf":0}"#
    let series = try JSONDecoder().decode(PriceSeries.self, from: Data(json.utf8))
    #expect(series.isStale == false)
    #expect(series.delayedMinutes == nil)
  }

  @Test func chartRangeRawValues() {
    #expect(ChartRange.allCases.map(\.rawValue) == ["1D", "1W", "1M", "1Y", "5Y"])
  }
}
