//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Logging

// MARK: - MigrationReport

public struct MigrationReport: Equatable, Sendable {
  public init(didRun: Bool, migratedItems: Int, migratedTemplate: Bool) {
    self.didRun = didRun
    self.migratedItems = migratedItems
    self.migratedTemplate = migratedTemplate
  }

  public var didRun: Bool
  public var migratedItems: Int
  public var migratedTemplate: Bool
}

// MARK: - LegacyMigrationError

public enum LegacyMigrationError: Error, Equatable, Sendable {
  /// `stocks` has rows but none could be decoded. Nothing is written, so the migration retries on the next launch.
  case undecodableStocks(rowCount: Int)
}

// MARK: - LegacyMigration

/// One-time move of the legacy Documents files into the app group (overview §7.6).
/// - Inputs: `stocks`, `checklist-<SYMBOL>` and `checklist-items.json`.
/// - Outputs: `watchlist.json` and `checklist-template.json`, plus the `migration-v1.done` marker.
/// - Old files are kept.
/// - A destination watchlist that already has items is never overwritten. A missing, zero-byte or `[]` watchlist counts as absent.
/// - Malformed `stocks` rows are skipped and logged.
/// - If `stocks` exists but can't be read, isn't a JSON array, or has rows but none decode, this throws without writing the marker, so the migration retries on the next launch.
/// - `checklist-template.json` counts as absent when it is missing, zero-byte or `[]`.
public struct LegacyMigration: Sendable {
  // MARK: Lifecycle

  public init(documents: URL, destination: URL) {
    self.documents = documents
    self.destination = destination
  }

  // MARK: Public

  public static var live: LegacyMigration {
    LegacyMigration(documents: URL.documentsDirectory, destination: AppGroup.containerURL())
  }

  public let documents: URL
  public let destination: URL

  public func runIfNeeded(now: Date) throws -> MigrationReport {
    let fileManager = FileManager.default
    let marker = destination.appending(path: AppGroup.migrationMarkerFileName)
    guard !fileManager.fileExists(atPath: marker.path) else {
      return MigrationReport(didRun: false, migratedItems: 0, migratedTemplate: false)
    }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

    let decoder = JSONDecoder() // legacy files use the default `deferredToDate` strategy
    let encoder = JSONEncoder() // matches swift-sharing's default FileStorageKey coding
    var report = MigrationReport(didRun: true, migratedItems: 0, migratedTemplate: false)

    // The template and per-stock checklists are best-effort: an unreadable file falls back to the defaults.
    var template = ChecklistTemplate.defaultItems
    let templateURL = destination.appending(path: AppGroup.checklistTemplateFileName)
    if
      let data = try? Self.readIfPresent(documents.appending(path: "checklist-items.json")),
      let legacyTemplate = try? decoder.decode([ChecklistItem].self, from: data),
      !legacyTemplate.isEmpty
    {
      template = Self.uniqueByID(legacyTemplate)
      if (try? Self.isAbsentOrEmpty(templateURL)) == true { // best-effort like the rest of the template block: an unreadable file is left alone
        try encoder.encode(template).write(to: templateURL, options: .atomic)
        report.migratedTemplate = true
      }
    }

    let watchlistURL = destination.appending(path: AppGroup.watchlistFileName)
    if try Self.isAbsentOrEmpty(watchlistURL), let data = try Self.readIfPresent(documents.appending(path: "stocks")) {
      let rows = try decoder.decode([LossyLegacyStock].self, from: data)
      let stocks = rows.compactMap(\.stock)
      if stocks.isEmpty, !rows.isEmpty {
        throw LegacyMigrationError.undecodableStocks(rowCount: rows.count)
      }
      if stocks.count < rows.count {
        Log.persistence.error("Legacy migration skipped \(rows.count - stocks.count) malformed stock rows")
      }
      var checklists: [String: [ChecklistItem]] = [:]
      for stock in stocks {
        let url = documents.appending(path: "checklist-\(stock.symbol)")
        if let data = try? Self.readIfPresent(url), let items = try? decoder.decode([ChecklistItem].self, from: data) {
          let key = LegacyStockMapper.mappedSymbol(stock.symbol)
          if checklists[key] == nil { // the mapper keeps the first row of a duplicated symbol, so keep its checklist too
            checklists[key] = Self.uniqueByID(items)
          }
        }
      }
      let items = LegacyStockMapper.items(from: stocks, checklists: checklists, template: template, now: now)
      try encoder.encode(items).write(to: watchlistURL, options: .atomic)
      report.migratedItems = items.count
    }

    try Data().write(to: marker, options: .atomic)
    return report
  }

  // MARK: Private

  /// Decodes one row, or nil for a malformed row, without failing the whole array.
  private struct LossyLegacyStock: Decodable {
    let stock: LegacyStock?

    init(from decoder: any Decoder) throws {
      stock = try? LegacyStock(from: decoder)
    }
  }

  /// Returns nil only when the file doesn't exist. Any other read error is rethrown.
  private static func readIfPresent(_ url: URL) throws -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
  }

  private static func isAbsentOrEmpty(_ url: URL) throws -> Bool {
    guard let data = try readIfPresent(url), !data.isEmpty else {
      return true
    }
    return (try? JSONSerialization.jsonObject(with: data) as? [Any])?.isEmpty == true
  }

  private static func uniqueByID(_ items: [ChecklistItem]) -> [ChecklistItem] {
    var seen = Set<UUID>()
    return items.filter { seen.insert($0.id).inserted }
  }
}
