//
// Created by: Kai Chen on 6/26/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - Cache

public final class Cache<Key: Hashable, Value> {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public func setValue(_ value: Value, forKey key: Key) {
    let entry = Entry(value: value)
    cache.setObject(entry, forKey: WrappedKey(key))
  }

  public func value(forKey key: Key) -> Value? {
    let entry = cache.object(forKey: WrappedKey(key))
    return entry?.value
  }

  public func removeValue(forKey key: Key) {
    cache.removeObject(forKey: WrappedKey(key))
  }

  // MARK: Private

  private let cache = NSCache<WrappedKey, Entry>()
}

public extension Cache {
  subscript(key: Key) -> Value? {
    get { value(forKey: key) }
    set {
      guard let value = newValue else {
        // If nil was assigned using our subscript,
        // then we remove any value for that key:
        removeValue(forKey: key)
        return
      }

      setValue(value, forKey: key)
    }
  }
}

private extension Cache {
  final class WrappedKey: NSObject {
    // MARK: Lifecycle

    init(_ key: Key) { self.key = key }

    // MARK: Internal

    let key: Key

    override var hash: Int { key.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
      guard let value = object as? WrappedKey else {
        return false
      }

      return value.key == key
    }
  }

  final class Entry {
    // MARK: Lifecycle

    init(value: Value) {
      self.value = value
    }

    // MARK: Internal

    let value: Value
  }
}
