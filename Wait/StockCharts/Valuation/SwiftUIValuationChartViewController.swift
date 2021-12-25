//
// Created by: kai_chen on 7/10/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Model
import SwiftUI
import UIKit

// MARK: - SwiftUIValuationChartViewController

public struct SwiftUIValuationChartViewController: UIViewControllerRepresentable {
  let stock: Stock

  public init(stock: Stock) {
    self.stock = stock
  }

  public func makeCoordinator() -> ValuationChartCoordinator {
    ValuationChartCoordinator(self)
  }

  public func makeUIViewController(context: Context) -> ValuationChartViewController {
    let viewController = ValuationChartViewController(stock: stock)

    return viewController
  }

  public func updateUIViewController(_ viewController: ValuationChartViewController, context: Context) {
    viewController.stock = stock
  }
}

// MARK: - ValuationChartCoordinator

public class ValuationChartCoordinator: NSObject {
  // MARK: Lifecycle

  init(_ viewController: SwiftUIValuationChartViewController) {
    self.viewController = viewController
  }

  // MARK: Internal

  let viewController: SwiftUIValuationChartViewController
}
