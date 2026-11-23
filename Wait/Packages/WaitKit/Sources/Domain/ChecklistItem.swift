//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChecklistItem

/// The JSON keys (`id`, `name`, `isChecked`) match the legacy `Model.ChecklistItem` files.
public struct ChecklistItem: Codable, Equatable, Hashable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(id: UUID, name: String, isChecked: Bool = false) {
    self.id = id
    self.name = name
    self.isChecked = isChecked
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    isChecked = try c.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
  }

  // MARK: Public

  public var id: UUID
  public var name: String
  public var isChecked: Bool

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case id, name, isChecked
  }
}
