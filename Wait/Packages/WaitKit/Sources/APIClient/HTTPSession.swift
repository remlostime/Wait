//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - APIRequest

public struct APIRequest: Sendable {
  // MARK: Lifecycle

  public init(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil, requiresAuth: Bool = true) {
    self.method = method
    self.path = path
    self.query = query
    self.body = body
    self.requiresAuth = requiresAuth
  }

  // MARK: Public

  public var method: String
  public var path: String
  public var query: [URLQueryItem]
  public var body: Data?
  public var requiresAuth: Bool
}

// MARK: - HTTPSession

/// The one connection to the Wait backend (overview §9). The JWT lives in memory only.
/// The first authenticated call registers with the anonymous ID. A 401 re-registers once and retries once.
/// Concurrent callers share a single in-flight registration.
public actor HTTPSession {
  // MARK: Lifecycle

  public init(baseURL: URL, session: URLSession = .shared, anonymousID: @escaping @Sendable () throws -> UUID) {
    self.baseURL = baseURL
    self.session = session
    self.anonymousID = anonymousID
  }

  // MARK: Public

  public func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
    try decode(try await send(APIRequest(method: "GET", path: path, query: query)))
  }

  public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response {
    try decode(try await send(APIRequest(method: "POST", path: path, body: try encode(body))))
  }

  /// For endpoints that answer 204.
  public func post<Body: Encodable & Sendable>(_ path: String, body: Body) async throws {
    _ = try await send(APIRequest(method: "POST", path: path, body: try encode(body)))
  }

  public func delete(_ path: String) async throws {
    _ = try await send(APIRequest(method: "DELETE", path: path))
  }

  /// Raw call with auth and the single 401 retry. Throws `APIError` for every non-2xx.
  public func send(_ request: APIRequest) async throws -> Data {
    var token = request.requiresAuth ? try await validToken() : nil
    var (data, response) = try await perform(request, token: token)
    if response.statusCode == 401, request.requiresAuth {
      token = try await validToken(replacing: token)
      (data, response) = try await perform(request, token: token)
    }
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    return data
  }

  // MARK: Private

  private let baseURL: URL
  private let session: URLSession
  private let anonymousID: @Sendable () throws -> UUID
  private var token: String?
  private var registration: Task<String, any Error>?

  /// Returns the cached token unless it is `stale` (the one that just got a 401). Concurrent 401s for the
  /// same stale token share one registration; a caller holding an older token gets the newer one directly.
  private func validToken(replacing stale: String? = nil) async throws -> String {
    if let token, token != stale {
      return token
    }
    if let registration {
      return try await registration.value
    }
    let task = Task { try await self.register() }
    registration = task
    defer { registration = nil }
    let fresh = try await task.value
    token = fresh
    return fresh
  }

  private func register() async throws -> String {
    let id: UUID
    do {
      id = try anonymousID()
    } catch {
      throw APIError(status: 0, code: "IDENTITY", message: "Could not read the anonymous ID: \(error)")
    }
    let body = try encode(RegisterRequestDTO(anonymousId: id.uuidString))
    let (data, response) = try await perform(APIRequest(method: "POST", path: "/api/auth/register", body: body, requiresAuth: false), token: nil)
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    let decoded: RegisterResponseDTO = try decode(data)
    return decoded.token
  }

  private func perform(_ request: APIRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
    guard var components = URLComponents(url: baseURL.appending(path: request.path), resolvingAgainstBaseURL: false) else {
      throw APIError.misconfigured
    }
    if !request.query.isEmpty {
      components.queryItems = request.query
      // URLComponents leaves `+` as is, and the server decodes a literal `+` in a query as a space.
      components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
    guard let url = components.url else { throw APIError.misconfigured }
    var urlRequest = URLRequest(url: url, timeoutInterval: 15)
    urlRequest.httpMethod = request.method
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body = request.body {
      urlRequest.httpBody = body
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw APIError.transport(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else { throw APIError.transport("Not an HTTP response") }
    return (data, http)
  }

  private func encode(_ value: some Encodable) throws -> Data {
    do {
      return try WireDates.makeEncoder().encode(value)
    } catch {
      throw APIError(status: 0, code: "ENCODING", message: String(describing: error))
    }
  }

  private func decode<Response: Decodable>(_ data: Data) throws -> Response {
    do {
      return try WireDates.makeDecoder().decode(Response.self, from: data)
    } catch {
      throw APIError.decoding(status: 200, String(describing: error))
    }
  }
}
