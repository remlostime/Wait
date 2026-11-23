//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Persistence
import Testing

@Suite struct LegacyMigrationTests {
  let now = Date(timeIntervalSince1970: 1_795_186_800)
  // Two malformed rows (a number, and an object without "symbol") must be skipped, not fail the migration.
  let legacyStocks = #"""
  [
    {"symbol":"AAPL","name":"Apple","expectedPrice":{"amount":150,"currencyCode":"USD"},"memo":"keep","expectedPriceHistory":[]},
    42,
    {"name":"no symbol"},
    {"symbol":"Empty","name":"Empty","expectedPrice":{"amount":0,"currencyCode":"USD"},"memo":"","expectedPriceHistory":[]},
    {"symbol":"MSFT","name":"Microsoft","expectedPrice":{"amount":300.5,"currencyCode":"USD"},"memo":"","expectedPriceHistory":[]}
  ]
  """#
  let aaplChecklist = #"[{"name":"Custom","isChecked":true,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}]"#
  let template = #"[{"name":"T1","isChecked":false,"id":"00000000-0000-0000-0000-0000000000AA"}]"#

  func dirs() throws -> (documents: URL, group: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
    let documents = root.appending(path: "Documents")
    let group = root.appending(path: "Group")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    return (documents, group)
  }

  func decodeWatchlist(_ group: URL) throws -> [WatchlistItem] {
    try JSONDecoder().decode([WatchlistItem].self, from: Data(contentsOf: group.appending(path: "watchlist.json")))
  }

  func markerExists(_ group: URL) -> Bool {
    FileManager.default.fileExists(atPath: group.appending(path: "migration-v1.done").path)
  }

  @Test func migratesStocksChecklistsAndTemplateSkippingMalformedRows() throws {
    let (documents, group) = try dirs()
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    try Data(aaplChecklist.utf8).write(to: documents.appending(path: "checklist-AAPL"))
    try Data(template.utf8).write(to: documents.appending(path: "checklist-items.json"))

    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)

    #expect(report == MigrationReport(didRun: true, migratedItems: 2, migratedTemplate: true))
    let items = try decodeWatchlist(group)
    #expect(items.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(items[0].memo == "keep")
    #expect(items[0].checklist.map(\.name) == ["Custom"])
    #expect(items[1].checklist.map(\.name) == ["T1"])
    #expect(items[1].ladder.buyHigh == Decimal(string: "300.5"))
    #expect(FileManager.default.fileExists(atPath: group.appending(path: "checklist-template.json").path))
    #expect(markerExists(group))
    #expect(FileManager.default.fileExists(atPath: documents.appending(path: "stocks").path)) // old files are kept
  }

  @Test func secondRunIsANoop() throws {
    let (documents, group) = try dirs()
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let migration = LegacyMigration(documents: documents, destination: group)
    _ = try migration.runIfNeeded(now: now)
    try Data("[]".utf8).write(to: documents.appending(path: "stocks"))
    let second = try migration.runIfNeeded(now: now)
    #expect(second == MigrationReport(didRun: false, migratedItems: 0, migratedTemplate: false))
    #expect(try decodeWatchlist(group).count == 2)
  }

  @Test func freshInstallWritesOnlyTheMarker() throws {
    let (documents, group) = try dirs()
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report == MigrationReport(didRun: true, migratedItems: 0, migratedTemplate: false))
    #expect(!FileManager.default.fileExists(atPath: group.appending(path: "watchlist.json").path))
    #expect(markerExists(group))
  }

  @Test func neverOverwritesANonEmptyWatchlist() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data(#"[{"symbol":"KEEP"}]"#.utf8).write(to: group.appending(path: "watchlist.json"))
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report.migratedItems == 0)
    #expect(try decodeWatchlist(group).map(\.symbol) == ["KEEP"])
  }

  @Test func anEmptyWatchlistFileCountsAsAbsent() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: group.appending(path: "watchlist.json"))
    try Data(legacyStocks.utf8).write(to: documents.appending(path: "stocks"))
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report.migratedItems == 2)
    #expect(try decodeWatchlist(group).map(\.symbol) == ["AAPL", "MSFT"])
  }

  @Test func unreadableStocksThrowsAndLeavesNoMarker() throws {
    let (documents, group) = try dirs()
    // A directory named "stocks" exists but can't be read as data: not "missing", so the migration must retry later.
    try FileManager.default.createDirectory(at: documents.appending(path: "stocks"), withIntermediateDirectories: true)
    #expect(throws: (any Error).self) {
      try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    }
    #expect(!markerExists(group))
  }

  @Test func aZeroByteTemplateFileDoesNotBlockMigratingTheLegacyTemplate() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    try Data().write(to: group.appending(path: "checklist-template.json")) // swift-sharing creates empty files when subscribing
    try Data(template.utf8).write(to: documents.appending(path: "checklist-items.json"))

    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)

    #expect(report.migratedTemplate)
    let data = try Data(contentsOf: group.appending(path: "checklist-template.json"))
    #expect(try JSONDecoder().decode([ChecklistItem].self, from: data).map(\.name) == ["T1"])
  }

  @Test func aNonEmptyTemplateFileIsNeverOverwritten() throws {
    let (documents, group) = try dirs()
    try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    let existing = #"[{"name":"Mine","isChecked":false,"id":"00000000-0000-0000-0000-0000000000BB"}]"#
    try Data(existing.utf8).write(to: group.appending(path: "checklist-template.json"))
    try Data(template.utf8).write(to: documents.appending(path: "checklist-items.json"))

    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)

    #expect(!report.migratedTemplate)
    let data = try Data(contentsOf: group.appending(path: "checklist-template.json"))
    #expect(try JSONDecoder().decode([ChecklistItem].self, from: data).map(\.name) == ["Mine"])
  }

  @Test func rowsThatAllFailToDecodeThrowAndLeaveNoMarker() throws {
    let (documents, group) = try dirs()
    try Data(#"[42, {"name":"no symbol"}]"#.utf8).write(to: documents.appending(path: "stocks"))
    #expect(throws: LegacyMigrationError.undecodableStocks(rowCount: 2)) {
      try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    }
    #expect(!markerExists(group))
    #expect(!FileManager.default.fileExists(atPath: group.appending(path: "watchlist.json").path))
  }

  @Test func anEmptyStocksArrayStillMigratesCleanly() throws {
    let (documents, group) = try dirs()
    try Data("[]".utf8).write(to: documents.appending(path: "stocks"))
    let report = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)
    #expect(report == MigrationReport(didRun: true, migratedItems: 0, migratedTemplate: false))
    #expect(markerExists(group))
  }

  @Test func theFirstDuplicateSymbolKeepsItsOwnChecklist() throws {
    let (documents, group) = try dirs()
    let duplicates = #"""
    [
      {"symbol":" AAPL","name":"First","memo":"first"},
      {"symbol":"AAPL","name":"Second","memo":"second"}
    ]
    """#
    let first = #"[{"name":"FirstList","isChecked":true,"id":"00000000-0000-0000-0000-0000000000C1"}]"#
    let second = #"[{"name":"SecondList","isChecked":true,"id":"00000000-0000-0000-0000-0000000000C2"}]"#
    try Data(duplicates.utf8).write(to: documents.appending(path: "stocks"))
    try Data(first.utf8).write(to: documents.appending(path: "checklist- AAPL"))
    try Data(second.utf8).write(to: documents.appending(path: "checklist-AAPL"))

    _ = try LegacyMigration(documents: documents, destination: group).runIfNeeded(now: now)

    let items = try decodeWatchlist(group)
    #expect(items.map(\.symbol) == ["AAPL"])
    #expect(items[0].memo == "first")
    #expect(items[0].checklist.map(\.name) == ["FirstList"])
  }
}
