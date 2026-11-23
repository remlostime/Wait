//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dispatch
import Domain
import Foundation
import os
import Testing
@testable import Connectivity

// MARK: - ConnectivityEngineTests

@Suite
struct ConnectivityEngineTests {
  // MARK: Sending

  @Test
  func onlyTheLatestSnapshotSentBeforeActivationIsDelivered() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let newer = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(30))

    try engine.send(older)
    try engine.send(newer)
    #expect(fake.sentContexts.isEmpty)

    engine.activate()
    fake.completeActivation()

    #expect(fake.sentContexts.count == 1)
    let sent = try #require(fake.sentContexts.last)
    #expect(SnapshotCoding.decode(sent) == newer)
  }

  @Test
  func sendAfterActivationDeliversImmediately() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))

    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func nothingIsSentUntilTheCounterpartAppIsInstalled() throws {
    let fake = FakeSessionAdapter(.init(canSendToCounterpart: false))
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    #expect(fake.sentContexts.isEmpty)

    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func aFailedUpdateKeepsThePayloadForTheNextChance() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    fake.setUpdateError(.notReachable)

    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    #expect(fake.sentContexts.isEmpty)

    fake.setUpdateError(nil)
    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func aSlowSendCannotOvertakeANewerOne() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let newer = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(30))
    let gate = UpdateGate()
    fake.blockNextUpdate(gate)
    let firstDone = DispatchGroup()
    let secondDone = DispatchGroup()

    // The first send blocks inside `updateContext`.
    firstDone.enter()
    DispatchQueue.global().async {
      _ = try? engine.send(older)
      firstDone.leave()
    }
    gate.entered.wait()
    // A second send races it. Serialized flushes make it wait for the first one; unserialized, it finishes first.
    secondDone.enter()
    DispatchQueue.global().async {
      _ = try? engine.send(newer)
      secondDone.leave()
    }
    _ = secondDone.wait(timeout: .now() + .milliseconds(300))
    gate.release.signal()
    firstDone.wait()
    secondDone.wait()

    let sent = fake.sentContexts.map { SnapshotCoding.decode($0) }
    #expect(sent.last == newer)
    #expect(sent == [older, newer])
  }

  @Test
  func theLastSentSnapshotIsResentAfterTheWatchChanges() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)
    try engine.send(snapshot)
    #expect(fake.sentContexts.count == 1)

    fake.setCanSendToCounterpart(false)
    #expect(fake.sentContexts.count == 1)
    fake.setCanSendToCounterpart(true)

    #expect(fake.sentContexts.count == 2)
    #expect(SnapshotCoding.decode(try #require(fake.sentContexts.last)) == snapshot)
  }

  @Test
  func theLastSentSnapshotIsResentOnReactivation() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))

    fake.completeActivation()

    #expect(fake.sentContexts.count == 2)
    #expect(fake.sentContexts.first == fake.sentContexts.last)
  }

  @Test
  func aPendingSnapshotWinsOverTheResend() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let newer = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(30))
    try engine.send(older)
    fake.setCanSendToCounterpart(false)
    try engine.send(newer)

    fake.setCanSendToCounterpart(true)

    #expect(fake.sentContexts.map { SnapshotCoding.decode($0) } == [older, newer])
  }

  @Test
  func nothingIsResentWhenNothingWasEverSent() {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()

    fake.setCanSendToCounterpart(true)

    #expect(fake.sentContexts.isEmpty)
  }

  @Test
  func aFailedResendIsNotRecordedAsSent() throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    engine.activate()
    fake.completeActivation()
    try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    fake.setUpdateError(.notReachable)

    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 1)

    fake.setUpdateError(nil)
    fake.setCanSendToCounterpart(true)
    #expect(fake.sentContexts.count == 2)
  }

  @Test
  func sendThrowsWhenTheSnapshotCannotFit() throws {
    let engine = ConnectivityEngine(adapter: FakeSessionAdapter(), maxContextBytes: 10)

    #expect(throws: SnapshotCodingError.self) {
      try engine.send(try SnapshotFixtures.snapshot(rowCount: 1))
    }
  }

  // MARK: Activation

  @Test
  func activateIsIdempotent() {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)

    engine.activate()
    engine.activate()

    #expect(fake.activationCount == 1)
  }

  @Test
  func anUnsupportedSessionIsNeverActivated() {
    let fake = FakeSessionAdapter(.init(isSupported: false))
    let engine = ConnectivityEngine(adapter: fake)

    engine.activate()

    #expect(fake.activationCount == 0)
  }

  // MARK: Receiving

  @Test
  func theContextReceivedBeforeLaunchIsYieldedFirst() async throws {
    let initial = try SnapshotFixtures.snapshot(rowCount: 2)
    let fake = FakeSessionAdapter(.init(receivedContextData: try SnapshotCoding.encode(initial)))
    let engine = ConnectivityEngine(adapter: fake)
    var iterator = engine.snapshots().makeAsyncIterator()

    engine.activate()
    fake.completeActivation()

    let first = await iterator.next()
    #expect(first == initial)
  }

  @Test
  func aLateSubscriberGetsTheLatestSnapshotImmediately() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)
    engine.activate()
    fake.completeActivation()
    fake.receive(try SnapshotCoding.encode(snapshot))

    var iterator = engine.snapshots().makeAsyncIterator()

    let first = await iterator.next()
    #expect(first == snapshot)
  }

  @Test
  func olderAndDuplicateContextsAreIgnored() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let base = SnapshotFixtures.generatedAt
    let middle = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: base.addingTimeInterval(60))
    let oldest = try SnapshotFixtures.snapshot(rowCount: 1, generatedAt: base)
    let newest = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: base.addingTimeInterval(120))
    engine.activate()
    fake.completeActivation()
    var iterator = engine.snapshots().makeAsyncIterator()

    fake.receive(try SnapshotCoding.encode(middle))
    let first = await iterator.next()
    fake.receive(try SnapshotCoding.encode(middle))
    fake.receive(try SnapshotCoding.encode(oldest))
    fake.receive(try SnapshotCoding.encode(newest))
    let second = await iterator.next()

    #expect(first == middle)
    #expect(second == newest)
  }

  @Test
  func garbageContextsAreDropped() async throws {
    let fake = FakeSessionAdapter()
    let engine = ConnectivityEngine(adapter: fake)
    let snapshot = try SnapshotFixtures.snapshot(rowCount: 1)
    engine.activate()
    fake.completeActivation()
    var iterator = engine.snapshots().makeAsyncIterator()

    fake.receive(Data("garbage".utf8))
    fake.receive(try SnapshotCoding.encode(snapshot))

    let first = await iterator.next()
    #expect(first == snapshot)
  }

  @Test
  func subscribingWhileASnapshotArrivesNeverEndsOnTheOlderOne() async throws {
    // Not deterministic by construction (there is no hook between registering and yielding), so it repeats
    // the race. It can never fail on correct code; on the old code it fails when the interleaving hits.
    let base = SnapshotFixtures.generatedAt
    let older = try SnapshotFixtures.snapshot(rowCount: 1, generatedAt: base)
    let newer = try SnapshotFixtures.snapshot(rowCount: 2, generatedAt: base.addingTimeInterval(60))
    let olderData = try SnapshotCoding.encode(older)
    let newerData = try SnapshotCoding.encode(newer)

    for _ in 0 ..< 500 {
      let fake = FakeSessionAdapter()
      let engine = ConnectivityEngine(adapter: fake)
      engine.activate()
      fake.completeActivation()
      fake.receive(olderData)
      let box = OSAllocatedUnfairLock<AsyncStream<WatchlistSnapshot>?>(initialState: nil)

      DispatchQueue.concurrentPerform(iterations: 2) { index in
        if index == 0 {
          box.withLock { $0 = engine.snapshots() }
        } else {
          fake.receive(newerData)
        }
      }

      var iterator = try #require(box.withLock { $0 }).makeAsyncIterator()
      let observed = await iterator.next()
      #expect(observed == newer)
    }
  }
}
