//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChecklistTemplate

/// The default per-stock checklist. The UUIDs are deterministic, so tests and migrations are stable.
public enum ChecklistTemplate {
  public static let defaultPrompts: [String] = [
    "等30分钟再决定",
    "愿意持有10年吗",
    "wash sale - vested date, 30 days rule etc",
    "管理团队健康情况",
    "我是不是听别人的评论才想买这支股票？",
    "我有没有做过仔细的研究？多长时间？研究过哪些方面？",
    "卖家为什么想卖？",
    "还有什么我没考虑到的问题？",
    "公司有可能破产吗？",
    "如果这家公司每年的增长率保持在20%以上是否合理？",
    "有什么情况要卖出股票？",
    "这是好行业吗？",
    "是好公司吗？",
    "价格够低吗？",
    "如果价格够低？为什么那么低？是暂时的还是长久的？",
    "别人为什么要卖？",
    "去雪球和seeking alpha看看反对的观点。你能反驳吗",
  ]

  public static var defaultItems: [ChecklistItem] {
    defaultPrompts.enumerated().map { offset, prompt in
      ChecklistItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!, name: prompt)
    }
  }
}
