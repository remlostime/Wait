//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotCoding

/// Encodes a `WatchlistSnapshot` for `WCSession.updateApplicationContext`.
///
/// The application context is capped at about 65 KB. When the snapshot is larger than `maxBytes`,
/// `encode` drops rows from the end until it fits. Favorites come first in a snapshot, so they survive longest.
public enum SnapshotCoding {
  // MARK: Public

  public static let contextKey = "snapshot"
  public static let defaultMaxBytes = 60000

  public static func encode(_ snapshot: WatchlistSnapshot, maxBytes: Int = defaultMaxBytes) throws -> Data {
    let encoder = makeEncoder()
    var rows = snapshot.rows
    while true {
      let candidate = WatchlistSnapshot(generatedAt: snapshot.generatedAt, quotesAsOf: snapshot.quotesAsOf, rows: rows)
      let data = try encoder.encode(candidate)
      if data.count <= maxBytes {
        return data
      }
      guard !rows.isEmpty else {
        throw SnapshotCodingError.tooLarge(bytes: data.count, maxBytes: maxBytes)
      }
      rows.removeLast()
    }
  }

  public static func decode(_ data: Data) -> WatchlistSnapshot? {
    try? JSONDecoder().decode(WatchlistSnapshot.self, from: data)
  }

  // MARK: Private

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

// MARK: - SnapshotCodingError

public enum SnapshotCodingError: Error, Equatable, Sendable {
  case tooLarge(bytes: Int, maxBytes: Int)
}
