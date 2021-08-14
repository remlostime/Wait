//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

public struct ChecklistItem {
  public let name: String
}

extension ChecklistItem: Identifiable, Hashable {
  public var id: String {
    name
  }
}

extension ChecklistItem {
  public static let allItems: [ChecklistItem] = [
    ChecklistItem(name: "等30分钟再决定"),
    ChecklistItem(name: "愿意持有10年吗"),
    ChecklistItem(name: "wash sale - vested date, 30 days rule etc"),
    ChecklistItem(name: "管理团队健康情况"),
    ChecklistItem(name: "我是不是听别人的评论才想买这支股票？"),
    ChecklistItem(name: "我有没有做过仔细的研究？多长时间？研究过哪些方面？"),
    ChecklistItem(name: "卖家为什么想卖？"),
    ChecklistItem(name: "还有什么我没考虑到的问题？"),
    ChecklistItem(name: "公司有可能破产吗？"),
    ChecklistItem(name: "如果这家公司每年的增长率保持在20%以上是否合理？"),
    ChecklistItem(name: "有什么情况要卖出股票？"),
    ChecklistItem(name: "这是好行业吗？"),
    ChecklistItem(name: "是好公司吗？"),
    ChecklistItem(name: "价格够低吗？"),
    ChecklistItem(name: "如果价格够低？为什么那么低？是暂时的还是长久的？"),
    ChecklistItem(name: "别人为什么要卖？"),
    ChecklistItem(name: "去雪球和seeking alpha看看反对的观点。你能反驳吗"),
  ]

  public static let example = ChecklistItem(name: "This is a check item")
}
