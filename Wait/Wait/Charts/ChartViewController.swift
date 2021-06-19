// Created by kai_chen on 5/17/21.

import Charts
import Foundation
import HMSegmentedControl
import Money
import SnapKit
import UI
import UIKit

// MARK: - ChartViewController

public class ChartViewController: UIViewController {
  // MARK: Lifecycle

  public init(
    symbol: String,
    dataSource: ChartViewDataSource,
    showPercent: Bool = true,
    selectedTimeSection: TimeSection = .day
  ) {
    self.symbol = symbol
    self.dataSource = dataSource
    self.showPercent = showPercent
    self.selectedTimeSection = selectedTimeSection
    super.init(nibName: nil, bundle: nil)

    dataSource.setDelegate(delegate: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Public

  public override func viewDidLoad() {
    super.viewDidLoad()

    view.addSubview(allContentsStackView)

    allContentsStackView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }

    showActivityIndicator()
    pricePercentageStackView.isHidden = true
  }

  public override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    fetchData()
  }

  // MARK: Private

  private let showPercent: Bool
  private let selectedTimeSection: TimeSection
  private var isMovingTheChart: Bool = false
  private let refreshPriceInterval: TimeInterval = 3.0

  private let symbol: String
  private let dataSource: ChartViewDataSource
  private lazy var timeRangeSegmentedControl: HMSegmentedControl = {
    let titles = TimeSection.allCases.map { $0.timeSectionDescription }
    let timeRangeSegmentedControl = HMSegmentedControl(sectionTitles: titles)
    timeRangeSegmentedControl.backgroundColor = .clear
    timeRangeSegmentedControl.selectionIndicatorHeight = 2.0
    timeRangeSegmentedControl.titleTextAttributes = [
      NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
      NSAttributedString.Key.foregroundColor: isLightMode ? UIColor.black : UIColor.white,
    ]
    timeRangeSegmentedControl.selectionIndicatorColor = .mint
    timeRangeSegmentedControl.selectedTitleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.mint]
    timeRangeSegmentedControl.selectionIndicatorLocation = .bottom

    timeRangeSegmentedControl.snp.makeConstraints { make in
      make.height.equalTo(32.0)
    }

    timeRangeSegmentedControl.selectedSegmentIndex = UInt(selectedTimeSection.rawValue)

    timeRangeSegmentedControl.addTarget(self, action: #selector(timeRangeSegmentedControl(control:)), for: .valueChanged)

    return timeRangeSegmentedControl
  }()

  private lazy var chartHighlightMarker: ChartHighlightMarker = {
    let marker = ChartHighlightMarker(
      font: .systemFont(ofSize: 14),
      textColor: .gray,
      insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4),
      circleColor: UIColor.mint,
      circleRadius: 4.0,
      timeSection: timeSection ?? .day
    )

