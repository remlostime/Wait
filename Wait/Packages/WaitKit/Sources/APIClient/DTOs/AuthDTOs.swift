//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - RegisterRequestDTO

struct RegisterRequestDTO: Encodable, Sendable {
  let anonymousId: String
}

// MARK: - RegisterResponseDTO

struct RegisterResponseDTO: Decodable, Sendable {
  struct User: Decodable, Sendable {
    let id: String
  }

  let token: String
  let user: User
}
