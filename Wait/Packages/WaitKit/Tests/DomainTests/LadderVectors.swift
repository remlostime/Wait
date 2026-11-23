//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - LadderVectors

/// Decodes `shared/ladder-test-vectors.json` (overview §7.4). The `alerts` section is TS-only and ignored here.
struct LadderVectors: Decodable {
  // MARK: Internal

  enum LadderRef: Decodable {
    case named(String)
    case inline([String: String])

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let name = try? container.decode(String.self) {
        self = .named(name)
      } else {
        self = try .inline(container.decode([String: String].self))
      }
    }
  }

  struct ValidationCase: Decodable {
    struct Failure: Decodable {
      let kind: String
      let rung: String?
      let lower: String?
      let upper: String?
    }

    let ladder: LadderRef
    let valid: Bool
    let error: Failure?
  }

  struct KnotCase: Decodable {
    let ladder: LadderRef
    let derivedFair: Double?
    let knots: [[Double]]
  }

  struct EvaluationCase: Decodable {
    let ladder: LadderRef
    let price: String
    let temperature: Double?
    let band: String?
    let status: String
  }

  let version: Int
  let ladders: [String: [String: String]]
  let validation: [ValidationCase]
  let knots: [KnotCase]
  let evaluations: [EvaluationCase]

  static func load() throws -> LadderVectors {
    // Tests/DomainTests/LadderVectors.swift → repo root is six levels up.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // DomainTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // WaitKit
      .deletingLastPathComponent() // Packages
      .deletingLastPathComponent() // Wait (Xcode folder)
      .deletingLastPathComponent() // repo root
      .appending(path: "shared/ladder-test-vectors.json")
    return try JSONDecoder().decode(LadderVectors.self, from: Data(contentsOf: url))
  }

  func raw(_ ref: LadderRef) -> [String: String] {
    switch ref {
      case let .named(name): ladders[name] ?? [:]
      case let .inline(raw): raw
    }
  }

  func ladder(_ ref: LadderRef) throws(LadderValidationError) -> PriceLadder {
    let raw = raw(ref)
    return try PriceLadder(
      buyLow: raw["buyLow"].flatMap(DecimalCoding.parse),
      buyHigh: raw["buyHigh"].flatMap(DecimalCoding.parse),
      fair: raw["fair"].flatMap(DecimalCoding.parse),
      trim: raw["trim"].flatMap(DecimalCoding.parse),
      sell: raw["sell"].flatMap(DecimalCoding.parse)
    )
  }
}
