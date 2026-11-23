//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import StockDetailsFeature
import Testing

let us = Locale(identifier: "en_US")

func dec(_ string: String) -> Decimal {
  Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@MainActor
@Suite struct EditorFeatureTests {
  @Test func invalidNumberBlocksSaving() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "abc"
    #expect(state.parsed == .failure(.invalidNumber(.buyHigh)))
    #expect(!state.canSave)
  }

  @Test func outOfOrderAnchors() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyLow = "120"
    state.buyHigh = "100"
    #expect(state.parsed == .failure(.ladder(.outOfOrder(lower: .buyLow, upper: .buyHigh))))
  }

  @Test func allFieldsEmptyClearsTheTargets() throws {
    // Product decision: an empty ladder is allowed and saves as "no targets" (status NO_ANCHORS).
    let state = LadderEditorFeature.State(symbol: "AAPL", ladder: try PriceLadder(buyHigh: 10), currentPrice: nil, locale: us)
    var cleared = state
    cleared.buyHigh = ""
    #expect(cleared.parsed == .success(.empty))
    #expect(cleared.canSave)
  }

  @Test func derivedFairHint() {
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "175"
    #expect(state.derivedFairHint == 250)
    state.trim = "300"
    #expect(state.derivedFairHint == nil)
  }

  @Test func prefillsFromAnExistingLadder() throws {
    let state = LadderEditorFeature.State(symbol: "AAPL", ladder: try PriceLadder(buyLow: 12, buyHigh: dec("16.5")), currentPrice: nil, locale: us)
    #expect(state.buyLow == "12")
    #expect(state.buyHigh == "16.5")
    #expect(state.fair.isEmpty)
  }

  @Test func saveEmitsTheLadderAndDismisses() async throws {
    let dismissed = LockIsolated(false)
    var state = LadderEditorFeature.State(symbol: "AAPL", ladder: .empty, currentPrice: nil, locale: us)
    state.buyHigh = "175"
    let store = TestStore(initialState: state) {
      LadderEditorFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect { dismissed.setValue(true) }
    }
    await store.send(\.binding.buyLow, "150") { $0.buyLow = "150" }
    await store.send(.saveTapped)
    await store.receive(\.delegate.saved, try PriceLadder(buyLow: 150, buyHigh: 175))
    await store.finish()
    #expect(dismissed.value)
  }

  @Test func notesSaveEmitsTextAndDismisses() async {
    let dismissed = LockIsolated(false)
    let store = TestStore(initialState: NotesEditorFeature.State(text: "old")) {
      NotesEditorFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect { dismissed.setValue(true) }
    }
    await store.send(\.binding.text, "line 1\nline 2") { $0.text = "line 1\nline 2" }
    await store.send(.saveTapped)
    await store.receive(\.delegate.saved, "line 1\nline 2")
    await store.finish()
    #expect(dismissed.value)
  }
}
