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
  // MARK: Lifecycle

  public init(stock: Binding<Stock>) {
    _stock = stock
  }

  // MARK: Public

  public func makeCoordinator() -> ValuationChartCoordinator {
    ValuationChartCoordinator(self)
  }

  public func makeUIViewController(context: Context) -> ValuationChartViewController {
    let viewController = ValuationChartViewController(stock: stock)

    return viewController
  }

  public func updateUIViewController(_ viewController: ValuationChartViewController, context: Context) {

  }

  // MARK: Internal

  // TODO(kai) - Edit chart price does not work, maybe fix here
  @Binding var stock: Stock
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
