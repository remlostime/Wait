// Created by kai_chen on 5/17/21.

import Charts
import Foundation
import Model
import UIKit

class ChartHighlightMarker: MarkerImage {
  // MARK: Lifecycle

  public init(
    font: UIFont,
    textColor: UIColor,
    insets: UIEdgeInsets,
    circleColor: UIColor,
    circleRadius: CGFloat,
    timeSection: TimeSection
  ) {
    self.insets = insets
    self.circleColor = circleColor
    self.circleRadius = circleRadius
    self.timeSection = timeSection

    drawAttributes = [
      .font: font,
      .foregroundColor: textColor,
    ]

    if let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle {
      paragraphStyle.alignment = .center
      drawAttributes[.paragraphStyle] = paragraphStyle
    }

    super.init()
  }

  // MARK: Internal

  var circleColor: UIColor

  var timeSection: TimeSection {
    didSet {
      let dateFormat: String
      switch timeSection {
        case .day:
          dateFormat = "h:mm a"
        case .week:
          dateFormat = "MMM dd, h:mm a"
        case .month, .year, .all:
          dateFormat = "MMM dd, yyyy"
      }
      dateFormatter.dateFormat = dateFormat
    }
  }

  override func offsetForDrawing(atPoint point: CGPoint) -> CGPoint {
    var offset = self.offset
    var size = self.size

    if size.width == 0.0, let image = image {
      size.width = image.size.width
    }
    if size.height == 0.0, let image = image {
      size.height = image.size.height
    }

    let width = size.width

    var origin = point
    origin.x -= width / 2

    if origin.x + offset.x < 0.0 {
      offset.x = -origin.x
    } else if let chart = chartView, origin.x + width + offset.x > chart.bounds.size.width {
      offset.x = chart.bounds.size.width - origin.x - width
    }

    return offset
  }

  override func draw(context: CGContext, point: CGPoint) {
    guard let label = label else {
      return
    }

    let offset = offsetForDrawing(atPoint: point)
    let size = self.size

    let rect = CGRect(
      origin: CGPoint(
        x: point.x + offset.x - size.width / 2,
        y: offset.y + insets.top
      ),
      size: CGSize(width: size.width, height: size.height - insets.top - insets.bottom)
    )

    context.saveGState()

    UIGraphicsPushContext(context)

    label.draw(in: rect, withAttributes: drawAttributes)
    let circleRect = CGRect(
      x: point.x - circleRadius,
      y: point.y - circleRadius,
      width: circleRadius * 2,
      height: circleRadius * 2
    )
    context.setFillColor(circleColor.cgColor)
    context.fillEllipse(in: circleRect)

    UIGraphicsPopContext()

    context.restoreGState()
  }

  override func refreshContent(entry: ChartDataEntry, highlight: Highlight) {
    guard let quote = entry.data as? StockQuote else {
      return
    }

    let date = quote.date
    let dateStr = dateFormatter.string(from: date)
    setLabel(dateStr)
  }

  // MARK: Private

  private let insets: UIEdgeInsets
  private var label: String?
  private var paragraphStyle: NSMutableParagraphStyle?
  private var drawAttributes: [NSAttributedString.Key: Any]
  private let circleRadius: CGFloat

  private lazy var dateFormatter = DateFormatter()

  private func setLabel(_ newLabel: String) {
    label = newLabel

    let labelSize = label?.size(withAttributes: drawAttributes) ?? CGSize.zero

    let size = CGSize(
      width: labelSize.width + insets.left + insets.right,
      height: labelSize.height + insets.top + insets.bottom
    )

    self.size = size
  }
}
