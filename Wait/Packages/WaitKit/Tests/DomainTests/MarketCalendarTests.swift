//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - MarketCalendarTests

@Suite struct MarketCalendarTests {
  func utc(_ iso: String) throws -> Date {
    try Date(iso, strategy: .iso8601)
  }

  @Test func openAndClosedDuringAWeekday() throws {
    #expect(try MarketCalendar.isOpen(at: utc("2026-11-20T15:00:00Z"))) // Fri 10:00 EST
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-20T21:00:00Z"))) // Fri 16:00 EST (close is exclusive)
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-21T15:00:00Z"))) // Saturday
  }

  @Test func nextOpenAcrossDSTStart() throws {
    // Fri 2026-03-06 16:00 EST → Mon 2026-03-09 09:30 EDT
    #expect(try MarketCalendar.nextOpen(after: utc("2026-03-06T21:00:00Z")) == utc("2026-03-09T13:30:00Z"))
  }

  @Test func nextOpenAcrossDSTEnd() throws {
    // Fri 2026-10-30 16:00 EDT → Mon 2026-11-02 09:30 EST
    #expect(try MarketCalendar.nextOpen(after: utc("2026-10-30T20:00:00Z")) == utc("2026-11-02T14:30:00Z"))
    #expect(try !MarketCalendar.isOpen(at: utc("2026-11-02T14:00:00Z")))
    #expect(try MarketCalendar.isOpen(at: utc("2026-11-02T14:30:00Z")))
  }

  @Test func nextClose() throws {
    #expect(try MarketCalendar.nextClose(after: utc("2026-11-20T15:00:00Z")) == utc("2026-11-20T21:00:00Z"))
    #expect(try MarketCalendar.nextClose(after: utc("2026-11-20T22:00:00Z")) == utc("2026-11-23T21:00:00Z"))
  }

  @Test func postCloseWindow() throws {
    #expect(try MarketCalendar.isWithinPostClose(utc("2026-11-20T21:10:00Z"), minutes: 30))
    #expect(try !MarketCalendar.isWithinPostClose(utc("2026-11-20T21:40:00Z"), minutes: 30))
    #expect(try !MarketCalendar.isWithinPostClose(utc("2026-11-21T21:10:00Z"), minutes: 30))
  }
}
