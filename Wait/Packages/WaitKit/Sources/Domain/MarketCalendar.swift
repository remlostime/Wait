//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - MarketCalendar

/// Regular NYSE/Nasdaq session, Mon–Fri 09:30–16:00 America/New_York. There is no holiday table; on a holiday the cache simply refetches once.
public enum MarketCalendar {
  // MARK: Public

  public static let timeZone = TimeZone(identifier: "America/New_York")!

  public static func isOpen(at date: Date) -> Bool {
    guard isWeekday(date) else {
      return false
    }
    return date >= open(on: date) && date < close(on: date)
  }

  public static func nextOpen(after date: Date) -> Date {
    nextSessionBoundary(after: date, boundary: open(on:))
  }

  public static func nextClose(after date: Date) -> Date {
    nextSessionBoundary(after: date, boundary: close(on:))
  }

  /// True on a weekday in `[close, close + minutes)`.
  public static func isWithinPostClose(_ date: Date, minutes: Int) -> Bool {
    guard isWeekday(date) else {
      return false
    }
    let close = close(on: date)
    return date >= close && date < close.addingTimeInterval(TimeInterval(minutes * 60))
  }

  // MARK: Private

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private static func isWeekday(_ date: Date) -> Bool {
    let weekday = calendar.component(.weekday, from: date)
    return weekday != 1 && weekday != 7
  }

  private static func open(on date: Date) -> Date {
    calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date)!
  }

  private static func close(on date: Date) -> Date {
    calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)!
  }

  private static func nextSessionBoundary(after date: Date, boundary: (Date) -> Date) -> Date {
    var day = calendar.startOfDay(for: date)
    for _ in 0 ..< 8 {
      if isWeekday(day) {
        let candidate = boundary(day)
        if candidate > date {
          return candidate
        }
      }
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return boundary(day)
  }
}
