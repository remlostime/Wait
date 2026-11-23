//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - SnapshotStore

/// Reads and writes `snapshot.json` atomically. The widget reads it; the app writes it through `SnapshotClient`.
public struct SnapshotStore: Sendable {
  // MARK: Lifecycle

  public init(load: @escaping @Sendable () -> WatchlistSnapshot?, save: @escaping @Sendable (WatchlistSnapshot) throws -> Void) {
    self.load = load
    self.save = save
  }

  // MARK: Public

  public var load: @Sendable () -> WatchlistSnapshot?
  public var save: @Sendable (WatchlistSnapshot) throws -> Void

  public static var appGroup: SnapshotStore {
    .live(url: AppGroup.fileURL(AppGroup.snapshotFileName))
  }

  public static func live(url: URL) -> SnapshotStore {
    SnapshotStore(
      load: {
        guard let data = try? Data(contentsOf: url) else {
          return nil
        }
        return try? JSONDecoder().decode(WatchlistSnapshot.self, from: data)
      },
      save: { snapshot in
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      }
    )
  }
}
