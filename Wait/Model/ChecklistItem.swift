//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChecklistItem

public struct ChecklistItem: Codable, Identifiable, Hashable {
  // MARK: Lifecycle

  public init(name: String, id: UUID) {
    self.name = name
    self.id = id
  }

  // MARK: Public

  public var name: String
  public var isChecked: Bool = false
  public let id: UUID
}

public extension ChecklistItem {
  static let allItems: [ChecklistItem] = [
    ChecklistItem(name: "等30分钟再决定", id: UUID()),
    ChecklistItem(name: "愿意持有10年吗", id: UUID()),
    ChecklistItem(name: "wash sale - vested date, 30 days rule etc", id: UUID()),
    ChecklistItem(name: "管理团队健康情况", id: UUID()),
    ChecklistItem(name: "我是不是听别人的评论才想买这支股票？", id: UUID()),
    ChecklistItem(name: "我有没有做过仔细的研究？多长时间？研究过哪些方面？", id: UUID()),
    ChecklistItem(name: "卖家为什么想卖？", id: UUID()),
    ChecklistItem(name: "还有什么我没考虑到的问题？", id: UUID()),
    ChecklistItem(name: "公司有可能破产吗？", id: UUID()),
    ChecklistItem(name: "如果这家公司每年的增长率保持在20%以上是否合理？", id: UUID()),
    ChecklistItem(name: "有什么情况要卖出股票？", id: UUID()),
    ChecklistItem(name: "这是好行业吗？", id: UUID()),
    ChecklistItem(name: "是好公司吗？", id: UUID()),
    ChecklistItem(name: "价格够低吗？", id: UUID()),
    ChecklistItem(name: "如果价格够低？为什么那么低？是暂时的还是长久的？", id: UUID()),
    ChecklistItem(name: "别人为什么要卖？", id: UUID()),
    ChecklistItem(name: "去雪球和seeking alpha看看反对的观点。你能反驳吗", id: UUID()),
  ]

  static let example = ChecklistItem(name: "This is a check item", id: UUID())
}
