//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import CryptoKit
import Foundation
import Logging

// MARK: - CacheEntry

public struct CacheEntry: Codable, Equatable, Sendable {
  public init(data: Data, fetchedAt: Date, expiresAt: Date) {
    self.data = data
    self.fetchedAt = fetchedAt
    self.expiresAt = expiresAt
  }

  public let data: Data
  public let fetchedAt: Date
  public let expiresAt: Date
}

// MARK: - DiskCache

/// One JSON file per key under `Library/Caches/marketdata/`. File names are `sha256(key).json`. It's a best-effort cache, so I/O errors are logged and otherwise ignored.
public struct DiskCache: Sendable {
  // MARK: Lifecycle

  public init(read: @escaping @Sendable (String) -> CacheEntry?, write: @escaping @Sendable (String, CacheEntry) -> Void) {
    self.read = read
    self.write = write
  }

  // MARK: Public

  public static let disabled = DiskCache(read: { _ in nil }, write: { _, _ in })

  public static var live: DiskCache {
    .files(in: URL.cachesDirectory.appending(path: "marketdata", directoryHint: .isDirectory))
  }

  public var read: @Sendable (String) -> CacheEntry?
  public var write: @Sendable (String, CacheEntry) -> Void

  /// A cache rooted at `directory` (named differently from the `live` property to keep call sites unambiguous).
  public static func files(in directory: URL) -> DiskCache {
    DiskCache(
      read: { key in
        guard let data = try? Data(contentsOf: fileURL(directory: directory, key: key)) else {
          return nil
        }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
      },
      write: { key, entry in
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try JSONEncoder().encode(entry).write(to: fileURL(directory: directory, key: key), options: .atomic)
        } catch {
          Log.network.error("Disk cache write failed for \(key): \(error)")
        }
      }
    )
  }

  // MARK: Private

  private static func fileURL(directory: URL, key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appending(path: "\(digest).json")
  }
}
