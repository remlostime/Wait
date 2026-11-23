//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DeviceRegistrationDTO

/// Body of `POST /api/devices` (overview §8.4).
public struct DeviceRegistrationDTO: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(token: String, environment: Environment = .current, bundleId: String = "com.chenkai.wait") {
    self.token = token
    self.environment = environment
    self.bundleId = bundleId
  }

  // MARK: Public

  public enum Environment: String, Codable, Sendable {
    case sandbox
    case production

    /// Debug builds get sandbox APNs tokens; TestFlight and App Store builds get production tokens.
    public static var current: Environment {
      #if DEBUG
      return .sandbox
      #else
      return .production
      #endif
    }
  }

  public let token: String
  public let environment: Environment
  public let bundleId: String
}

// MARK: - APNsToken

public enum APNsToken {
  /// Lowercase hex, the format the server validates (`^[0-9a-f]{64,200}$`).
  public static func hexString(_ deviceToken: Data) -> String {
    deviceToken.map { String(format: "%02x", $0) }.joined()
  }
}
