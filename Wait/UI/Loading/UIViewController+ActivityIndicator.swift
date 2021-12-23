//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SnapKit
import UIKit

// MARK: - ActivityIndicatorManager

class ActivityIndicatorManager {
  // MARK: Lifecycle

  private init() {
    activityIndicatorView = UIActivityIndicatorView(frame: .zero)
    activityIndicatorView.snp.makeConstraints { make in
      make.width.height.equalTo(50)
    }
  }

  // MARK: Internal

  static let shared = ActivityIndicatorManager()

  func startAnimating(for view: UIView) {
    view.addSubview(activityIndicatorView)

    activityIndicatorView.snp.makeConstraints { make in
      make.center.equalToSuperview()
    }

    activityIndicatorView.startAnimating()
  }

  func stopAnimating() {
    activityIndicatorView.stopAnimating()
    activityIndicatorView.removeFromSuperview()
  }

  // MARK: Private

  private let activityIndicatorView: UIActivityIndicatorView
}

public extension UIViewController {
  func showActivityIndicator() {
    ActivityIndicatorManager.shared.startAnimating(for: view)
  }

  func hideActivityIndicator() {
    ActivityIndicatorManager.shared.stopAnimating()
  }
}
