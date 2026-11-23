//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation
import Security

// MARK: - IdentityClient

/// The anonymous identity (overview D14). It lives in iCloud Keychain (synchronizable,
/// AfterFirstUnlock), so the user's devices share one server account and it survives reinstalls.
@DependencyClient
public struct IdentityClient: Sendable {
  /// Get-or-create. Never returns two different IDs for concurrent first calls on one device.
  public var anonymousID: @Sendable () throws -> UUID
  /// Deletes the ID on every device that shares iCloud Keychain. The next `anonymousID()` mints a new one.
  public var reset: @Sendable () throws -> Void
}

extension IdentityClient {
  public static let account = "anonymous-id"

  public static func live(keychain: KeychainClient) -> IdentityClient {
    let lock = LockIsolated(())
    return IdentityClient(
      anonymousID: {
        try lock.withValue { _ in
          if let id = try storedID(keychain) {
            return id
          }
          let id = UUID()
          do {
            try keychain.write(Data(id.uuidString.utf8), account, true)
          } catch let error as KeychainError where error.status == errSecDuplicateItem {
            // The iCloud copy arrived between our read and our add: keep the one that synced.
            guard let existing = try storedID(keychain) else { throw error }
            return existing
          }
          return id
        }
      },
      reset: { try keychain.delete(account, true) }
    )
  }

  private static func storedID(_ keychain: KeychainClient) throws -> UUID? {
    guard let data = try keychain.read(account, true), let raw = String(data: data, encoding: .utf8) else {
      return nil
    }
    return UUID(uuidString: raw)
  }
}

// MARK: - IdentityClient + DependencyKey

extension IdentityClient: DependencyKey {
  public static let liveValue = IdentityClient.live(keychain: .liveValue)
  public static let testValue = IdentityClient()
}

extension DependencyValues {
  public var identity: IdentityClient {
    get { self[IdentityClient.self] }
    set { self[IdentityClient.self] = newValue }
  }
}
