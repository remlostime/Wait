//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Testing
@testable import APIClient

// MARK: - WireDatesTests

@Suite
struct WireDatesTests {
  private let fridayClose = Date(timeIntervalSince1970: 1_795_208_400) // 2026-11-20T21:00:00Z

  @Test
  func formatsUTCWithMilliseconds() {
    #expect(WireDates.string(from: fridayClose) == "2026-11-20T21:00:00.000Z")
  }

  @Test
  func parsesWithAndWithoutFractionalSeconds() {
    #expect(WireDates.date(from: "2026-11-20T21:00:00.000Z") == fridayClose)
    #expect(WireDates.date(from: "2026-11-20T21:00:00Z") == fridayClose)
    #expect(WireDates.date(from: "yesterday") == nil)
  }

  @Test
  func roundTripsThroughTheCoders() throws {
    struct Box: Codable, Equatable { let at: Date }
    let data = try WireDates.makeEncoder().encode(Box(at: fridayClose))
    #expect(String(decoding: data, as: UTF8.self) == #"{"at":"2026-11-20T21:00:00.000Z"}"#)
    #expect(try WireDates.makeDecoder().decode(Box.self, from: data) == Box(at: fridayClose))
  }
}
