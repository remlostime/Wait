//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import NotificationClient
import Testing

// MARK: - TapBroadcasterTests

@Suite
struct TapBroadcasterTests {
  @Test
  func everySubscriberReceivesEachTap() async {
    let broadcaster = TapBroadcaster()
    var first = broadcaster.stream().makeAsyncIterator()
    var second = broadcaster.stream().makeAsyncIterator()

    broadcaster.send("AAPL")

    #expect(await first.next() == "AAPL")
    #expect(await second.next() == "AAPL")
  }

  @Test
  func tapsBeforeTheFirstSubscriberAreKeptForIt() async {
    let broadcaster = TapBroadcaster()
    broadcaster.send("AAPL")
    broadcaster.send("MSFT")

    var iterator = broadcaster.stream().makeAsyncIterator()

    #expect(await iterator.next() == "AAPL")
    #expect(await iterator.next() == "MSFT")
  }

  @Test
  func theBacklogKeepsTheNewestEight() async {
    let broadcaster = TapBroadcaster()
    for index in 1...10 {
      broadcaster.send("S\(index)")
    }

    var iterator = broadcaster.stream().makeAsyncIterator()

    #expect(await iterator.next() == "S3")
  }

  @Test
  func theBacklogGoesToOneSubscriberOnly() async {
    let broadcaster = TapBroadcaster()
    broadcaster.send("AAPL")
    var first = broadcaster.stream().makeAsyncIterator()
    var second = broadcaster.stream().makeAsyncIterator()

    broadcaster.send("MSFT")

    #expect(await first.next() == "AAPL")
    #expect(await first.next() == "MSFT")
    #expect(await second.next() == "MSFT")
  }

  @Test
  func aNewSubscriberDoesNotEndTheEarlierStream() async {
    let broadcaster = TapBroadcaster()
    var first = broadcaster.stream().makeAsyncIterator()
    _ = broadcaster.stream()

    broadcaster.send("AAPL")

    #expect(await first.next() == "AAPL")
  }

  @Test
  func aTapBetweenTwoSubscribersWaitsForTheNextOne() async {
    let broadcaster = TapBroadcaster()
    let task = Task { await broadcaster.stream().first { _ in false } }
    task.cancel()
    _ = await task.value
    // The cancelled consumer is gone, so this tap has no subscriber and waits for the next one.
    broadcaster.send("AAPL")

    var iterator = broadcaster.stream().makeAsyncIterator()

    #expect(await iterator.next() == "AAPL")
  }
}
