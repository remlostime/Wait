//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
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
}
