//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation
@testable import SyncClient
import Testing

struct SyncMappingTests {
  @Test
  func mapsAnUpsertToTheWireShape() throws {
    var item = makeItem("AAPL", memo: "Wait", isFavorite: true, sortIndex: 3, updatedAt: stamp(123))
    item.ladder = try PriceLadder(buyLow: Decimal(string: "0.0075")!, buyHigh: Decimal(string: "14.2")!)
    item.checklist = [ChecklistItem(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, name: "Moat?", isChecked: true)]
    item.ladderHistory = [LadderRevision(date: stamp(0), ladder: try PriceLadder(buyHigh: 16))]

    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)

    #expect(dto.symbol == "AAPL")
    #expect(dto.ladder == LadderDTO(buyLow: "0.0075", buyHigh: "14.2"))
    #expect(dto.clientUpdatedAt == "2026-11-20T15:00:00.123Z")
    #expect(dto.checklist == [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)])
    #expect(dto.ladderHistory == [LadderRevisionDTO(date: "2026-11-20T15:00:00.000Z", ladder: LadderDTO(buyHigh: "16"))])
    #expect(!dto.deleted)
  }

  @Test
  func mapsATombstoneWithPlaceholderFields() {
    let dto = SyncMapping.changeDTO(.deletion(symbol: "MSFT", at: stamp(5)), now: .distantFuture)
    #expect(dto == WatchlistChangeDTO(
      symbol: "MSFT", name: "MSFT", ladder: LadderDTO(), memo: "", isFavorite: false, sortIndex: 0,
      checklist: [], ladderHistory: [], clientUpdatedAt: "2026-11-20T15:00:00.005Z", deleted: true
    ))
  }

  @Test
  func clampsOversizedFieldsToTheServerLimitsInUTF16Units() {
    var item = makeItem("AAPL")
    item.memo = String(repeating: "😀", count: 6000) // 12,000 UTF-16 units
    item.name = String(repeating: "n", count: 800)
    item.checklist = (0 ..< 150).map { _ in ChecklistItem(id: UUID(), name: "q", isChecked: false) }
    item.ladderHistory = (0 ..< 250).map { LadderRevision(date: stamp(Int64($0)), ladder: .empty) }

    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)

    #expect(dto.memo.utf16.count == 10000)
    #expect(dto.memo.allSatisfy { $0 == "😀" })
    #expect(dto.name.count == 500)
    #expect(dto.checklist.count == 100)
    #expect(dto.ladderHistory.count == 200)
    #expect(dto.ladderHistory.first?.date == SyncStamp.string(from: stamp(50)))
  }

  @Test
  func roundsAnchorsToSixDecimals() throws {
    var item = makeItem("AAPL")
    item.ladder = try PriceLadder(buyHigh: Decimal(string: "1.23456789")!)
    #expect(SyncMapping.changeDTO(.upsert(item), now: .distantFuture).ladder.buyHigh == "1.234568")
  }

  @Test
  func clampsAFutureStampToNowPlusFiveMinutes() {
    let now = stamp(0)
    let future = makeItem("AAPL", updatedAt: stamp(3_600_000))
    #expect(SyncMapping.changeDTO(.upsert(future), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(300_000)))
    #expect(SyncMapping.changeDTO(.deletion(symbol: "MSFT", at: stamp(3_600_000)), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(300_000)))
    #expect(SyncMapping.changeDTO(.upsert(makeItem("AAPL", updatedAt: stamp(1))), now: now).clientUpdatedAt == SyncStamp.string(from: stamp(1)))
  }

  @Test
  func stripsNulCharactersBecauseTheServerRejectsTheWholeBatchOverThem() {
    var item = makeItem("AAPL", memo: "a\u{0}b\u{0}")
    item.name = "App\u{0}le"
    item.checklist = [ChecklistItem(id: UUID(), name: "Mo\u{0}at?", isChecked: false)]

    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)

    #expect(dto.name == "Apple")
    #expect(dto.memo == "ab")
    #expect(dto.checklist.first?.name == "Moat?")
    #expect(dto.checklist.first?.id.unicodeScalars.contains("\u{0}") == false)
  }

  @Test
  func stripsNulBeforeClampingSoNoUsableTextIsLost() {
    var item = makeItem("AAPL")
    item.memo = String(repeating: "\u{0}x", count: 6000) // 12,000 UTF-16 units, 6,000 once stripped
    #expect(SyncMapping.changeDTO(.upsert(item), now: .distantFuture).memo == String(repeating: "x", count: 6000))
  }

  @Test
  func recognisesAnchorsThatSurviveTheSixDecimalWireFormat() throws {
    #expect(SyncMapping.isRepresentable(.empty))
    #expect(SyncMapping.isRepresentable(try PriceLadder(buyLow: Decimal(string: "0.000001")!)))
    #expect(SyncMapping.isRepresentable(try PriceLadder(buyLow: Decimal(string: "0.0000005")!))) // rounds half up to 0.000001
    #expect(SyncMapping.isRepresentable(try PriceLadder(sell: Decimal(string: "999999999999.999999")!)))
    // These would go out as "0" (rejected: INVALID_LADDER) or as 13 integer digits (rejected: schema pattern).
    #expect(!SyncMapping.isRepresentable(try PriceLadder(buyLow: Decimal(string: "0.0000004")!)))
    #expect(!SyncMapping.isRepresentable(try PriceLadder(buyLow: 10, sell: Decimal(string: "1000000000000")!)))
    #expect(!SyncMapping.isRepresentable(try PriceLadder(sell: Decimal(string: "999999999999.9999996")!)))
  }

  @Test
  func dropsHistoryRevisionsThatCannotBeRepresentedOnTheWire() throws {
    var item = makeItem("AAPL")
    item.ladderHistory = [
      LadderRevision(date: stamp(1), ladder: try PriceLadder(buyHigh: Decimal(string: "0.0000004")!)),
      LadderRevision(date: stamp(2), ladder: try PriceLadder(buyHigh: 16)),
    ]
    let dto = SyncMapping.changeDTO(.upsert(item), now: .distantFuture)
    #expect(dto.ladderHistory == [LadderRevisionDTO(date: SyncStamp.string(from: stamp(2)), ladder: LadderDTO(buyHigh: "16"))])
  }

  @Test
  func mapsAServerRowBackToDomain() throws {
    let dto = WatchlistItemDTO(
      symbol: "AAPL", name: "Apple Inc.", ladder: LadderDTO(buyLow: "12", buyHigh: "16", fair: "23"), memo: "Wait",
      isFavorite: true, sortIndex: 2,
      checklist: [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)],
      ladderHistory: [
        LadderRevisionDTO(date: "2026-11-01T00:00:00.000Z", ladder: LadderDTO(buyHigh: "18")),
        LadderRevisionDTO(date: "not a date", ladder: LadderDTO(buyHigh: "18")),
      ],
      clientUpdatedAt: "2026-11-20T15:00:00.123Z", deleted: false, version: 7
    )

    let row = try SyncMapping.remote(dto)

    #expect(row.version == 7)
    #expect(!row.isDeleted)
    #expect(SyncStamp.milliseconds(row.stamp) == 1_795_186_800_123)
    #expect(row.item.ladder == (try PriceLadder(buyLow: 12, buyHigh: 16, fair: 23)))
    #expect(row.item.checklist.first?.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    #expect(row.item.ladderHistory.count == 1)
    #expect(row.item.createdAt == SyncStamp.date(from: "2026-11-01T00:00:00.000Z"))
  }

  @Test
  func rejectsAnUnreadableServerRow() {
    var dto = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("AAPL")), now: .distantFuture), version: 1)
    dto.ladder = LadderDTO(buyLow: "20", buyHigh: "10")
    #expect(throws: SyncMappingError.invalidLadder("AAPL")) { try SyncMapping.remote(dto) }
    dto.ladder = LadderDTO()
    dto.clientUpdatedAt = "yesterday"
    #expect(throws: SyncMappingError.invalidTimestamp("yesterday")) { try SyncMapping.remote(dto) }
  }
}
