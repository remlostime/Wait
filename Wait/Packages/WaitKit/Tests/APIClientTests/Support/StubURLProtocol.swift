//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Foundation

// MARK: - StubURLProtocol

final class StubURLProtocol: URLProtocol {
  // MARK: Internal

  struct Reply: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]
  }

  typealias Handler = @Sendable (URLRequest) -> Reply

  /// Registers a handler under a fresh host and returns its base URL.
  static func stub(_ handler: @escaping Handler) -> URL {
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    handlers.withValue { $0[host] = handler }
    return URL(string: "https://\(host)")!
  }

  static func requests(for baseURL: URL) -> [URLRequest] {
    captured.value[baseURL.host() ?? ""] ?? []
  }

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var request = request
    if request.httpBody == nil, let stream = request.httpBodyStream {
      request.httpBody = Data(reading: stream)
    }
    let host = request.url?.host() ?? ""
    let recorded = request
    Self.captured.withValue { $0[host, default: []].append(recorded) }
    guard let url = request.url, let handler = Self.handlers.value[host] else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    let reply = handler(request)
    let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  // MARK: Private

  private static let handlers = LockIsolated<[String: Handler]>([:])
  private static let captured = LockIsolated<[String: [URLRequest]]>([:])
}

func jsonReply(_ status: Int = 200, _ json: String, headers: [String: String] = [:]) -> StubURLProtocol.Reply {
  StubURLProtocol.Reply(status: status, body: Data(json.utf8), headers: ["Content-Type": "application/json"].merging(headers) { $1 })
}

extension Data {
  init(reading stream: InputStream) {
    self.init()
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      append(buffer, count: read)
    }
  }
}