    return marker
  }()

  private lazy var chart: LineChartView = {
    let chart = LineChartView()
    chart.isUserInteractionEnabled = true
    chart.setScaleEnabled(false)
    chart.xAxis.avoidFirstLastClippingEnabled = true
    chart.minOffset = 0
    chart.extraTopOffset = 30.0
    chart.highlightPerTapEnabled = false
    chart.pinchZoomEnabled = false
    chart.legend.enabled = false
    chart.xAxis.enabled = false
    chart.leftAxis.enabled = false
    chart.rightAxis.enabled = false
    chart.delegate = self

    chartHighlightMarker.chartView = chart
    chart.marker = chartHighlightMarker

    return chart
  }()

  private lazy var allContentsStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.alignment = .leading
    stackView.distribution = .fill
    stackView.axis = .vertical
    stackView.layoutMargins = UIEdgeInsets(top: 0.0, left: 16.0, bottom: 0.0, right: 16.0)
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.addArrangedSubview(priceLabel)
    if showPercent {
      stackView.addArrangedSubview(pricePercentageStackView)
    }

    stackView.addArrangedSubview(chart)
    stackView.addArrangedSubview(timeRangeSegmentedControl)

    priceLabel.snp.makeConstraints { make in
      make.leading.trailing.equalTo(stackView.layoutMargins)
    }

    chart.snp.makeConstraints { make in
      make.leading.trailing.equalToSuperview()
    }

    timeRangeSegmentedControl.snp.makeConstraints { make in
      make.leading.trailing.equalTo(stackView.layoutMargins)
    }

    return stackView
  }()

  private lazy var priceChangeLabel: UILabel = {
    let priceChangeLabel = UILabel()
    priceChangeLabel.font = .systemFont(ofSize: 13)
    return priceChangeLabel
  }()

  private lazy var priceLabel: NumberScrollCounter = {
    let priceLabel = NumberScrollCounter(
      value: currentPrice.amountDoubleValue ?? 0.0,
      scrollDuration: 0.1,
      decimalPlaces: 2,
      prefix: "$",
      font: .systemFont(ofSize: 32.0)
    )

    let height = priceLabel.bounds.height
    priceLabel.snp.makeConstraints { make in
      make.height.equalTo(height)
    }

    return priceLabel
  }()

  private lazy var pricePercentageChangeLabel: UILabel = {
    let pricePercentageChangeLabel = UILabel()
    pricePercentageChangeLabel.font = .systemFont(ofSize: 13)
    return pricePercentageChangeLabel
  }()

  private lazy var dateLabel: UILabel = {
    let label = UILabel()
    let section = TimeSection(rawValue: Int(timeRangeSegmentedControl.selectedSegmentIndex))
    label.text = section?.dateLabelDescription
    label.font = .systemFont(ofSize: 13.0)
    label.textColor = .gray

    return label
  }()

  private lazy var pricePercentageStackView: UIStackView = {
    let pricePercentageStackView = UIStackView(arrangedSubviews: [priceChangeLabel, pricePercentageChangeLabel, dateLabel])
    pricePercentageStackView.alignment = .center
    pricePercentageStackView.axis = .horizontal
    pricePercentageStackView.distribution = .equalSpacing
    pricePercentageStackView.spacing = 3.0

    return pricePercentageStackView
  }()

  private var lastNow: TimeInterval = Date().timeIntervalSinceReferenceDate

  private var isLightMode: Bool {
    traitCollection.userInterfaceStyle == .light
  }

  private var currentPrice: Money<USD> {
    dataSource.currentPrice
  }

  private var changedPrice: Double {
    let price: Double = currentPrice.amountDoubleValue ?? .zero
    let priceChangePercent = 0.0
    return price * priceChangePercent
  }

  private var timeSection: TimeSection? {
    TimeSection(rawValue: Int(timeRangeSegmentedControl.selectedSegmentIndex))
  }

  private func fetchData() {
    dataSource.fetchData(for: TimeSection.allCases)
  }

  private func updateChart(data: [TimeSection: ChartData]) {
    guard let timeSection = timeSection else {
      logger.error("Failed to convert timeRangeSegmentedControl.selectedSegmentIndex to timeSection")
      return
    }

    guard let newChartData = data[timeSection] else {
      logger.error("Failed to load newChartData from timeSection: \(timeSection)")
      return
    }

    chart.data = newChartData
    chart.notifyDataSetChanged()

    chartHighlightMarker.timeSection = timeSection

    guard
      let dataSet = newChartData.dataSets.first,
      let openPrice = dataSet.entryForIndex(0)?.y,
      let lastPrice = currentPrice.amountDoubleValue ?? dataSet.entryForIndex(dataSet.entryCount - 1)?.y
    else {
      return
    }

    updateDisplayPriceInfo(currentPrice: lastPrice, comparedPrice: openPrice)

    if lastPrice >= openPrice {
      chartHighlightMarker.circleColor = .stockGreen
    } else {
      chartHighlightMarker.circleColor = .stockRed
    }
  }

  private func updateDisplayPriceInfo(currentPrice: Double, comparedPrice: Double) {
    guard comparedPrice > 0 else {
      return
    }
    let now = Date().timeIntervalSinceReferenceDate

    // this stops the animation to cut the numbers out
    let diff = now - lastNow
    if diff > 1 || isMovingTheChart {
      lastNow = now
      priceLabel.setValue(currentPrice, animated: true)
    }

    let priceDifference = currentPrice - comparedPrice
    let isPositive = priceDifference >= 0
    let newColor: UIColor = isPositive ? .stockGreen : .stockRed
    priceChangeLabel.textColor = newColor
    priceChangeLabel.text = (isPositive ? "+" : "") + Money<USD>(floatLiteral: priceDifference).formattedCurrency

    let nonZeroComparedPrice = comparedPrice <= 0 ? 1.0 : comparedPrice
    let priceDiffRatio = abs(priceDifference / nonZeroComparedPrice * 100.0)
    pricePercentageChangeLabel.textColor = newColor
    let percenteText = priceDiffRatio.rounded(numberOfDecimalPlaces: 2, rule: .up).string
    pricePercentageChangeLabel.text = isPositive ? "(+\(percenteText)%)" : "(-\(percenteText)%)"
  }

  @objc
  private func timeRangeSegmentedControl(control: HMSegmentedControl) {
    let section = TimeSection(rawValue: Int(control.selectedSegmentIndex))
    dateLabel.text = section?.dateLabelDescription
    updateChart(data: dataSource.chartData)
  }
}

// MARK: ChartViewDelegate

extension ChartViewController: ChartViewDelegate {
  // MARK: Public

  public func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
    dateLabel.isHidden = true

    let currentPrice = entry.y
    let (beginPrice, _) = getBeginAndEndPrice(chartView: chartView)

    isMovingTheChart = true
    updateDisplayPriceInfo(currentPrice: currentPrice, comparedPrice: beginPrice)
  }

  public func chartViewDidEndPanning(_ chartView: ChartViewBase) {
    dateLabel.isHidden = false

    let (beginPrice, _) = getBeginAndEndPrice(chartView: chartView)
    let currentPrice = self.currentPrice.amountDoubleValue ?? .zero

    isMovingTheChart = false
    updateDisplayPriceInfo(currentPrice: currentPrice, comparedPrice: beginPrice)

    chartView.highlightValue(nil)
  }

  // MARK: Internal

  func getBeginAndEndPrice(chartView: ChartViewBase) -> (beginPrice: Double, endPrice: Double) {
    guard
      let dataSet = chartView.data?.dataSets.first,
      let beginPrice = dataSet.entryForIndex(0)?.y,
      let endPrice = dataSet.entryForIndex(dataSet.entryCount - 1)?.y
    else {
      return (0, 0)
    }

    return (beginPrice, endPrice)
  }
}

// MARK: ChartViewDataSourceDelegate

extension ChartViewController: ChartViewDataSourceDelegate {
  public func currentPriceDidUpdate(_ currentPrice: Money<USD>) {
    let (beginPrice, _) = getBeginAndEndPrice(chartView: chart)
    let currentPriceDouble = currentPrice.amountDoubleValue ?? .zero

    updateDisplayPriceInfo(currentPrice: currentPriceDouble, comparedPrice: beginPrice)
  }

  public func dataDidUpdate(_ data: [TimeSection: ChartData]) {
    DispatchQueue.main.async {
      self.hideActivityIndicator()
      self.pricePercentageStackView.isHidden = false
      self.updateChart(data: data)
    }
  }
}
