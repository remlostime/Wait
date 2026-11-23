//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Dependencies
import Foundation
import Testing

// MARK: - HTTPSessionTests

@Suite
struct HTTPSessionTests {
  private struct OK: Decodable, Equatable, Sendable { let ok: Bool }
  private struct Echo: Codable, Equatable, Sendable { let value: String }

  private let anonymousID = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!

  /// Serves tokens in `tokens` order on register; `accept` decides which bearer tokens /api/x accepts.
  private func makeSession(tokens: [String], accept: @escaping @Sendable (String?) -> Bool) -> (HTTPSession, URL, LockIsolated<Int>) {
    let registers = LockIsolated(0)
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register":
          let index = registers.withValue { count -> Int in
            count += 1
            return count - 1
          }
          return jsonReply(200, #"{"token":"\#(tokens[min(index, tokens.count - 1)])","user":{"id":"u1"}}"#)
        case "/api/x":
          let header = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
          return accept(header)
            ? jsonReply(200, #"{"ok":true}"#)
            : jsonReply(401, #"{"error":{"code":"UNAUTHORIZED","message":"Invalid or expired token"}}"#)
        case "/api/echo":
          return StubURLProtocol.Reply(status: 200, body: request.httpBody ?? Data())
        default:
          return jsonReply(404, #"{"error":{"code":"NOT_FOUND","message":"nope"}}"#)
      }
    }
    let id = anonymousID
    return (HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id }), base, registers)
  }

  @Test
  func registersOnFirstUseThenReusesTheToken() async throws {
    let (session, base, registers) = makeSession(tokens: ["t1"]) { $0 == "t1" }
    let first: OK = try await session.get("/api/x", query: [URLQueryItem(name: "symbols", value: "AAPL,MSFT")])
    let second: OK = try await session.get("/api/x")
    #expect(first == OK(ok: true) && second == OK(ok: true))
    #expect(registers.value == 1)
    let requests = StubURLProtocol.requests(for: base)
    let register = try #require(requests.first { $0.url?.path() == "/api/auth/register" })
    #expect(register.httpMethod == "POST")
    #expect(register.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"anonymousId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"}"#)
    #expect(requests.contains { $0.url?.query() == "symbols=AAPL,MSFT" })
  }

  @Test
  func reRegistersOnceOn401AndRetries() async throws {
    let (session, _, registers) = makeSession(tokens: ["stale", "fresh"]) { $0 == "fresh" }
    let result: OK = try await session.get("/api/x")
    #expect(result == OK(ok: true))
    #expect(registers.value == 2)
  }

  @Test
  func surfacesASecond401() async {
    let (session, _, registers) = makeSession(tokens: ["a", "b"]) { _ in false }
    await #expect(throws: APIError(status: 401, code: "UNAUTHORIZED", message: "Invalid or expired token")) {
      let _: OK = try await session.get("/api/x")
    }
    #expect(registers.value == 2)
  }

  @Test
  func postsEncodableBodiesAndDecodesResponses() async throws {
    let (session, _, _) = makeSession(tokens: ["t1"]) { _ in true }
    let echoed: Echo = try await session.post("/api/echo", body: Echo(value: "hello"))
    #expect(echoed == Echo(value: "hello"))
  }

  @Test
  func mapsErrorEnvelopesWithRetryAfter() async {
    let base = StubURLProtocol.stub { request in
      request.url?.path() == "/api/auth/register"
        ? jsonReply(200, #"{"token":"t","user":{"id":"u"}}"#)
        : jsonReply(503, #"{"error":{"code":"UPSTREAM_RATE_LIMITED","message":"Slow down"}}"#, headers: ["Retry-After": "30"])
    }
    let id = anonymousID
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })
    await #expect(throws: APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "Slow down", retryAfter: .seconds(30))) {
      let _: OK = try await session.get("/api/market/quotes")
    }
  }

  @Test
  func concurrentFirstCallsRegisterOnce() async throws {
    let (session, _, registers) = makeSession(tokens: ["t1"]) { $0 == "t1" }
    async let a: OK = session.get("/api/x")
    async let b: OK = session.get("/api/x")
    _ = try await (a, b)
    #expect(registers.value == 1)
  }
}
