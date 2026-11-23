//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - AppGroup

/// Files shared by the app and the widget (overview §9).
public enum AppGroup {
  // MARK: Public

  public static let identifier = "group.chenkai.wait.contents"

  public static let watchlistFileName = "watchlist.json"
  public static let checklistTemplateFileName = "checklist-template.json"
  public static let snapshotFileName = "snapshot.json"
  public static let migrationMarkerFileName = "migration-v1.done"

  /// The group container, or the app's Documents when the entitlement is missing (package tests, unsigned builds).
  public static func containerURL(
    groupContainer: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
  ) -> URL {
    groupContainer(identifier) ?? URL.documentsDirectory
  }

  public static func fileURL(_ name: String) -> URL {
    containerURL().appending(path: name)
  }
}
