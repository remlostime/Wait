import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { isAlertStatus, parseLadderStatus, shouldAlert, statusRank, type LadderStatus } from "../../src/domain/ladder.js"

type AlertVector = { previous: LadderStatus | null; next: LadderStatus; alert: boolean }

const vectors = JSON.parse(
  readFileSync(new URL("../../../shared/ladder-test-vectors.json", import.meta.url), "utf8"),
) as { alerts: AlertVector[] }

describe("shouldAlert (shared vectors)", () => {
  it("has the alert vectors from the overview", () => {
    expect(vectors.alerts.length).toBeGreaterThanOrEqual(11)
  })

  it.each(vectors.alerts)("$previous -> $next alerts: $alert", ({ previous, next, alert }) => {
    expect(shouldAlert(previous, next)).toBe(alert)
  })
})

describe("shouldAlert edge cases", () => {
  it("never alerts into or out of NO_ANCHORS", () => {
    expect(shouldAlert("NO_ANCHORS", "BUY_ZONE")).toBe(false)
    expect(shouldAlert("WATCH", "NO_ANCHORS")).toBe(false)
  })

  it("alerts on a crash straight from SELL to DEEP_BUY", () => {
    expect(shouldAlert("SELL", "DEEP_BUY")).toBe(true)
  })

  it("stays quiet when falling from SELL to AT_OR_ABOVE_FAIR", () => {
    expect(shouldAlert("SELL", "AT_OR_ABOVE_FAIR")).toBe(false)
  })
})

describe("statusRank", () => {
  it("orders statuses from cheapest to richest", () => {
    const order: LadderStatus[] = ["DEEP_BUY", "BUY_ZONE", "WATCH", "AT_OR_ABOVE_FAIR", "TRIM", "SELL"]
    expect(order.map((status) => statusRank(status))).toEqual([0, 1, 2, 3, 4, 5])
    expect(statusRank("NO_ANCHORS")).toBeNull()
  })
})

describe("parseLadderStatus / isAlertStatus", () => {
  it("accepts only known status strings", () => {
    expect(parseLadderStatus("BUY_ZONE")).toBe("BUY_ZONE")
    expect(parseLadderStatus("buy_zone")).toBeNull()
    expect(parseLadderStatus(null)).toBeNull()
    expect(parseLadderStatus(7)).toBeNull()
  })

  it("treats only the four push-worthy statuses as alert statuses", () => {
    expect(["DEEP_BUY", "BUY_ZONE", "TRIM", "SELL"].every((status) => isAlertStatus(status))).toBe(true)
    expect(["WATCH", "AT_OR_ABOVE_FAIR", "NO_ANCHORS"].some((status) => isAlertStatus(status))).toBe(false)
  })
})
