//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - SyncStamp

/// Whole-millisecond timestamps for sync (overview D21; plan 05 deviation 4).
/// Two dates are "the same stamp" when they round to the same Unix millisecond. The wire format is always
/// `yyyy-MM-ddTHH:mm:ss.SSSZ`, built by hand, so Double noise and formatter truncation can't create perpetual pending changes.
public enum SyncStamp {
  // MARK: Public

  public static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  public static func date(milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  }

  public static func same(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
      case (nil, nil):
        true
      case let (lhs?, rhs?):
        milliseconds(lhs) == milliseconds(rhs)
      default:
        false
    }
  }

  public static func string(from date: Date) -> String {
    let total = milliseconds(date)
    let seconds = total >= 0 ? total / 1000 : (total - 999) / 1000
    let fraction = Int(total - seconds * 1000)
    let components = utcCalendar().dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSince1970: Double(seconds))
    )
    return "\(pad(components.year ?? 0, 4))-\(pad(components.month ?? 0, 2))-\(pad(components.day ?? 0, 2))"
      + "T\(pad(components.hour ?? 0, 2)):\(pad(components.minute ?? 0, 2)):\(pad(components.second ?? 0, 2))"
      + ".\(pad(fraction, 3))Z"
  }

  /// Parses `yyyy-MM-ddTHH:mm:ss[.f…]Z` (UTC only). Fractions are rounded to whole milliseconds.
  public static func date(from text: String) -> Date? {
    guard text.hasSuffix("Z") else {
      return nil
    }
    let parts = text.dropLast().split(separator: "T", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      return nil
    }
    let dateFields = parts[0].split(separator: "-", omittingEmptySubsequences: false)
    let timeAndFraction = parts[1].split(separator: ".", omittingEmptySubsequences: false)
    guard dateFields.count == 3, (1 ... 2).contains(timeAndFraction.count) else {
      return nil
    }
    let timeFields = timeAndFraction[0].split(separator: ":", omittingEmptySubsequences: false)
    guard
      timeFields.count == 3,
      let year = Int(dateFields[0]), dateFields[0].count == 4,
      let month = Int(dateFields[1]), (1 ... 12).contains(month),
      let day = Int(dateFields[2]), (1 ... 31).contains(day),
      let hour = Int(timeFields[0]), (0 ... 23).contains(hour),
      let minute = Int(timeFields[1]), (0 ... 59).contains(minute),
      let second = Int(timeFields[2]), (0 ... 60).contains(second)
    else {
      return nil
    }

    var fractionMilliseconds: Int64 = 0
    if timeAndFraction.count == 2 {
      let digits = timeAndFraction[1]
      guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Double("0.\(digits)") else {
        return nil
      }
      fractionMilliseconds = Int64((value * 1000).rounded())
    }

    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let whole = utcCalendar().date(from: components) else {
      return nil
    }
    return date(milliseconds: Int64(whole.timeIntervalSince1970.rounded()) * 1000 + fractionMilliseconds)
  }

  // MARK: Private

  private static func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
