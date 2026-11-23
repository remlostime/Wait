import { describe, expect, it } from "vitest"
import { START_CURSOR, decodeCursor, encodeCursor, normalizeDecimal } from "../../src/db/watchlistTypes.js"

describe("sync cursor", () => {
  it("treats null, undefined and the empty string as the start cursor", () => {
    expect(decodeCursor(null)).toEqual(START_CURSOR)
    expect(decodeCursor(undefined)).toEqual(START_CURSOR)
    expect(decodeCursor("")).toEqual(START_CURSOR)
    expect(START_CURSOR).toEqual({ version: 0, symbol: "" })
  })

  it("round-trips version and symbol, including dotted symbols", () => {
    expect(decodeCursor(encodeCursor({ version: 12, symbol: "BRK.B" }))).toEqual({ version: 12, symbol: "BRK.B" })
    expect(encodeCursor({ version: 3, symbol: "AAPL" })).toBe("3:AAPL")
    expect(decodeCursor("0:")).toEqual({ version: 0, symbol: "" })
  })

  it("rejects malformed cursors", () => {
    for (const raw of ["AAPL", "-1:AAPL", "1.5:AAPL", "x:AAPL", "99999999999999999999:A", ":AAPL"]) {
      expect(decodeCursor(raw), raw).toBeNull()
    }
  })
})

describe("normalizeDecimal", () => {
  it("strips trailing zeros that NUMERIC(18,6) adds", () => {
    expect(normalizeDecimal("16.000000")).toBe("16")
    expect(normalizeDecimal("14.200000")).toBe("14.2")
    expect(normalizeDecimal("0.007500")).toBe("0.0075")
    expect(normalizeDecimal("120")).toBe("120")
    expect(normalizeDecimal(16.5)).toBe("16.5")
  })

  it("passes null and undefined through as null", () => {
    expect(normalizeDecimal(null)).toBeNull()
    expect(normalizeDecimal(undefined)).toBeNull()
  })
})
