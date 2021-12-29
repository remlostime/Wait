//
// Created by: kai_chen on 12/29/21.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
import XCTest
@testable import StockDetailsFeature
import SnapshotTesting

class StockStatsViewSnapshotTests: XCTestCase {

  func testView() {
    let view = StockStatsView(title: "PE", value: "10.0")
    let vc = UIHostingController(rootView: view)
    vc.view.frame = UIScreen.main.bounds

    assertSnapshot(matching: vc, as: .image)
  }
}
