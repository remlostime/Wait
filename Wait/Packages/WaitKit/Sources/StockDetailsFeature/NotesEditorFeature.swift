//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation

// MARK: - NotesEditorFeature

/// Edits the multi-line memo. It only ever emits the text, so saving a note can never touch the ladder (and saving a ladder can never touch the note).
@Reducer
public struct NotesEditorFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    public init(text: String) {
      self.text = text
    }

    public var text: String
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case saveTapped
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case saved(String)
    }
  }

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .binding, .delegate:
          return .none

        case .saveTapped:
          let text = state.text
          return .run { [dismiss] send in
            await send(.delegate(.saved(text)))
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
