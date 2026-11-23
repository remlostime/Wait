//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import MarketDataClient
import Testing

@Suite struct DiskCacheTests {
  func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "marketdata-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  @Test func writeThenReadFromANewInstance() {
    let directory = tempDirectory()
    let entry = CacheEntry(data: Data("hello".utf8), fetchedAt: fridayOpen, expiresAt: fridayOpen + 60)
    DiskCache.files(in: directory).write("quote:AAPL", entry)
    #expect(DiskCache.files(in: directory).read("quote:AAPL") == entry)
    #expect(DiskCache.files(in: directory).read("quote:MSFT") == nil)
  }

  @Test func corruptFileReadsNil() throws {
    let directory = tempDirectory()
    let cache = DiskCache.files(in: directory)
    cache.write("k", CacheEntry(data: Data(), fetchedAt: fridayOpen, expiresAt: fridayOpen))
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    try Data("garbage".utf8).write(to: file)
    #expect(cache.read("k") == nil)
  }

  @Test func disabledNeverStores() {
    DiskCache.disabled.write("k", CacheEntry(data: Data(), fetchedAt: fridayOpen, expiresAt: fridayOpen))
    #expect(DiskCache.disabled.read("k") == nil)
  }
}
