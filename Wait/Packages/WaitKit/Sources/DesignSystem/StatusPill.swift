//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import SwiftUI

// MARK: - StatusPill

/// The ladder status as a tinted capsule. A nil status renders as "No Anchors".
public struct StatusPill: View {
  // MARK: Lifecycle

  public init(status: LadderStatus?, compact: Bool = false) {
    self.status = status ?? .noAnchors
    self.compact = compact
  }

  // MARK: Public

  public var body: some View {
    Group {
      if compact {
        Image(systemName: status.symbolName)
      } else {
        Label(status.title, systemImage: status.symbolName)
      }
    }
    .font(.caption.weight(.semibold))
    .padding(.horizontal, compact ? Spacing.xs : Spacing.s)
    .padding(.vertical, Spacing.xxs)
    .foregroundStyle(status.tint)
    .background(status.tint.opacity(0.15), in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.title)
  }

  // MARK: Private

  private let status: LadderStatus
  private let compact: Bool
}

#Preview {
  VStack(alignment: .leading) {
    ForEach(LadderStatus.allCases, id: \.self) { StatusPill(status: $0) }
    StatusPill(status: .buyZone, compact: true)
  }
  .padding()
}
