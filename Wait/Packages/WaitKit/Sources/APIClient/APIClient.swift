//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation

// MARK: - APIClient

/// Typed endpoints of the Wait backend. Plans 05 and 06 add sync and device endpoints here.
@DependencyClient
public struct APIClient: Sendable {
  public var quotes: @Sendable (_ symbols: [String]) async throws -> QuotesResponseDTO
  public var history: @Sendable (_ symbol: String, _ range: ChartRange) async throws -> HistoryResponseDTO
  public var search: @Sendable (_ query: String) async throws -> SearchResponseDTO
  public var profile: @Sendable (_ symbol: String) async throws -> ProfileDTO
  public var deleteAccount: @Sendable () async throws -> Void
  /// `POST /api/watchlist/sync` (overview §8.4–§8.5).
  public var syncWatchlist: @Sendable (_ request: SyncRequestDTO) async throws -> SyncResponseDTO
}

extension APIClient {
  public static func live(session: HTTPSession) -> APIClient {
    APIClient(
      quotes: { symbols in
        try await session.get("/api/market/quotes", query: [URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))])
      },
      history: { symbol, range in
        try await session.get("/api/market/history", query: [URLQueryItem(name: "symbol", value: symbol), URLQueryItem(name: "range", value: range.rawValue)])
      },
      search: { query in
        try await session.get("/api/market/search", query: [URLQueryItem(name: "q", value: query)])
      },
      profile: { symbol in
        try await session.get("/api/market/profile", query: [URLQueryItem(name: "symbol", value: symbol)])
      },
      deleteAccount: {
        try await session.delete("/api/auth/account")
      },
      syncWatchlist: { request in
        try await session.post("/api/watchlist/sync", body: request)
      }
    )
  }

  /// `WaitAPIBaseURL` comes from `WAIT_API_BASE_URL` in `Config/*.xcconfig` (overview §8.2).
  public static func baseURL(infoValue: String?) -> URL? {
    guard
      let infoValue,
      let url = URL(string: infoValue),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = url.host(), !host.isEmpty
    else {
      return nil
    }
    return url
  }

  static let misconfigured = APIClient(
    quotes: { _ in throw APIError.misconfigured },
    history: { _, _ in throw APIError.misconfigured },
    search: { _ in throw APIError.misconfigured },
    profile: { _ in throw APIError.misconfigured },
    deleteAccount: { throw APIError.misconfigured },
    syncWatchlist: { _ in throw APIError.misconfigured }
  )
}

// MARK: - APIClient + DependencyKey

extension APIClient: DependencyKey {
  /// One shared session per process, so the in-memory JWT is reused by every caller.
  public static let liveValue: APIClient = {
    let info = Bundle.main.object(forInfoDictionaryKey: "WaitAPIBaseURL") as? String
    guard let baseURL = baseURL(infoValue: info) else {
      return .misconfigured
    }
    let identity = IdentityClient.liveValue
    return .live(session: HTTPSession(baseURL: baseURL, anonymousID: { try identity.anonymousID() }))
  }()

  public static let testValue = APIClient()
}

extension DependencyValues {
  public var apiClient: APIClient {
    get { self[APIClient.self] }
    set { self[APIClient.self] = newValue }
  }
}
