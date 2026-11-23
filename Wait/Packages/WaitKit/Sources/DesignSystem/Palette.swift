//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Palette

/// Semantic colors with light and dark variants. watchOS always uses the dark variant.
public enum Palette {
  public static let accent = Color.mint
  public static let stockUp = Color(light: 0x00BF83, dark: 0x34D399)
  public static let stockDown = Color(light: 0xDE3745, dark: 0xF87171)
  public static let warning = Color(light: 0xD9A400, dark: 0xFACC15)

  /// Green when the change is ≥ 0, red when it's < 0, secondary when unknown.
  public static func change(_ percent: Double?) -> Color {
    guard let percent else {
      return .secondary
    }
    return percent < 0 ? stockDown : stockUp
  }
}

extension Color {
  init(light: UInt32, dark: UInt32) {
    #if os(iOS)
      self.init(uiColor: UIColor { traits in
        UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
      })
    #else
      self.init(rgb: dark)
    #endif
  }

  init(rgb: UInt32) {
    self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
  }
}

#if os(iOS)
  extension UIColor {
    convenience init(rgb: UInt32) {
      self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
  }
#endif
