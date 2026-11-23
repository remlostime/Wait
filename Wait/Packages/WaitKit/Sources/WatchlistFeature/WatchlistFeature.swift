//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature

// MARK: - WatchlistFeature

/// The home screen: Favorites and Watchlist sections, pull-to-refresh, swipe to favorite or delete, and reordering.
/// Quotes are loaded `.cacheOnly`, then `.useCache`, so the list renders instantly and refetches only after the TTL.
@Reducer
public struct WatchlistFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Path {
    case details(StockDetailsFeature)
    case checklist(ChecklistFeature)
  }

  @Reducer
  public enum Destination {
    case addStock(AddStockFeature)
  }

  public enum QuotesStatus: Equatable, Sendable {
    case idle
    case refreshing
    case delayed(String)
  }

  /// What the widget/watch snapshot depends on. `AppFeature` publishes on every change (debounced).
  public struct SnapshotInputs: Equatable, Sendable {
    public var items: [WatchlistItem]
    public var quotes: [String: Quote]
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    @Shared(.watchlist) public var items
    public var quotes: [String: Quote] = [:]
    public var quotesStatus: QuotesStatus = .idle
    public var path = StackState<Path.State>()
    @Presents public var destination: Destination.State?

    public var favorites: [WatchlistItem] {
      items.filter(\.isFavorite).sorted { $0.sortIndex < $1.sortIndex }
    }

    public var others: [WatchlistItem] {
      items.filter { !$0.isFavorite }.sorted { $0.sortIndex < $1.sortIndex }
    }

    public var snapshotInputs: SnapshotInputs {
      SnapshotInputs(items: Array(items), quotes: quotes)
    }

    /// Pushes details for `symbol`, for row taps and deep links. Returns false for an unknown symbol.
    @discardableResult
    public mutating func showDetails(symbol: String) -> Bool {
      let symbol = symbol.uppercased()
      guard let item = Shared($items[id: symbol]) else {
        return false
      }
      path.append(.details(StockDetailsFeature.State(item: item, quote: quotes[symbol])))
      return true
    }
  }

  public enum Action {
    case task
    case sceneBecameActive
    case refreshPulled
    case quotesLoaded([Quote])
    case quotesFailed(MarketDataError)
    case addTapped
    case rowTapped(symbol: String)
    case deleteSwiped(symbol: String)
    case favoriteSwiped(symbol: String)
    case moved(WatchlistSection, from: IndexSet, to: Int)
    case path(StackActionOf<Path>)
    case destination(PresentationAction<Destination.Action>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      /// Pull-to-refresh. `AppFeature` ignores this in plan 02 and starts a sync in plan 05.
      case refreshRequested
    }
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .task:
          return loadQuotes(symbols: state.items.map(\.symbol), policies: [.cacheOnly, .useCache], id: .all)

        case .sceneBecameActive:
          return loadQuotes(symbols: state.items.map(\.symbol), policies: [.useCache], id: .all)

        case .refreshPulled:
          // With nothing to load there is no completion to clear the spinner state.
          state.quotesStatus = state.items.isEmpty ? .idle : .refreshing
          return .merge(
            .send(.delegate(.refreshRequested)),
            loadQuotes(symbols: state.items.map(\.symbol), policies: [.reload], id: .all)
          )

        case let .quotesLoaded(quotes):
          for quote in quotes {
            state.quotes[quote.symbol] = quote
          }
          state.quotesStatus = quotes.contains(where: \.isStale) ? .delayed("Showing cached prices") : .idle
          return .none

        case let .quotesFailed(error):
          state.quotesStatus = .delayed(error.userMessage)
          return .none

        case .addTapped:
          state.destination = .addStock(AddStockFeature.State())
          return .none

        case let .rowTapped(symbol):
          state.showDetails(symbol: symbol)
          return .none

        case let .deleteSwiped(symbol):
          state.$items.remove(symbol, now: now)
          state.quotes[symbol] = nil
          return .none

        case let .favoriteSwiped(symbol):
          state.$items.update(symbol, now: now) { $0.isFavorite.toggle() }
          return .none

        case let .moved(section, source, destination):
          state.$items.reorder(section: section, from: source, to: destination, now: now)
          return .none

        case let .path(.element(_, .details(.delegate(.openChecklist(symbol))))):
          guard let item = Shared(state.$items[id: symbol]) else {
            return .none
          }
          state.path.append(.checklist(ChecklistFeature.State(item: item)))
          return .none

        case let .path(.element(id, .details(.delegate(.deleteConfirmed(symbol))))):
          // Pop first, so the details screen never renders a removed item.
          state.path.pop(from: id)
          state.$items.remove(symbol, now: now)
          state.quotes[symbol] = nil
          return .none

        case let .destination(.presented(.addStock(.delegate(.added(item))))):
          state.$items.add(item, now: now)
          state.destination = nil
          return loadQuotes(symbols: [item.symbol], policies: [.useCache], id: .single(item.symbol))

        case .path, .destination, .delegate:
          return .none
      }
    }
    .forEach(\.path, action: \.path)
    .ifLet(\.$destination, action: \.destination)
  }

  // MARK: Private

  private enum CancelID: Hashable {
    case all
    case single(String)
  }

  @Dependency(\.date.now) private var now
  @Dependency(\.marketData) private var marketData

  /// `.notCached` from a `.cacheOnly` attempt is silent. Any other error reports `.quotesFailed`, and existing quotes are kept.
  private func loadQuotes(symbols: [String], policies: [CachePolicy], id: CancelID) -> Effect<Action> {
    guard !symbols.isEmpty else {
      return .none
    }
    return .run { [marketData] send in
      for policy in policies {
        do {
          try await send(.quotesLoaded(marketData.quotes(symbols, policy)))
        } catch {
          let mapped = try MarketDataError(error) // rethrows cancellation
          if mapped != .notCached {
            await send(.quotesFailed(mapped))
          }
        }
      }
    }
    .cancellable(id: id, cancelInFlight: true)
  }
}

// MARK: - WatchlistFeature.Path.State + Equatable

extension WatchlistFeature.Path.State: Equatable {}

// MARK: - WatchlistFeature.Destination.State + Equatable

extension WatchlistFeature.Destination.State: Equatable {}
