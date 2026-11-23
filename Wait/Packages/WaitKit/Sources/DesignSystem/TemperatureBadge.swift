//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

// MARK: - TemperatureBadge

/// The 0–100 ladder temperature, for example "27°", tinted by band.
public struct TemperatureBadge: View {
  // MARK: Lifecycle

  public init(temperature: Temperature?) {
    self.temperature = temperature
  }

  // MARK: Public

  public var body: some View {
    let tint = temperature?.band.tint ?? .secondary
    Text(Self.label(for: temperature))
      .font(.caption.monospacedDigit().weight(.semibold))
      .padding(.horizontal, Spacing.s)
      .padding(.vertical, Spacing.xxs)
      .foregroundStyle(tint)
      .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
      .accessibilityLabel(temperature.map { "Temperature \(Int($0.value.rounded())), \($0.band.title)" } ?? "No temperature")
  }

  public nonisolated static func label(for temperature: Temperature?) -> String {
    temperature?.formatted ?? "—"
  }

  // MARK: Private

  private let temperature: Temperature?
}

#Preview {
  HStack {
    TemperatureBadge(temperature: Temperature(value: 8))
    TemperatureBadge(temperature: Temperature(value: 35))
    TemperatureBadge(temperature: Temperature(value: 55))
    TemperatureBadge(temperature: Temperature(value: 72))
    TemperatureBadge(temperature: Temperature(value: 91))
    TemperatureBadge(temperature: nil)
  }
  .padding()
}
