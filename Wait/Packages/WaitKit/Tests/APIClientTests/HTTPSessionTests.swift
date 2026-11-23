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
  func registersAgainAfterTheSessionIsReset() async throws {
    let (session, _, registers) = makeSession(tokens: ["t1", "t2"]) { $0 == "t1" || $0 == "t2" }
    let _: OK = try await session.get("/api/x")
    #expect(registers.value == 1)
    await session.reset()
    let _: OK = try await session.get("/api/x")
    #expect(registers.value == 2)
  }

  @Test
  func aTokenIssuedForOneIDIsNotReusedAfterTheIdentityChanges() async throws {
    let current = LockIsolated(anonymousID)
    let newID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    let registeredIDs = LockIsolated<[String]>([])
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register":
          let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
          registeredIDs.withValue { $0.append(body) }
          return jsonReply(200, #"{"token":"t\#(registeredIDs.value.count)","user":{"id":"u1"}}"#)
        default:
          return jsonReply(200, #"{"ok":true}"#)
      }
    }
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { current.value })
    let _: OK = try await session.get("/api/x")
    let _: OK = try await session.get("/api/x")
    #expect(registeredIDs.value.count == 1)

    current.setValue(newID)
    let _: OK = try await session.get("/api/x")
    #expect(registeredIDs.value.count == 2)
    #expect(registeredIDs.value[1] == #"{"anonymousId":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"}"#)
    let bearer = StubURLProtocol.requests(for: base).last?.value(forHTTPHeaderField: "Authorization")
    #expect(bearer == "Bearer t2")

    // The new token is reused while the ID stays the same.
    let _: OK = try await session.get("/api/x")
    #expect(registeredIDs.value.count == 2)
  }

  @Test
  func aTokenForTheOldIDIsReplacedWhenTheIdentityFlipsDuringRegistration() async throws {
    let current = LockIsolated(anonymousID)
    let newID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    let registeredIDs = LockIsolated<[String]>([])
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register":
          let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
          registeredIDs.withValue { $0.append(body) }
          // The identity flips while the first registration is on the wire.
          current.setValue(newID)
          return jsonReply(200, #"{"token":"t\#(registeredIDs.value.count)","user":{"id":"u1"}}"#)
        default:
          let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
          return token == "Bearer t2" ? jsonReply(200, #"{"ok":true}"#) : jsonReply(401, #"{"error":{"code":"UNAUTHORIZED","message":"no"}}"#)
      }
    }
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { current.value })
    let result: OK = try await session.get("/api/x")
    #expect(result == OK(ok: true))
    #expect(registeredIDs.value.count == 2)
    #expect(registeredIDs.value[1].contains("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"))
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
  func rethrowsURLErrorCancelledAsCancellationError() async {
    let base = StubURLProtocol.stub { request in
      request.url?.path() == "/api/auth/register"
        ? jsonReply(200, #"{"token":"t","user":{"id":"u"}}"#)
        : StubURLProtocol.Reply(status: 0, body: Data(), failure: .cancelled)
    }
    let id = anonymousID
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })
    await #expect(throws: CancellationError.self) {
      let _: OK = try await session.get("/api/x")
    }
  }

  @Test
  func otherTransportFailuresStillBecomeNetworkErrors() async {
    let base = StubURLProtocol.stub { request in
      request.url?.path() == "/api/auth/register"
        ? jsonReply(200, #"{"token":"t","user":{"id":"u"}}"#)
        : StubURLProtocol.Reply(status: 0, body: Data(), failure: .notConnectedToInternet)
    }
    let id = anonymousID
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })
    let error = await #expect(throws: APIError.self) {
      let _: OK = try await session.get("/api/x")
    }
    #expect(error?.status == 0 && error?.code == "NETWORK")
  }

  @Test
  func decodingErrorsCarryTheRealStatus() async {
    let base = StubURLProtocol.stub { request in
      request.url?.path() == "/api/auth/register"
        ? jsonReply(200, #"{"token":"t","user":{"id":"u"}}"#)
        : jsonReply(201, #"{"unexpected":true}"#)
    }
    let id = anonymousID
    let session = HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })
    let error = await #expect(throws: APIError.self) {
      let _: OK = try await session.post("/api/x", body: Echo(value: "v"))
    }
    #expect(error?.status == 201 && error?.code == "DECODING")
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
