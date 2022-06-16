// Created by kai_chen on 5/17/21.

import Foundation
import SwiftUI
import UIKit

// MARK: - SwiftUIChartViewController

/*

 public struct SwiftUIChartViewController: UIViewControllerRepresentable {
   // MARK: Lifecycle

   public init(symbol: String) {
     self.symbol = symbol
   }

   // MARK: Public

   public func makeCoordinator() -> ChartCoordinator {
     ChartCoordinator(self)
   }

   public func makeUIViewController(context: Context) -> ChartViewController {
     let dataSource = PriceHistoryDataSource(symbol: symbol)

     let chartViewController = ChartViewController(
       symbol: symbol,
       dataSource: dataSource,
       showPercent: true,
       selectedTimeSection: .day
     )

     return chartViewController
   }

   public func updateUIViewController(_ viewController: ChartViewController, context: Context) {}

   // MARK: Internal

   let symbol: String
 }

 // MARK: - ChartCoordinator

 public class ChartCoordinator: NSObject {
   // MARK: Lifecycle

   init(_ viewController: SwiftUIChartViewController) {
     self.viewController = viewController
   }

   // MARK: Internal

   let viewController: SwiftUIChartViewController
 }

 */
