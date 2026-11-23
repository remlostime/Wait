//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Dependencies
import Foundation
import Testing

// MARK: - DeviceStubProtocol

final class DeviceStubProtocol: URLProtocol, @unchecked Sendable {
  // MARK: Internal

  static let requests = LockIsolated<[(request: URLRequest, body: Data)]>([])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body = request.httpBodyStream.map(Self.readAll) ?? request.httpBody ?? Data()
    Self.requests.withValue { $0.append((request, body)) }
    let path = request.url?.path() ?? ""
    let (status, payload): (Int, Data) =
      if path == "/api/auth/register" {
        (200, Data(#"{"token":"jwt-1","user":{"id":"user-1"}}"#.utf8))
      } else if path.hasPrefix("/api/devices") {
        (204, Data())
      } else {
        (404, Data(#"{"error":{"code":"NOT_FOUND","message":"Route not found"}}"#.utf8))
      }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: payload)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  // MARK: Private

  private static func readAll(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

// MARK: - DeviceEndpointTests

@Suite(.serialized)
struct DeviceEndpointTests {
  // MARK: Internal

  @Test
  func hexEncodesTheDeviceToken() {
    #expect(APNsToken.hexString(Data([0x00, 0x0F, 0xDE, 0xAD])) == "000fdead")
  }

  @Test
  func usesTheSandboxInDebugBuilds() {
    #expect(DeviceRegistrationDTO.Environment.current == .sandbox)
  }

  @Test
  func encodesTheWireShape() throws {
    let dto = DeviceRegistrationDTO(token: "ab12", environment: .production)
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: String])
    #expect(json == ["token": "ab12", "environment": "production", "bundleId": "com.chenkai.wait"])
  }

  @Test
  func registerDevicePostsTheRegistration() async throws {
    DeviceStubProtocol.requests.setValue([])
    try await makeClient().registerDevice(DeviceRegistrationDTO(token: "ab12", environment: .sandbox))

    let (request, body) = try #require(DeviceStubProtocol.requests.value.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path() == "/api/devices")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-1")
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json == ["token": "ab12", "environment": "sandbox", "bundleId": "com.chenkai.wait"])
  }

  @Test
  func unregisterDeviceSendsADelete() async throws {
    DeviceStubProtocol.requests.setValue([])
    try await makeClient().unregisterDevice("ab12")

    let (request, _) = try #require(DeviceStubProtocol.requests.value.last)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path() == "/api/devices/ab12")
  }

  // MARK: Private

  private func makeClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeviceStubProtocol.self]
    let session = HTTPSession(
      baseURL: URL(string: "https://wait.test")!,
      session: URLSession(configuration: configuration),
      anonymousID: { UUID(uuidString: "00000000-0000-4000-8000-000000000001")! }
    )
    return APIClient.live(session: session)
  }
}
