//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ChecklistFeature
import ComposableArchitecture
import Foundation
import Persistence
import SyncClient

// MARK: - SettingsFeature

/// Settings: the checklist template editor, the account section (anonymous ID, Delete Account), the sync section
/// ("Last synced", "Sync now") and the app version. Plan 06 adds the alerts section (overview §12.3).
@Reducer
public struct SettingsFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Path {
    case checklistTemplate(ChecklistTemplateFeature)
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(appVersion: String = State.versionString(info: Bundle.main.infoDictionary)) {
      self.appVersion = appVersion
    }

    // MARK: Public

    public var path = StackState<Path.State>()
    public var appVersion: String
    public var account = AccountState()
    @Presents public var alert: AlertState<Action.Alert>?
    @SharedReader(.syncState) public var syncState: SyncState
    public var isSyncing = false
    public var syncError: String?

    public var lastSyncedAt: Date? {
      syncState.lastSyncedAt
    }

    public static func versionString(info: [String: Any]?) -> String {
      let version = info?["CFBundleShortVersionString"] as? String ?? "?"
      let build = info?["CFBundleVersion"] as? String ?? "?"
      return "\(version) (\(build))"
    }
  }

  public enum Action {
    case task
    case checklistTemplateTapped
    case path(StackActionOf<Path>)
    case accountLoaded(String)
    case deleteAccountTapped
    case alert(PresentationAction<Alert>)
    case accountDeleted
    case accountDeletionFailed(String)
    case syncNowTapped
    case syncFinished(SyncReport)
    case syncFailed(String)

    public enum Alert: Equatable, Sendable {
      case confirmDeleteAccount
    }
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .task:
          return .run { [identity] send in
            if let id = try? identity.anonymousID() {
              await send(.accountLoaded(id.uuidString))
            }
          }

        case let .accountLoaded(id):
          state.account.anonymousID = id
          return .none

        case .deleteAccountTapped:
          state.alert = .deleteAccount
          return .none

        case .alert(.presented(.confirmDeleteAccount)):
          state.account.isDeleting = true
          state.account.errorMessage = nil
          return .run { [apiClient, identity, syncClient] send in
            do {
              try await apiClient.deleteAccount()
              // The identity goes first, so a sync that starts from here on can't authenticate as the deleted account. The sync
              // bookkeeping goes second: it bumps the sync generation, so a run that is mid-request drops its result, and it forgets
              // the old account's cursor and acknowledgements (which would otherwise stop the new account from receiving the items).
              // The local watchlist stays and re-uploads under the new identity. The reset runs even when the identity reset fails.
              var identityError: (any Error)?
              do {
                try identity.reset()
              } catch {
                identityError = error
              }
              await syncClient.reset()
              if let identityError {
                throw identityError
              }
              await send(.accountDeleted)
            } catch {
              await send(.accountDeletionFailed(error.localizedDescription))
            }
          }

        case .alert:
          return .none

        case .accountDeleted:
          state.account.isDeleting = false
          state.account.anonymousID = nil
          return .none

        case let .accountDeletionFailed(message):
          state.account.isDeleting = false
          state.account.errorMessage = message
          return .none

        case .syncNowTapped:
          guard !state.isSyncing else {
            return .none
          }
          state.isSyncing = true
          state.syncError = nil
          return .run { [syncClient] send in
            do {
              await send(.syncFinished(try await syncClient.sync()))
            } catch {
              await send(.syncFailed(error.localizedDescription))
            }
          }

        case .syncFinished:
          state.isSyncing = false
          return .none

        case let .syncFailed(message):
          state.isSyncing = false
          state.syncError = message
          return .none

        case .checklistTemplateTapped:
          state.path.append(.checklistTemplate(ChecklistTemplateFeature.State()))
          return .none

        case .path:
          return .none
      }
    }
    .forEach(\.path, action: \.path)
    .ifLet(\.$alert, action: \.alert)
  }

  // MARK: Internal

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.identity) var identity
  @Dependency(\.syncClient) var syncClient
}

// MARK: - AccountState

public struct AccountState: Equatable, Sendable {
  // MARK: Lifecycle

  public init(anonymousID: String? = nil) {
    self.anonymousID = anonymousID
  }

  // MARK: Public

  /// Nil after a deletion, until the next server call mints a new ID.
  public var anonymousID: String?
  public var isDeleting = false
  public var errorMessage: String?
}

// MARK: - AlertState + Delete account

extension AlertState where Action == SettingsFeature.Action.Alert {
  static var deleteAccount: Self {
    AlertState {
      TextState("Delete your Wait account?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDeleteAccount) {
        TextState("Delete Account")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("This removes your synced watchlist, notes and alert settings from the Wait server. The stocks on this iPhone stay.")
    }
  }
}

// MARK: - SettingsFeature.Path.State + Equatable

extension SettingsFeature.Path.State: Equatable {}
