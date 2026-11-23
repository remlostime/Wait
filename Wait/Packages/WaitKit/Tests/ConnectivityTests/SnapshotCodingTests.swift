//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - SnapshotCodingTests

@Suite
struct SnapshotCodingTests {
  @Test
  func roundTripPreservesDecimalsAndDates() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 3)

    let data = try SnapshotCoding.encode(snapshot)

    #expect(SnapshotCoding.decode(data) == snapshot)
  }

  @Test
  func encodesPricesAsDecimalStrings() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)

    let json = try String(decoding: SnapshotCoding.encode(snapshot), as: UTF8.self)

    #expect(json.contains("\"price\":\"3.133\""))
  }

  @Test
  func dropsTrailingRowsUntilThePayloadFits() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 40)
    let full = try SnapshotCoding.encode(snapshot, maxBytes: .max)
    let limit = full.count / 2

    let data = try SnapshotCoding.encode(snapshot, maxBytes: limit)
    let decoded = try #require(SnapshotCoding.decode(data))

    #expect(data.count <= limit)
    #expect(decoded.rows.count < snapshot.rows.count)
    #expect(decoded.rows == Array(snapshot.rows.prefix(decoded.rows.count)))
    #expect(decoded.generatedAt == snapshot.generatedAt)
  }

  @Test
  func throwsWhenEvenAnEmptySnapshotDoesNotFit() throws {
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)

    #expect(throws: SnapshotCodingError.self) {
      try SnapshotCoding.encode(snapshot, maxBytes: 10)
    }
  }

  @Test
  func decodeReturnsNilForGarbage() {
    #expect(SnapshotCoding.decode(Data("not json".utf8)) == nil)
  }
}
