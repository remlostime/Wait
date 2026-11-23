//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import NotificationClient
import Testing
#if os(iOS)
import UserNotifications
#endif

// MARK: - NotificationPayloadTests

@Suite
struct NotificationPayloadTests {
  @Test
  func readsTheSymbolKey() {
    #expect(NotificationPayload.symbol(from: ["symbol": "AAPL"]) == "AAPL")
  }

  @Test
  func uppercasesTheSymbol() {
    #expect(NotificationPayload.symbol(from: ["symbol": "brk.b"]) == "BRK.B")
  }

  @Test
  func acceptsEverySymbolTheAppCanOpen() {
    #expect(NotificationPayload.symbol(from: ["symbol": "0700.HK"]) == "0700.HK")
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://stock/600887.SS"]) == "600887.SS")
  }

  @Test
  func fallsBackToTheDeepLink() {
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://stock/MSFT"]) == "MSFT")
  }

  @Test
  func prefersTheSymbolKeyOverTheDeepLink() {
    #expect(NotificationPayload.symbol(from: ["symbol": "AAPL", "deepLink": "wait://stock/MSFT"]) == "AAPL")
  }

  @Test
  func rejectsForeignDeepLinks() {
    #expect(NotificationPayload.symbol(from: ["deepLink": "https://example.com/stock/MSFT"]) == nil)
    #expect(NotificationPayload.symbol(from: ["deepLink": "wait://settings/MSFT"]) == nil)
  }

  @Test
  func rejectsInvalidSymbols() {
    #expect(NotificationPayload.symbol(from: ["symbol": "NOT A SYMBOL"]) == nil)
    #expect(NotificationPayload.symbol(from: ["symbol": 42]) == nil)
    #expect(NotificationPayload.symbol(from: [:]) == nil)
  }

  #if os(iOS)
  @Test
  func mapsSystemAuthorizationStatuses() {
    #expect(NotificationAuthorization(UNAuthorizationStatus.notDetermined) == .notDetermined)
    #expect(NotificationAuthorization(UNAuthorizationStatus.denied) == .denied)
    #expect(NotificationAuthorization(UNAuthorizationStatus.authorized) == .authorized)
    #expect(NotificationAuthorization(UNAuthorizationStatus.provisional) == .provisional)
    #expect(NotificationAuthorization(UNAuthorizationStatus.ephemeral) == .ephemeral)
  }
  #endif
}
