//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
@testable import SyncClient
import Testing

struct SyncStampTests {
  @Test
  func formatsWithExactlyThreeFractionDigits() {
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_795_186_800_123)) == "2026-11-20T15:00:00.123Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_795_186_800_000)) == "2026-11-20T15:00:00.000Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 0)) == "1970-01-01T00:00:00.000Z")
    #expect(SyncStamp.string(from: SyncStamp.date(milliseconds: 1_798_761_599_999)) == "2026-12-31T23:59:59.999Z")
  }

  @Test
  func parsesWithAndWithoutFraction() {
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.123Z").map(SyncStamp.milliseconds) == 1_795_186_800_123)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00Z").map(SyncStamp.milliseconds) == 1_795_186_800_000)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.1234567Z").map(SyncStamp.milliseconds) == 1_795_186_800_123)
    #expect(SyncStamp.date(from: "2026-11-20T15:00:00.5Z").map(SyncStamp.milliseconds) == 1_795_186_800_500)
  }

  @Test
  func rejectsMalformedStrings() {
    for text in ["", "garbage", "2026-11-20 15:00:00Z", "2026-11-20T15:00:00", "2026-13-20T15:00:00Z", "2026-11-20T15:00:00.Z"] {
      #expect(SyncStamp.date(from: text) == nil, "\(text)")
    }
  }

  @Test
  func comparesByWholeMillisecondsIgnoringDoubleNoise() {
    let base = Date(timeIntervalSince1970: 1_795_186_800.123)
    let noisy = Date(timeIntervalSince1970: (1_795_186_800.123).nextUp)
    let parsed = SyncStamp.date(from: SyncStamp.string(from: base))!
    #expect(SyncStamp.same(base, noisy))
    #expect(SyncStamp.same(base, parsed))
    #expect(!SyncStamp.same(base, base.addingTimeInterval(0.001)))
    #expect(!SyncStamp.same(base, nil))
    #expect(SyncStamp.same(nil, nil))
  }

  @Test
  func reportsAddUp() {
    let sum = SyncReport(pushed: 1, pulled: 2, applied: 3, rounds: 1) + SyncReport(pushed: 4, pulled: 5, applied: 6, rounds: 2)
    #expect(sum == SyncReport(pushed: 5, pulled: 7, applied: 9, rounds: 3))
  }
}
