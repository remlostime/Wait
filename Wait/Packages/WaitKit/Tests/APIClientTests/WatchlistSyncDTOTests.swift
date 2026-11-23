//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

@testable import APIClient
import Foundation
import Testing

struct WatchlistSyncDTOTests {
  @Test
  func encodesNilCursorAndUnsetRungsAsExplicitNulls() throws {
    let request = SyncRequestDTO(
      cursor: nil,
      changes: [
        WatchlistChangeDTO(
          symbol: "AAPL", name: "Apple Inc.", ladder: LadderDTO(buyHigh: "175"), memo: "", isFavorite: true, sortIndex: 0,
          checklist: [ChecklistItemDTO(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Moat?", isChecked: true)],
          ladderHistory: [LadderRevisionDTO(date: "2026-11-01T00:00:00.000Z", ladder: LadderDTO(buyHigh: "180"))],
          clientUpdatedAt: "2026-11-20T15:00:00.000Z", deleted: false
        ),
      ]
    )
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
    let json = try #require(object as? [String: Any])
    #expect(json["cursor"] is NSNull)
    let change = try #require((json["changes"] as? [[String: Any]])?.first)
    let ladder = try #require(change["ladder"] as? [String: Any])
    #expect(Set(ladder.keys) == ["buyLow", "buyHigh", "fair", "trim", "sell"])
    #expect(ladder["buyHigh"] as? String == "175")
    #expect(ladder["buyLow"] is NSNull)
    #expect(change["clientUpdatedAt"] as? String == "2026-11-20T15:00:00.000Z")
    #expect(change["version"] == nil)
  }

  @Test
  func decodesAServerResponse() throws {
    let body = """
      {"changes":[{"symbol":"AAPL","name":"Apple Inc.","ladder":{"buyLow":null,"buyHigh":"175","fair":null,"trim":null,"sell":null},
      "memo":"Wait","isFavorite":true,"sortIndex":2,"checklist":[],"ladderHistory":[{"date":"2026-11-01T00:00:00.000Z","ladder":{"buyHigh":"180"}}],
      "clientUpdatedAt":"2026-11-20T15:00:00.000Z","deleted":false,"version":7}],"cursor":"7:AAPL","hasMore":false}
      """
    let response = try JSONDecoder().decode(SyncResponseDTO.self, from: Data(body.utf8))
    #expect(response.cursor == "7:AAPL")
    #expect(response.hasMore == false)
    #expect(response.changes.first?.version == 7)
    #expect(response.changes.first?.ladder == LadderDTO(buyHigh: "175"))
    #expect(response.changes.first?.ladderHistory.first?.ladder.buyHigh == "180")
  }
}
