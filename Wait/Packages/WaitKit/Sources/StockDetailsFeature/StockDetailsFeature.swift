//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockChartFeature

// MARK: - StockDetailsFeature

@Reducer
public struct StockDetailsFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Destination {
    case ladderEditor(LadderEditorFeature)
    case notesEditor(NotesEditorFeature)
  }

  @ObservableState
  public struct State: Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: Shared<WatchlistItem>, quote: Quote? = nil) {
      _item = item
      self.quote = quote
      chart = StockChartFeature.State(symbol: item.wrappedValue.symbol)
    }

    // MARK: Public

    @Shared public var item: WatchlistItem
    public var quote: Quote?
    public var chart: StockChartFeature.State
    public var isShowingLadderHistory = false
    @Presents public var destination: Destination.State?
    @Presents public var alert: AlertState<Action.Alert>?

    public var id: String {
      item.symbol
    }

    public var status: LadderStatus? {
      quote.map { item.ladder.status(at: $0.price) }
    }

    public var temperature: Temperature? {
      quote.flatMap { item.ladder.temperature(at: $0.price) }
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case quoteLoaded(Quote)
    case quoteFailed(MarketDataError)
    case chart(StockChartFeature.Action)
    case editLadderTapped
    case editNotesTapped
    case historyTapped
    case checklistTapped
    case favoriteTapped
    case deleteTapped
    case destination(PresentationAction<Destination.Action>)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)

    public enum Alert: Equatable, Sendable {
      case confirmDelete
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case openChecklist(symbol: String)
      case deleteConfirmed(symbol: String)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Scope(\.chart, action: \.chart) {
      StockChartFeature()
    }
    Reduce { state, action in
      switch action {
        case .task:
          let symbol = state.item.symbol
          return .run { [marketData] send in
            if let cached = try? await marketData.quotes([symbol], .cacheOnly).first {
              await send(.quoteLoaded(cached))
            }
            do {
              if let fresh = try await marketData.quotes([symbol], .useCache).first {
                await send(.quoteLoaded(fresh))
              }
            } catch {
              try await send(.quoteFailed(MarketDataError(error))) // rethrows cancellation
            }
          }

        case let .quoteLoaded(quote):
          state.quote = quote
          return .none

        case .quoteFailed:
          return .none

        case .editLadderTapped:
          state.destination = .ladderEditor(LadderEditorFeature.State(symbol: state.item.symbol, ladder: state.item.ladder, currentPrice: state.quote?.price))
          return .none

        case .editNotesTapped:
          state.destination = .notesEditor(NotesEditorFeature.State(text: state.item.memo))
          return .none

        case .historyTapped:
          state.isShowingLadderHistory = true
          return .none

        case .checklistTapped:
          return .send(.delegate(.openChecklist(symbol: state.item.symbol)))

        case .favoriteTapped:
          state.$item.update(now: now) { $0.isFavorite.toggle() }
          return .none

        case .deleteTapped:
          state.alert = .confirmDelete(symbol: state.item.symbol)
          return .none

        case .alert(.presented(.confirmDelete)):
          return .send(.delegate(.deleteConfirmed(symbol: state.item.symbol)))

        case let .destination(.presented(.ladderEditor(.delegate(.saved(ladder))))):
          guard ladder != state.item.ladder else {
            return .none
          }
          let stamp = now
          state.$item.update(now: stamp) { item in
            item.ladder = ladder
            item.ladderHistory.append(LadderRevision(date: stamp.truncatedToMilliseconds, ladder: ladder))
            if item.ladderHistory.count > LadderRevision.maxCount {
              item.ladderHistory.removeFirst(item.ladderHistory.count - LadderRevision.maxCount)
            }
          }
          return .none

        case let .destination(.presented(.notesEditor(.delegate(.saved(text))))):
          state.$item.update(now: now) { $0.memo = text }
          return .none

        case .binding, .chart, .destination, .alert, .delegate:
          return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
    .ifLet(\.$alert, action: \.alert)
  }

  // MARK: Private

  @Dependency(\.date.now) private var now
  @Dependency(\.marketData) private var marketData
}

// MARK: - StockDetailsFeature.Destination.State + Equatable

extension StockDetailsFeature.Destination.State: Equatable {}

public extension AlertState where Action == StockDetailsFeature.Action.Alert {
  static func confirmDelete(symbol: String) -> Self {
    AlertState {
      TextState("Remove \(symbol)?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete) {
        TextState("Remove")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Its ladder, notes and checklist will be deleted.")
    }
  }
}
