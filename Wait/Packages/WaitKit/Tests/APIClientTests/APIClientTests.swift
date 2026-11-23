//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Domain
import Foundation
import Testing

// MARK: - APIClientTests

@Suite
struct APIClientTests {
  private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// A live APIClient over a stub server that answers register plus one `path` with `json`.
  private func client(path: String, status: Int = 200, json: String) -> (APIClient, URL) {
    let base = StubURLProtocol.stub { request in
      switch request.url?.path() {
        case "/api/auth/register": return jsonReply(200, #"{"token":"t1","user":{"id":"u1"}}"#)
        case path: return jsonReply(status, json)
        default: return jsonReply(404, #"{"error":{"code":"NOT_FOUND","message":"unexpected \#(request.url?.path() ?? "")"}}"#)
      }
    }
    let id = UUID()
    return (.live(session: HTTPSession(baseURL: base, session: StubURLProtocol.makeSession(), anonymousID: { id })), base)
  }

  private func lastRequest(_ base: URL) -> URLRequest? {
    StubURLProtocol.requests(for: base).last
  }

  @Test
  func quotesJoinsSymbolsAndDecodesTheWireShape() async throws {
    let (api, base) = client(path: "/api/market/quotes", json: try fixture("quotes"))
    let response = try await api.quotes(["AAPL", "ZZZZ"])
    #expect(lastRequest(base)?.url?.query() == "symbols=AAPL,ZZZZ")
    #expect(response.missing == ["ZZZZ"])
    let quote = try #require(response.quotes.first)
    #expect(quote.price == "172.1" && quote.changePercent == 1.2353 && quote.volume == nil && quote.stale == false)
    #expect(quote.asOf == WireDates.date(from: "2026-11-20T15:00:00.000Z"))
  }

  @Test
  func historySendsTheRangeRawValue() async throws {
    let (api, base) = client(path: "/api/market/history", json: try fixture("history-1d"))
    let response = try await api.history("AAPL", .oneDay)
    #expect(lastRequest(base)?.url?.query() == "symbol=AAPL&range=1D")
    #expect(response.points.map(\.c) == ["171.2", "171.6"])
    #expect(response.delayedMinutes == 15)
  }

  @Test
  func searchPercentEncodesPlusSoTheServerDoesNotReadItAsASpace() async throws {
    let (api, base) = client(path: "/api/market/search", json: try fixture("search"))
    _ = try await api.search("a+b c")
    #expect(lastRequest(base)?.url?.query() == "q=a%2Bb%20c")
  }

  @Test
  func searchAndProfileDecode() async throws {
    let (searchAPI, _) = client(path: "/api/market/search", json: try fixture("search"))
    #expect(try await searchAPI.search("app").results.map(\.symbol) == ["AAPL"])
    let (profileAPI, _) = client(path: "/api/market/profile", json: try fixture("profile"))
    let profile = try await profileAPI.profile("AAPL")
    #expect(profile.marketCap == "2650000500000" && profile.peRatio == 28.4 && profile.fiftyTwoWeekLow == "164.08")
  }

  @Test
  func deleteAccountSendsDELETEAndAccepts204() async throws {
    let (api, base) = client(path: "/api/auth/account", status: 204, json: "")
    try await api.deleteAccount()
    #expect(lastRequest(base)?.httpMethod == "DELETE")
  }

  @Test
  func baseURLComesFromInfoPlistAndRejectsEmptyValues() {
    #expect(APIClient.baseURL(infoValue: "https://wait-api.vercel.app") == URL(string: "https://wait-api.vercel.app"))
    #expect(APIClient.baseURL(infoValue: "") == nil)
    #expect(APIClient.baseURL(infoValue: nil) == nil)
  }
}
