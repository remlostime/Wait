// Created by kai_chen on 5/17/21.

import Foundation
import SwiftUI
import UIKit

// MARK: - SwiftUIChartViewController

struct SwiftUIChartViewController: UIViewControllerRepresentable {
  let symbol: String

  func makeCoordinator() -> ChartCoordinator {
    ChartCoordinator(self)
  }

  func makeUIViewController(context: Context) -> ChartViewController {
    let dataSource = PriceHistoryDataSource(symbol: symbol)

    let chartViewController = ChartViewController(
      symbol: symbol,
      dataSource: dataSource,
      showPercent: true,
      selectedTimeSection: .day
    )

    return chartViewController
  }

  func updateUIViewController(_ viewController: ChartViewController, context: Context) {}
}

// MARK: - ChartCoordinator

class ChartCoordinator: NSObject {
  // MARK: Lifecycle

  init(_ viewController: SwiftUIChartViewController) {
    self.viewController = viewController
  }

  // MARK: Internal

  let viewController: SwiftUIChartViewController
}
