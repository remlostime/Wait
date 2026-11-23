//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Foundation
import Logging
import NotificationClient
import Persistence

// MARK: - PushFeature

/// Remote-notification plumbing:
/// - At launch, registers with APNs when alerts are on and allowed, and finishes a pending device unregistration when they're off.
/// - Uploads the device token APNs hands back.
/// - Turns push taps into `delegate(.openStock)`.
@Reducer
public struct PushFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    @Shared(.alertsEnabled) public var alertsEnabled: Bool
    @Shared(.apnsDeviceToken) public var deviceToken: String?
  }

  public enum Action: Equatable, Sendable {
    case launched
    case authorizationLoaded(NotificationAuthorization)
    case registered(Data)
    case registrationFailed(String)
    case staleTokenRemoved(String)
    case tapped(String)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case openStock(String)
    }
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .launched:
          let pendingUnregistration = state.alertsEnabled ? nil : state.deviceToken
          return .merge(
            .run { [notifications] send in
              for await symbol in notifications.tappedSymbols() {
                await send(.tapped(symbol))
              }
            }
            .cancellable(id: CancelID.taps, cancelInFlight: true),
            .run { [notifications] send in
              await send(.authorizationLoaded(notifications.authorizationStatus()))
            },
            .run { [apiClient] send in
              guard let token = pendingUnregistration else {
                return
              }
              do {
                try await apiClient.unregisterDevice(token)
                await send(.staleTokenRemoved(token))
              } catch {
                Log.push.error("Pending device unregistration failed, will retry next launch: \(error)")
              }
            }
          )

        case let .authorizationLoaded(status):
          guard state.alertsEnabled, status == .authorized else {
            return .none
          }
          return .run { [notifications] _ in
            await notifications.registerForRemoteNotifications()
          }

        case let .registered(deviceToken):
          // A token can arrive after the user turned alerts off (the toggle raced the APNs callback). Storing and uploading it would
          // register a device the user just opted out of, and nothing would clear it.
          guard state.alertsEnabled else {
            return .none
          }
          let token = APNsToken.hexString(deviceToken)
          state.$deviceToken.withLock { $0 = token }
          return .run { [apiClient] _ in
            try await apiClient.registerDevice(DeviceRegistrationDTO(token: token))
          } catch: { error, _ in
            Log.push.error("Device registration upload failed: \(error)")
          }

        case let .registrationFailed(message):
          Log.push.error("APNs registration failed: \(message)")
          return .none

        case let .staleTokenRemoved(removed):
          // Only forget the token the server confirmed. A newer one may have been stored while the DELETE was in flight.
          state.$deviceToken.withLock { stored in
            if stored == removed {
              stored = nil
            }
          }
          return .none

        case let .tapped(symbol):
          return .send(.delegate(.openStock(symbol)))

        case .delegate:
          return .none
      }
    }
  }

  // MARK: Internal

  enum CancelID {
    case taps
  }

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.notifications) var notifications
}
