//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Testing
@testable import APIClient

// MARK: - APIErrorTests

@Suite
struct APIErrorTests {
  @Test
  func decodesTheServerErrorEnvelopeAndRetryAfter() {
    let body = Data(#"{"error":{"code":"UPSTREAM_RATE_LIMITED","message":"Slow down"}}"#.utf8)
    let error = APIError(status: 503, body: body, retryAfterHeader: "30")
    #expect(error == APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "Slow down", retryAfter: .seconds(30)))
    #expect(error.localizedDescription == "Slow down")
  }

  @Test
  func fallsBackToTheHTTPStatusWhenTheBodyIsNotAnEnvelope() {
    let error = APIError(status: 502, body: Data("<html>".utf8), retryAfterHeader: nil)
    #expect(error.code == "HTTP_502")
    #expect(error.retryAfter == nil)
  }

  @Test
  func flagsOnlyClientSideConfigurationFailures() {
    #expect(APIError.misconfigured.isConfigurationFailure)
    #expect(APIError(status: 0, code: APIError.identityCode, message: "").isConfigurationFailure)
    #expect(!APIError.transport("offline").isConfigurationFailure)
    #expect(!APIError(status: 500, code: APIError.misconfiguredCode, message: "").isConfigurationFailure)
  }
}
