import { describe, expect, it } from "vitest"
import { etDateString, isMarketOpen, lastSessionOpen, nextClose, nextOpen } from "../../src/domain/marketCalendar.js"

const at = (iso: string) => new Date(iso)

describe("marketCalendar (America/New_York, Mon–Fri 09:30–16:00, no holiday table)", () => {
  it("formats the ET calendar date", () => {
    expect(etDateString(at("2026-11-21T03:00:00Z"))).toBe("2026-11-20") // Fri 22:00 EST
  })

  it("knows when the regular session is open", () => {
    expect(isMarketOpen(at("2026-11-20T15:00:00Z"))).toBe(true) // Fri 10:00 EST
    expect(isMarketOpen(at("2026-11-20T14:29:00Z"))).toBe(false) // 09:29
    expect(isMarketOpen(at("2026-11-20T21:00:00Z"))).toBe(false) // 16:00 is closed
    expect(isMarketOpen(at("2026-11-21T15:00:00Z"))).toBe(false) // Saturday
  })

  it("finds the next open across a weekend", () => {
    expect(nextOpen(at("2026-11-20T21:30:00Z")).toISOString()).toBe("2026-11-23T14:30:00.000Z")
  })

  it("handles the DST start (2026-03-08)", () => {
    expect(nextOpen(at("2026-03-06T22:00:00Z")).toISOString()).toBe("2026-03-09T13:30:00.000Z")
  })

  it("handles the DST end (2026-11-01)", () => {
    expect(nextClose(at("2026-10-30T12:00:00Z")).toISOString()).toBe("2026-10-30T20:00:00.000Z")
    expect(nextClose(at("2026-10-30T20:30:00Z")).toISOString()).toBe("2026-11-02T21:00:00.000Z")
  })

  it("finds the most recent session open at or before an instant", () => {
    expect(lastSessionOpen(at("2026-11-21T15:00:00Z")).toISOString()).toBe("2026-11-20T14:30:00.000Z") // Sat → Fri
    expect(lastSessionOpen(at("2026-11-20T14:00:00Z")).toISOString()).toBe("2026-11-19T14:30:00.000Z") // Fri 09:00 → Thu
    expect(lastSessionOpen(at("2026-11-20T14:30:00Z")).toISOString()).toBe("2026-11-20T14:30:00.000Z")
  })
})
