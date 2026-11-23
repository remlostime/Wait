import { describe, expect, it } from "vitest"
import { expiresAt } from "../../src/domain/ttl.js"

const iso = (kind: Parameters<typeof expiresAt>[0], fetched: string) => expiresAt(kind, new Date(fetched)).toISOString()

describe("server cache TTLs (overview §6.3 item 3)", () => {
  it("quotes live 3 min while open, until the next open while closed", () => {
    expect(iso("quote", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:03:00.000Z")
    expect(iso("quote", "2026-11-20T22:00:00.000Z")).toBe("2026-11-23T14:30:00.000Z")
  })

  it("intraday history lives 5 min (1D) / 15 min (1W) while open", () => {
    expect(iso("history1D", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:05:00.000Z")
    expect(iso("history1W", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T15:15:00.000Z")
    expect(iso("history1W", "2026-11-21T15:00:00.000Z")).toBe("2026-11-23T14:30:00.000Z")
  })

  it("daily5y refreshes two hours after the session close it belongs to", () => {
    expect(iso("daily5y", "2026-11-20T15:00:00.000Z")).toBe("2026-11-20T23:00:00.000Z") // Fri 10:00 → Fri 18:00 EST
    expect(iso("daily5y", "2026-11-20T21:30:00.000Z")).toBe("2026-11-20T23:00:00.000Z") // Fri 16:30 → same
    expect(iso("daily5y", "2026-11-21T00:00:00.000Z")).toBe("2026-11-23T23:00:00.000Z") // Fri 19:00 → Mon 18:00
  })

  it("search and profile live 7 days, metrics 1 day", () => {
    expect(iso("search", "2026-11-20T15:00:00.000Z")).toBe("2026-11-27T15:00:00.000Z")
    expect(iso("profile", "2026-11-20T15:00:00.000Z")).toBe("2026-11-27T15:00:00.000Z")
    expect(iso("metrics", "2026-11-20T15:00:00.000Z")).toBe("2026-11-21T15:00:00.000Z")
  })
})
