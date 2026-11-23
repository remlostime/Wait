import { describe, expect, it } from "vitest"
import { buildPayload } from "../../src/apns/payload.js"
import type { LadderInput } from "../../src/domain/ladder.js"

const FULL: LadderInput = { buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260" }

describe("buildPayload", () => {
  it("renders the BUY_ZONE alert exactly (overview §8.7)", () => {
    const payload = buildPayload({
      symbol: "AAPL",
      status: "BUY_ZONE",
      price: "172.1",
      ladder: { buyLow: "150", buyHigh: "175", fair: "210", trim: null, sell: null },
      temperature: 27.4,
      tradingDate: "2026-11-20",
    })
    expect(payload.body).toBe(
      '{"aps":{"alert":{"title":"AAPL · BUY ZONE","body":"Closed $172.10, at or below buy-high $175.00 · 27°"},"sound":"default","thread-id":"AAPL"},"symbol":"AAPL","status":"BUY_ZONE","deepLink":"wait://stock/AAPL"}',
    )
    expect(payload.collapseId).toBe("AAPL-2026-11-20")
  })

  it.each([
    { status: "DEEP_BUY", price: "140", temperature: 8.2, title: "AAPL · DEEP BUY", body: "Closed $140.00, at or below buy-low $150.00 · 8°" },
    { status: "TRIM", price: "245.5", temperature: 82.6, title: "AAPL · TRIM", body: "Closed $245.50, at or above trim $240.00 · 83°" },
    { status: "SELL", price: "261", temperature: null, title: "AAPL · SELL", body: "Closed $261.00, at or above sell $260.00" },
  ] as const)("describes $status against its rung", ({ status, price, temperature, title, body }) => {
    const parsed = JSON.parse(buildPayload({ symbol: "AAPL", status, price, ladder: FULL, temperature, tradingDate: "2026-11-20" }).body) as {
      aps: { alert: { title: string; body: string } }
    }
    expect(parsed.aps.alert).toEqual({ title, body })
  })

  it("falls back to the price alone when the rung is missing", () => {
    const parsed = JSON.parse(
      buildPayload({ symbol: "AAPL", status: "BUY_ZONE", price: "100", ladder: { ...FULL, buyHigh: null }, temperature: 30, tradingDate: "2026-11-20" }).body,
    ) as { aps: { alert: { body: string } } }
    expect(parsed.aps.alert.body).toBe("Closed $100.00 · 30°")
  })

  it("stays far below the 4 KB APNs payload limit", () => {
    const payload = buildPayload({ symbol: "BRK.B", status: "SELL", price: "481.25", ladder: FULL, temperature: 99.9, tradingDate: "2026-11-20" })
    expect(Buffer.byteLength(payload.body)).toBeLessThan(4096)
    expect(payload.collapseId).toBe("BRK.B-2026-11-20")
  })
})
