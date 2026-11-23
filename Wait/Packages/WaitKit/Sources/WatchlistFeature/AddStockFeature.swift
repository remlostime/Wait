//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature

// MARK: - AddStockFeature

/// Search is debounced 300 ms with the injected clock (the legacy code used `asyncAfter` for 1 s). Tapping a result opens the ladder editor, and saving emits `.delegate(.added)`.
/// Uses the effect-returning `onChange(of:)`; the reducer-builder overload is deprecated in TCA 1.26.
@Reducer
public struct AddStockFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Destination {
    case ladderEditor(LadderEditorFeature)
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var query = ""
    public var results: [SymbolSearchResult] = []
    public var isSearching = false
    public var errorMessage: String?
    public var pending: SymbolSearchResult?
    @Presents public var destination: Destination.State?

    // MARK: Internal

    @SharedReader(.watchlist) var existing
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case searchLoaded(query: String, [SymbolSearchResult])
    case searchFailed(MarketDataError)
    case resultTapped(SymbolSearchResult)
    case cancelTapped
    case destination(PresentationAction<Destination.Action>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case added(WatchlistItem)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
      .onChange(of: \.query) { _, state in
        let trimmed = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.errorMessage = nil
        guard !trimmed.isEmpty else {
          state.results = []
          state.isSearching = false
          return .cancel(id: CancelID.search)
        }
        state.isSearching = true
        return .run { [clock, marketData] send in
          try await clock.sleep(for: .milliseconds(300))
          do {
            try await send(.searchLoaded(query: trimmed, marketData.search(trimmed)))
          } catch is CancellationError {
            return
          } catch {
            try await send(.searchFailed(MarketDataError(error))) // rethrows cancellation
          }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
      }
    Reduce { state, action in
      switch action {
        case let .searchLoaded(query, results):
          guard query == state.query.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .none
          }
          state.isSearching = false
          state.results = results
          return .none

        case let .searchFailed(error):
          state.isSearching = false
          state.errorMessage = error.userMessage
          return .none

        case let .resultTapped(result):
          let symbol = result.symbol.uppercased()
          guard state.existing[id: symbol] == nil else {
            state.errorMessage = "\(symbol) is already on your watchlist."
            return .none
          }
          state.errorMessage = nil
          state.pending = result
          state.destination = .ladderEditor(LadderEditorFeature.State(symbol: symbol, ladder: .empty, currentPrice: nil))
          return .none

        case .cancelTapped:
          return .run { [dismiss] _ in await dismiss() }

        case let .destination(.presented(.ladderEditor(.delegate(.saved(ladder))))):
          guard let result = state.pending else {
            return .none
          }
          @SharedReader(.checklistTemplate) var template
          let stamp = now.truncatedToMilliseconds
          let item = WatchlistItem(
            symbol: result.symbol.uppercased(),
            name: result.name,
            ladder: ladder,
            checklist: template.map { ChecklistItem(id: uuid(), name: $0.name) },
            ladderHistory: ladder.isEmpty ? [] : [LadderRevision(date: stamp, ladder: ladder)],
            createdAt: stamp,
            updatedAt: stamp
          )
          return .send(.delegate(.added(item)))

        case .binding, .destination, .delegate:
          return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
  }

  // MARK: Private

  private enum CancelID {
    case search
  }

  @Dependency(\.continuousClock) private var clock
  @Dependency(\.date.now) private var now
  @Dependency(\.dismiss) private var dismiss
  @Dependency(\.marketData) private var marketData
  @Dependency(\.uuid) private var uuid
}

// MARK: - AddStockFeature.Destination.State + Equatable

extension AddStockFeature.Destination.State: Equatable {}
