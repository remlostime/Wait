//
// Created by: Kai Chen on 8/7/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import WatchConnectivity

final class Connectivity: NSObject, ObservableObject {
  
  static let shared = Connectivity()
  
  @Published var stockSymbols: [String] = []
  
  private override init() {
    super.init()
    
#if !os(watchOS)
    guard WCSession.isSupported() else {
      return
    }
#endif
    
    WCSession.default.delegate = self
    WCSession.default.activate()
  }
  
  public func send(stockSymbols: [String]) {
    guard WCSession.default.activationState == .activated else {
      return
    }
    
#if os(watchOS)
    guard WCSession.default.isCompanionAppInstalled else {
      return
    }
#else
    guard WCSession.default.isWatchAppInstalled else {
      return
    }
#endif
    
    let userInfo: [String: [String]] = [
      "stockSymbols": stockSymbols
    ]

    WCSession.default.transferUserInfo(userInfo)
  }
  
  private func update(from dictionary: [String: Any]) {
    let key = "stockSymbols"
    guard let stockSymbols = dictionary[key] as? [String] else {
      return
    }

    self.stockSymbols = stockSymbols
  }
}

// MARK: - WCSessionDelegate
extension Connectivity: WCSessionDelegate {
  func session(
      _ session: WCSession,
      activationDidCompleteWith activationState: WCSessionActivationState,
      error: Error?
  ) {
  }
  
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
    let key = "stockSymbols"
    guard let stockSymbols = userInfo[key] as? [String] else {
      return
    }
    
    self.stockSymbols = stockSymbols
  }
  
  func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    update(from: applicationContext)
  }

  #if os(iOS)
  func sessionDidBecomeInactive(_ session: WCSession) {
  }

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }
  #endif
}
