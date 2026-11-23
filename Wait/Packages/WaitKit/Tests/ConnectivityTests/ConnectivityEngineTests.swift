//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
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
}
