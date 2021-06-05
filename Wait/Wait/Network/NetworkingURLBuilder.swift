// Created by kai_chen on 5/16/21.

import Foundation

enum NetworkingURLBuilder {
  static func buildURL(
    domain: URLDomain = .twelveData,
    api: String,
    params: [String: String?]? = nil
  ) -> URL? {
    guard let url = URL(string: api, relativeTo: URL(string: domain.rawValue)) else {
      return nil
    }

    var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)

    var finalQueryItems = domain.queryItems

    if let params = params {
      let queryItems: [URLQueryItem] = params.compactMap { key, value -> URLQueryItem in
        URLQueryItem(name: key, value: value)
      }

      finalQueryItems.append(contentsOf: queryItems)
    }

    urlComponents?.queryItems = finalQueryItems

    return urlComponents?.url
  }
}
