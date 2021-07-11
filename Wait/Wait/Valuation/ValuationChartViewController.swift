//
// Created by: kai_chen on 7/10/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import Color
import Model
import SnapKit
import UIKit

// MARK: - ValuationChartViewController

class ValuationChartViewController: UIViewController {
  // MARK: Lifecycle

  init(stock: Stock) {
    self.stock = stock

    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Internal

  override func viewDidLoad() {
    super.viewDidLoad()

    view.addSubview(chartView)
    chartView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }

    setupData()
  }

  func setupData() {
    let expectedPriceData = BarChartDataEntry(x: 0, y: stock.expectedPrice.amountDoubleValue)
    let currentPriceData = BarChartDataEntry(x: 1, y: stock.currentPrice.amountDoubleValue)

    let currentPriceDataSet = BarChartDataSet(entries: [currentPriceData], label: "Current")
    currentPriceDataSet.drawIconsEnabled = true
    currentPriceDataSet.setColor(currentPirceColor)

    let expectedPriceDataSet = BarChartDataSet(entries: [expectedPriceData], label: "Expected")
    expectedPriceDataSet.drawIconsEnabled = true
    expectedPriceDataSet.setColor(.primary)

    let data = BarChartData(dataSets: [currentPriceDataSet, expectedPriceDataSet])
    data.barWidth = 0.65

    chartView.data = data
  }

  // MARK: Private

  private lazy var chartView: HorizontalBarChartView = {
    let chartView = HorizontalBarChartView()
    chartView.delegate = self
    chartView.drawValueAboveBarEnabled = true
    chartView.xAxis.enabled = false
    chartView.rightAxis.enabled = false

    let leftAxis = chartView.leftAxis
    leftAxis.labelFont = .systemFont(ofSize: 14.0)
    leftAxis.drawGridLinesEnabled = false

    return chartView
  }()

  private let stock: Stock

  private var currentPirceColor: UIColor {
    let action = stock.tradeAction
    switch action {
      case .buy:
        return .stockGreen
      case .wait:
        return .stockRed
      case .almost:
        return .banana
    }
  }
}

// MARK: ChartViewDelegate

extension ValuationChartViewController: ChartViewDelegate {}