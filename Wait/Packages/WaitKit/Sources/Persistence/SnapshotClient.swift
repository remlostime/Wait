//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation
import Logging
#if canImport(WidgetKit)
  import WidgetKit
#endif

// MARK: - SnapshotClient

/// Publishes the watchlist snapshot: it saves `snapshot.json` and reloads the widgets. Plan 03 also sends it to the watch, from `AppFeature`.
@DependencyClient
public struct SnapshotClient: Sendable {
  public var publish: @Sendable (_ snapshot: WatchlistSnapshot) async -> Void
}

// MARK: DependencyKey

extension SnapshotClient: DependencyKey {
  public static let liveValue = SnapshotClient(
    publish: { snapshot in
      do {
        try SnapshotStore.appGroup.save(snapshot)
      } catch {
        Log.persistence.error("Snapshot save failed: \(error)")
      }
      #if canImport(WidgetKit)
        await MainActor.run {
          WidgetCenter.shared.reloadAllTimelines()
        }
      #endif
    }
  )

  public static let testValue = SnapshotClient()
  public static let previewValue = SnapshotClient(publish: { _ in })
}

public extension DependencyValues {
  var snapshotClient: SnapshotClient {
    get { self[SnapshotClient.self] }
    set { self[SnapshotClient.self] = newValue }
  }
}
