//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import CoreGraphics

/// 4-pt spacing scale. It replaces the legacy `Size` enum, which is deleted at the cutover.
public enum Spacing {
  public static let xxs: CGFloat = 2
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let xl: CGFloat = 24
  public static let xxl: CGFloat = 32
}
