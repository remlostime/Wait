import { describe, expect, it } from "vitest"
import { easternDate, isWeekend } from "../../src/domain/tradingDate.js"

describe("easternDate", () => {
  it.each([
    { instant: "2026-11-20T22:00:00.000Z", expected: "2026-11-20", note: "Fri 5pm EST, the cron time" },
    { instant: "2026-07-10T22:00:00.000Z", expected: "2026-07-10", note: "Fri 6pm EDT" },
    { instant: "2026-11-21T04:30:00.000Z", expected: "2026-11-20", note: "Fri 11:30pm EST" },
    { instant: "2026-03-08T04:30:00.000Z", expected: "2026-03-07", note: "Sat 11:30pm EST, before DST starts" },
    { instant: "2026-03-08T07:30:00.000Z", expected: "2026-03-08", note: "Sun 3:30am EDT, after DST starts" },
    { instant: "2026-11-01T03:59:00.000Z", expected: "2026-10-31", note: "Sat 11:59pm EDT, before DST ends" },
    { instant: "2026-11-01T06:30:00.000Z", expected: "2026-11-01", note: "Sun 1:30am EST, after DST ends" },
  ])("$instant is $expected in New York ($note)", ({ instant, expected }) => {
    expect(easternDate(new Date(instant))).toBe(expected)
  })
})

describe("isWeekend", () => {
  it.each([
    { date: "2026-11-20", weekend: false },
    { date: "2026-11-21", weekend: true },
    { date: "2026-11-22", weekend: true },
    { date: "2026-11-23", weekend: false },
    { date: "2026-11-26", weekend: false }, // Thanksgiving is a weekday; DailyCloseResolver detects holidays
  ])("$date weekend: $weekend", ({ date, weekend }) => {
    expect(isWeekend(date)).toBe(weekend)
  })
})
