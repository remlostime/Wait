//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import StockDetailsFeature
import Testing

// swiftlint:disable force_try

let detailsNow = Date(timeIntervalSince1970: 1_795_186_800)

func detailsItem() -> WatchlistItem {
  WatchlistItem(symbol: "AAPL", name: "Apple", ladder: try! PriceLadder(buyHigh: 150), memo: "Keep me", createdAt: .distantPast, updatedAt: .distantPast)
}

@MainActor
@Suite struct StockDetailsFeatureTests {
  func makeStore(quotes: (@Sendable ([String], CachePolicy) async throws -> [Quote])? = nil) -> TestStoreOf<StockDetailsFeature> {
    TestStore(initialState: StockDetailsFeature.State(item: Shared(value: detailsItem()))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.date.now = detailsNow
      if let quotes {
        $0.marketData.quotes = quotes
      }
    }
  }

  @Test func savingALadderKeepsTheMemo() async throws {
    let store = makeStore()
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    let newLadder = try PriceLadder(buyHigh: 140, fair: 200)
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(newLadder)))))) {
      $0.$item.withLock {
        $0.ladder = newLadder
        $0.ladderHistory = [LadderRevision(date: detailsNow, ladder: newLadder)]
        $0.updatedAt = detailsNow
      }
    }
    #expect(store.state.item.memo == "Keep me")
  }

  @Test func savingAnUnchangedLadderDoesNothing() async throws {
    let store = makeStore()
    // Present first: `ifLet` reports an issue for a presented action when the destination is nil.
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(try PriceLadder(buyHigh: 150)))))))
  }

  @Test func editingInThePresentedEditorSavesDismissesAndKeepsTheMemo() async throws {
    let store = makeStore()
    await store.send(.editLadderTapped) {
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "AAPL", ladder: try! PriceLadder(buyHigh: 150), currentPrice: nil))
    }
    await store.send(.destination(.presented(.ladderEditor(.binding(.set(\.buyHigh, "140")))))) {
      $0.destination?.modify(\.ladderEditor) { $0.buyHigh = "140" }
    }
    await store.send(.destination(.presented(.ladderEditor(.saveTapped))))
    let ladder = try PriceLadder(buyHigh: 140)
    await store.receive(\.destination.presented.ladderEditor.delegate.saved, ladder) {
      $0.$item.withLock {
        $0.ladder = ladder
        $0.ladderHistory = [LadderRevision(date: detailsNow, ladder: ladder)]
        $0.updatedAt = detailsNow
      }
    }
    await store.receive(\.destination.dismiss) { $0.destination = nil }
    #expect(store.state.item.memo == "Keep me")
  }

  @Test func failedRefreshKeepsTheCachedQuote() async {
    let cached = Quote(symbol: "AAPL", price: 140, asOf: detailsNow, isStale: true)
    let store = makeStore { _, policy in
      if policy == .cacheOnly {
        return [cached]
      }
      throw MarketDataError.network("offline")
    }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = cached }
    await store.receive(\.quoteFailed)
    #expect(store.state.quote == cached)
  }

  @Test func starTogglesFavoriteAndNeverRemoves() async {
    let store = makeStore()
    await store.send(.favoriteTapped) {
      $0.$item.withLock {
        $0.isFavorite = true
        $0.updatedAt = detailsNow
      }
    }
    await store.send(.favoriteTapped) {
      $0.$item.withLock { $0.isFavorite = false }
    }
  }

  @Test func notesSaveOnlyTouchesTheMemo() async throws {
    let store = makeStore()
    await store.send(.editNotesTapped) {
      $0.destination = .notesEditor(NotesEditorFeature.State(text: "Keep me"))
    }
    await store.send(.destination(.presented(.notesEditor(.delegate(.saved("New\nnote")))))) {
      $0.$item.withLock {
        $0.memo = "New\nnote"
        $0.updatedAt = detailsNow
      }
    }
    #expect(store.state.item.ladder == (try PriceLadder(buyHigh: 150)))
  }

  @Test func deleteAsksForConfirmationThenDelegates() async {
    let store = makeStore()
    await store.send(.deleteTapped) {
      $0.alert = .confirmDelete(symbol: "AAPL")
    }
    await store.send(.alert(.presented(.confirmDelete))) {
      $0.alert = nil
    }
    await store.receive(\.delegate.deleteConfirmed, "AAPL")
  }

  @Test func checklistTapDelegates() async {
    let store = makeStore()
    await store.send(.checklistTapped)
    await store.receive(\.delegate.openChecklist, "AAPL")
  }

  @Test func taskLoadsTheQuoteAndDerivesTheStatus() async {
    let quote = Quote(symbol: "AAPL", price: 140, asOf: detailsNow)
    let store = makeStore { _, policy in
      if policy == .cacheOnly {
        throw MarketDataError.notCached
      }
      return [quote]
    }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = quote }
    #expect(store.state.status == .buyZone)
    #expect(store.state.temperature != nil)
  }

  @Test func historyTapShowsTheSheet() async {
    let store = makeStore()
    await store.send(.historyTapped) { $0.isShowingLadderHistory = true }
    await store.send(\.binding.isShowingLadderHistory, false) { $0.isShowingLadderHistory = false }
  }
}
