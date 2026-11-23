//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation
import Security

// MARK: - KeychainClient

/// Generic-password items under service `com.chenkai.wait`. Every query sets `kSecAttrSynchronizable`
/// explicitly (risk 9), so synchronizable and device-only items never shadow each other.
@DependencyClient
public struct KeychainClient: Sendable {
  public var read: @Sendable (_ account: String, _ synchronizable: Bool) throws -> Data?
  public var write: @Sendable (_ data: Data, _ account: String, _ synchronizable: Bool) throws -> Void
  public var delete: @Sendable (_ account: String, _ synchronizable: Bool) throws -> Void
}

// MARK: - KeychainError

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

// MARK: - KeychainClient + DependencyKey

extension KeychainClient: DependencyKey {
  // MARK: Public

  public static let service = "com.chenkai.wait"

  public static let liveValue = KeychainClient(
    read: { account, synchronizable in
      var query = baseQuery(account: account, synchronizable: synchronizable)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
      }
    },
    write: { data, account, synchronizable in
      let query = baseQuery(account: account, synchronizable: synchronizable)
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]
      var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
      }
      guard status == errSecSuccess else { throw KeychainError(status: status) }
    },
    delete: { account, synchronizable in
      let status = SecItemDelete(baseQuery(account: account, synchronizable: synchronizable) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
  )

  public static let testValue = KeychainClient()

  /// For tests and previews.
  public static func inMemory() -> KeychainClient {
    let store = LockIsolated<[String: Data]>([:])
    return KeychainClient(
      read: { account, synchronizable in store.value["\(synchronizable):\(account)"] },
      write: { data, account, synchronizable in store.withValue { $0["\(synchronizable):\(account)"] = data } },
      delete: { account, synchronizable in store.withValue { $0["\(synchronizable):\(account)"] = nil } }
    )
  }

  // MARK: Private

  private static func baseQuery(account: String, synchronizable: Bool) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
    ]
  }
}

extension DependencyValues {
  public var keychain: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}
