//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Color
import Foundation
import Hue
import NVActivityIndicatorView
import SnapKit
import UIKit

// MARK: - ActivityIndicatorManager

class ActivityIndicatorManager {
  // MARK: Lifecycle

  private init() {
    activityIndicatorView = NVActivityIndicatorView(
      frame: .zero,
      type: .ballBeat,
      color: .white,
      padding: nil
    )
  }

  // MARK: Internal

  static let shared = ActivityIndicatorManager()

  func startAnimating(for view: UIView) {
    let containerView = UIView(frame: .zero)

    containerView.backgroundColor = UIColor.black.alpha(0.1)
    containerView.addSubview(activityIndicatorView)
    activityIndicatorView.snp.makeConstraints { make in
      make.center.equalToSuperview()
      make.height.equalTo(40.0)
      make.width.equalTo(100.0)
    }

    // first we make sure we remove the actual to avoid double add
    self.containerView?.removeFromSuperview()
    self.containerView = containerView

    view.addSubview(containerView)

    containerView.snp.makeConstraints { make in
      make.edges.equalToSuperview()
      make.center.equalToSuperview()
    }

    activityIndicatorView.startAnimating()
  }

  func stopAnimating() {
    activityIndicatorView.stopAnimating()
    containerView?.removeFromSuperview()
  }

  // MARK: Private

  private let activityIndicatorView: NVActivityIndicatorView
  private var containerView: UIView?
}

public extension UIViewController {
  func showActivityIndicator() {
    ActivityIndicatorManager.shared.startAnimating(for: view)
  }

  func hideActivityIndicator() {
    ActivityIndicatorManager.shared.stopAnimating()
  }
}
