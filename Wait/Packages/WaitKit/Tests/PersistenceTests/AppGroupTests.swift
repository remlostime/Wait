//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Persistence
import Testing

@Suite struct AppGroupTests {
  @Test func identifierMatchesEntitlements() {
    #expect(AppGroup.identifier == "group.chenkai.wait.contents")
  }

  @Test func fallsBackToDocumentsWhenTheGroupIsUnavailable() {
    let url = AppGroup.containerURL(groupContainer: { _ in nil })
    #expect(url == URL.documentsDirectory)
  }

  @Test func usesTheGroupContainerWhenAvailable() {
    let group = URL(fileURLWithPath: "/tmp/group-container")
    #expect(AppGroup.containerURL(groupContainer: { _ in group }) == group)
  }

  @Test func fileNames() {
    #expect(AppGroup.fileURL(AppGroup.watchlistFileName).lastPathComponent == "watchlist.json")
    #expect(AppGroup.checklistTemplateFileName == "checklist-template.json")
    #expect(AppGroup.snapshotFileName == "snapshot.json")
    #expect(AppGroup.migrationMarkerFileName == "migration-v1.done")
  }
}
