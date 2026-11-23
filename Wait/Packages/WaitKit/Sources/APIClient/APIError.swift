//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - APIError

/// Every failure from the Wait backend. `status == 0` means the request never got an HTTP response.
public struct APIError: Error, Equatable, Sendable {
  // MARK: Lifecycle

  public init(status: Int, code: String, message: String, retryAfter: Duration? = nil) {
    self.status = status
    self.code = code
    self.message = message
    self.retryAfter = retryAfter
  }

  /// Builds an error from a non-2xx body shaped `{ "error": { "code", "message" } }`.
  public init(status: Int, body: Data, retryAfterHeader: String?) {
    let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
    self.init(
      status: status,
      code: envelope?.error.code ?? "HTTP_\(status)",
      message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
      retryAfter: retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { .seconds($0) }
    )
  }

  // MARK: Public

  public static let misconfigured = APIError(status: 0, code: "MISCONFIGURED", message: "WaitAPIBaseURL is missing from Info.plist")

  public let status: Int
  public let code: String
  public let message: String
  public let retryAfter: Duration?

  public static func transport(_ message: String) -> APIError {
    APIError(status: 0, code: "NETWORK", message: message)
  }

  public static func decoding(status: Int, _ message: String) -> APIError {
    APIError(status: status, code: "DECODING", message: message)
  }

  // MARK: Private

  private struct Envelope: Decodable {
    struct Body: Decodable {
      let code: String
      let message: String
    }

    let error: Body
  }
}

// MARK: LocalizedError

extension APIError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
