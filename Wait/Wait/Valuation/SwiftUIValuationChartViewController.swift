//
// Created by: kai_chen on 7/10/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Model
import SwiftUI
import UIKit

// MARK: - SwiftUIValuationChartViewController

struct SwiftUIValuationChartViewController: UIViewControllerRepresentable {
  let stock: Stock

  func makeCoordinator() -> ValuationChartCoordinator {
    ValuationChartCoordinator(self)
  }

  func makeUIViewController(context: Context) -> ValuationChartViewController {
    let viewController = ValuationChartViewController(stock: stock)

    return viewController
  }

  func updateUIViewController(_ viewController: ValuationChartViewController, context: Context) {}
}

// MARK: - ValuationChartCoordinator

class ValuationChartCoordinator: NSObject {
  // MARK: Lifecycle

  init(_ viewController: SwiftUIValuationChartViewController) {
    self.viewController = viewController
  }

  // MARK: Internal

  let viewController: SwiftUIValuationChartViewController
}
