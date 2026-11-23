//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Foundation
import Security
import Testing
@testable import APIClient

// MARK: - IdentityClientTests

@Suite
struct IdentityClientTests {
  @Test
  func createsTheIDOnceAndStoresItSynchronizable() throws {
    let keychain = KeychainClient.inMemory()
    let identity = IdentityClient.live(keychain: keychain)
    let first = try identity.anonymousID()
    let second = try identity.anonymousID()
    #expect(first == second)
    #expect(try keychain.read(IdentityClient.account, true) == Data(first.uuidString.utf8))
    #expect(try keychain.read(IdentityClient.account, false) == nil)
  }

  @Test
  func resetMakesTheNextCallCreateANewID() throws {
    let identity = IdentityClient.live(keychain: .inMemory())
    let before = try identity.anonymousID()
    try identity.reset()
    #expect(try identity.anonymousID() != before)
  }

  @Test
  func replacesACorruptStoredValue() throws {
    let keychain = KeychainClient.inMemory()
    try keychain.write(Data("not-a-uuid".utf8), IdentityClient.account, true)
    let id = try IdentityClient.live(keychain: keychain).anonymousID()
    #expect(try keychain.read(IdentityClient.account, true) == Data(id.uuidString.utf8))
  }

  @Test
  func aDuplicateOnAddReturnsTheIDThatSyncedInMeanwhile() throws {
    let synced = UUID()
    let reads = LockIsolated(0)
    let keychain = KeychainClient(
      read: { _, _ in
        // The first read finds nothing; by the second read the iCloud copy has arrived.
        let count = reads.withValue { count -> Int in
          count += 1
          return count
        }
        return count == 1 ? nil : Data(synced.uuidString.utf8)
      },
      write: { _, _, _ in throw KeychainError(status: errSecDuplicateItem) },
      delete: { _, _ in }
    )
    #expect(try IdentityClient.live(keychain: keychain).anonymousID() == synced)
  }

  @Test
  func aDuplicateWithNothingReadableAfterwardsStillThrows() {
    let keychain = KeychainClient(
      read: { _, _ in nil },
      write: { _, _, _ in throw KeychainError(status: errSecDuplicateItem) },
      delete: { _, _ in }
    )
    #expect(throws: KeychainError(status: errSecDuplicateItem)) { try IdentityClient.live(keychain: keychain).anonymousID() }
  }

  @Test
  func otherKeychainFailuresStillThrow() {
    let keychain = KeychainClient(
      read: { _, _ in nil },
      write: { _, _, _ in throw KeychainError(status: errSecInteractionNotAllowed) },
      delete: { _, _ in }
    )
    #expect(throws: KeychainError(status: errSecInteractionNotAllowed)) { try IdentityClient.live(keychain: keychain).anonymousID() }
  }
}
