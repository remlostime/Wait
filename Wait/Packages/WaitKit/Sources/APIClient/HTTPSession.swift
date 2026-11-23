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
/// A token (and an in-flight registration) is bound to the anonymous ID it was issued for. When the identity returns another ID,
/// for instance after the account was deleted and the ID reset, the old token is never sent again and a fresh registration starts.
public actor HTTPSession {
  // MARK: Lifecycle

  public init(baseURL: URL, session: URLSession = .shared, anonymousID: @escaping @Sendable () throws -> UUID) {
    self.baseURL = baseURL
    self.session = session
    self.anonymousID = anonymousID
  }

  // MARK: Public

  public func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
    let (data, status) = try await sendWithStatus(APIRequest(method: "GET", path: path, query: query))
    return try decode(data, status: status)
  }

  public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response {
    let (data, status) = try await sendWithStatus(APIRequest(method: "POST", path: path, body: try encode(body)))
    return try decode(data, status: status)
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
    try await sendWithStatus(request).data
  }

  /// Drops the cached JWT and ignores any in-flight registration (its result is never published), so the next authenticated
  /// call registers again with whatever the anonymous ID is by then. Called after the identity was reset.
  public func reset() {
    credential = nil
    registration = nil
  }

  // MARK: Private

  /// A JWT and the anonymous ID it was issued for.
  private struct Credential {
    let token: String
    let anonymousID: UUID
  }

  /// A registration in flight. `serial` tells a newer registration or a `reset()` apart from this one.
  private struct Registration {
    let serial: Int
    let anonymousID: UUID
    let task: Task<String, any Error>
  }

  /// Enough for a reset or identity change to land while a registration is awaited, never an endless loop.
  private static let maxRegistrationAttempts = 3

  private let baseURL: URL
  private let session: URLSession
  private let anonymousID: @Sendable () throws -> UUID
  private var credential: Credential?
  private var registration: Registration?
  private var registrationCount = 0

  private func sendWithStatus(_ request: APIRequest) async throws -> (data: Data, status: Int) {
    var token = request.requiresAuth ? try await validToken() : nil
    var (data, response) = try await perform(request, token: token)
    if response.statusCode == 401, request.requiresAuth {
      token = try await validToken(replacing: token)
      (data, response) = try await perform(request, token: token)
    }
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    return (data, response.statusCode)
  }

  /// Returns the cached token unless it is `stale` (the one that just got a 401) or was issued for another anonymous ID.
  /// Concurrent 401s for the same stale token share one registration; a caller holding an older token gets the newer one directly.
  private func validToken(replacing stale: String? = nil) async throws -> String {
    for _ in 0 ..< Self.maxRegistrationAttempts {
      let id = try currentAnonymousID()
      if let credential, credential.anonymousID != id {
        self.credential = nil
      }
      if let credential, credential.token != stale {
        return credential.token
      }
      let token = try await pendingRegistration(for: id).task.value
      // A `reset()` or an identity change while we waited discards that registration: ask again with the current ID.
      if let credential, credential.token == token, credential.anonymousID == id {
        return token
      }
    }
    throw CancellationError()
  }

  /// The registration in flight for `id`, or a new one. A registration for another ID is ignored: its result is never published.
  private func pendingRegistration(for id: UUID) -> Registration {
    if let registration, registration.anonymousID == id {
      return registration
    }
    registrationCount += 1
    let serial = registrationCount
    // The task runs on this actor, so it publishes the credential (and clears `registration`) itself. Every waiter,
    // including a caller that was cancelled while waiting, then sees the token without depending on the first caller.
    let task = Task { [self] in
      defer { finishRegistration(serial: serial) }
      let fresh = try await register(anonymousID: id)
      if registration?.serial == serial {
        credential = Credential(token: fresh, anonymousID: id)
      }
      return fresh
    }
    let pending = Registration(serial: serial, anonymousID: id, task: task)
    registration = pending
    return pending
  }

  private func finishRegistration(serial: Int) {
    if registration?.serial == serial {
      registration = nil
    }
  }

  private func currentAnonymousID() throws -> UUID {
    do {
      return try anonymousID()
    } catch {
      throw APIError(status: 0, code: APIError.identityCode, message: "Could not read the anonymous ID: \(error)")
    }
  }

  private func register(anonymousID id: UUID) async throws -> String {
    let body = try encode(RegisterRequestDTO(anonymousId: id.uuidString))
    let (data, response) = try await perform(APIRequest(method: "POST", path: "/api/auth/register", body: body, requiresAuth: false), token: nil)
    guard (200 ..< 300).contains(response.statusCode) else {
      throw APIError(status: response.statusCode, body: data, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"))
    }
    let decoded: RegisterResponseDTO = try decode(data, status: response.statusCode)
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
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch is CancellationError {
      throw CancellationError()
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

  private func decode<Response: Decodable>(_ data: Data, status: Int) throws -> Response {
    do {
      return try WireDates.makeDecoder().decode(Response.self, from: data)
    } catch {
      throw APIError.decoding(status: status, String(describing: error))
    }
  }
}
