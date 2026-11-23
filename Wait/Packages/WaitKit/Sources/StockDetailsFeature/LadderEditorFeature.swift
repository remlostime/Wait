//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation

// MARK: - LadderInputError

public enum LadderInputError: Error, Equatable, Sendable {
  case invalidNumber(PriceLadder.Rung)
  case ladder(LadderValidationError)

  // MARK: Public

  public var message: String {
    switch self {
      case let .invalidNumber(rung): "\(rung.title) isn't a valid price."
      case let .ladder(.nonPositive(rung)): "\(rung.title) must be greater than 0."
      case let .ladder(.outOfOrder(lower, upper)): "\(upper.title) must be at least \(lower.title)."
    }
  }
}

// MARK: - LadderEditorFeature

/// Edits the five anchors as locale-aware decimal text. It replaces `StockExpectedPriceInputView`, which only accepted whole dollars.
/// Leaving every field empty is valid: it saves `PriceLadder.empty`, which clears the targets.
@Reducer
public struct LadderEditorFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(symbol: String, ladder: PriceLadder, currentPrice: Decimal?, locale: Locale = .autoupdatingCurrent) {
      self.symbol = symbol
      self.currentPrice = currentPrice
      self.locale = locale
      buyLow = PriceInput.format(ladder.buyLow, locale: locale)
      buyHigh = PriceInput.format(ladder.buyHigh, locale: locale)
      fair = PriceInput.format(ladder.fair, locale: locale)
      trim = PriceInput.format(ladder.trim, locale: locale)
      sell = PriceInput.format(ladder.sell, locale: locale)
    }

    // MARK: Public

    public let symbol: String
    public let currentPrice: Decimal?
    public let locale: Locale
    public var buyLow: String
    public var buyHigh: String
    public var fair: String
    public var trim: String
    public var sell: String

    public var parsed: Result<PriceLadder, LadderInputError> {
      var values: [PriceLadder.Rung: Decimal] = [:]
      let fields: [(PriceLadder.Rung, String)] = [(.buyLow, buyLow), (.buyHigh, buyHigh), (.fair, fair), (.trim, trim), (.sell, sell)]
      for (rung, text) in fields {
        guard let parsed = PriceInput.parse(text, locale: locale) else {
          return .failure(.invalidNumber(rung))
        }
        if let value = parsed {
          values[rung] = value
        }
      }
      // Swift 6 infers `any Error` for a plain do/catch, so state the typed-throws clause explicitly.
      do throws(LadderValidationError) {
        return try .success(PriceLadder(
          buyLow: values[.buyLow],
          buyHigh: values[.buyHigh],
          fair: values[.fair],
          trim: values[.trim],
          sell: values[.sell]
        ))
      } catch {
        return .failure(.ladder(error))
      }
    }

    public var derivedFairHint: Decimal? {
      guard case let .success(ladder) = parsed else {
        return nil
      }
      return ladder.derivedFair
    }

    public var canSave: Bool {
      if case .success = parsed { true } else { false }
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case saveTapped
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case saved(PriceLadder)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .binding, .delegate:
          return .none

        case .saveTapped:
          guard case let .success(ladder) = state.parsed else {
            return .none
          }
          return .run { [dismiss] send in
            await send(.delegate(.saved(ladder)))
            await dismiss()
          }

        case .cancelTapped:
          return .run { [dismiss] _ in await dismiss() }
      }
    }
  }

  // MARK: Private

  @Dependency(\.dismiss) private var dismiss
}
