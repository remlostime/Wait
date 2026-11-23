//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

/// Every persisted or synced timestamp is truncated to whole milliseconds (overview D21).
public extension Date {
  /// Whole milliseconds since 1970. The +0.001 absorbs Double error, so re-truncating a truncated date is stable.
  var millisecondsSince1970: Int64 {
    Int64((timeIntervalSince1970 * 1000 + 0.001).rounded(.down))
  }

  var truncatedToMilliseconds: Date {
    Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000)
  }

  /// Use this, not `==`, when comparing a local stamp with one echoed by the server.
  func isSameMillisecond(as other: Date) -> Bool {
    millisecondsSince1970 == other.millisecondsSince1970
  }
}
