//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Sharing

// MARK: - SyncState

/// Client sync bookkeeping (overview §8.5), stored in the app group as `sync-state.json`.
public struct SyncState: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    cursor: String? = nil,
    acknowledged: [String: Date] = [:],
    tombstones: [String: Date] = [:],
    lastSyncedAt: Date? = nil
  ) {
    self.cursor = cursor
    self.acknowledged = acknowledged
    self.tombstones = tombstones
    self.lastSyncedAt = lastSyncedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
    acknowledged = try container.decodeIfPresent([String: Date].self, forKey: .acknowledged) ?? [:]
    tombstones = try container.decodeIfPresent([String: Date].self, forKey: .tombstones) ?? [:]
    lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
  }

  // MARK: Public

  public static let initial = SyncState()

  /// The server cursor `"<version>:<symbol>"`. `nil` before the first sync.
  public var cursor: String?
  /// For each symbol, the stamp (item `updatedAt` or tombstone date) that the server last acknowledged.
  public var acknowledged: [String: Date]
  /// Local deletions, by symbol. Kept until a newer remote or local version of the symbol replaces them.
  public var tombstones: [String: Date]
  public var lastSyncedAt: Date?

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case cursor
    case acknowledged
    case tombstones
    case lastSyncedAt
  }
}

// MARK: - AppGroup + syncStateFileName

public extension AppGroup {
  static let syncStateFileName = "sync-state.json"
}

// MARK: - SharedReaderKey + syncState

/// Declared once on `SharedReaderKey`, like plan 02's `.watchlist` and `.checklistTemplate` keys. One declaration
/// resolves for both `@Shared(.syncState)` and `@SharedReader(.syncState)`. Don't add a twin on `SharedKey`, because
/// that makes `@Shared(.syncState)` ambiguous.
public extension SharedReaderKey where Self == FileStorageKey<SyncState>.Default {
  static var syncState: Self {
    Self[.fileStorage(AppGroup.fileURL(AppGroup.syncStateFileName)), default: .initial]
  }
}
