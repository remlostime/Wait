//
// Created by: Kai Chen on 6/27/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

public class Storage<Value: Codable> {
  // MARK: Lifecycle

  public init(name: String) {
    path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: name)
  }

  // MARK: Public

  public func saveValue(_ value: Value) throws {
    let data = try encoder.encode(value)
    try data.write(to: path)
  }

  public func value() throws -> Value {
    let data = try Data(contentsOf: path)
    let value = try decoder.decode(Value.self, from: data)

    return value
  }

  // MARK: Private

  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  private let path: URL
}
