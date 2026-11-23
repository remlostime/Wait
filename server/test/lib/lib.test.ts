import { describe, expect, it } from "vitest"
import { AppError } from "../../src/lib/errors.js"
import { safeEqual } from "../../src/lib/safeEqual.js"
import { fixedClock } from "../../src/lib/clock.js"
import { asDate, asNullableString, asNumber } from "../../src/lib/time.js"
import { toDecimalString } from "../../src/lib/decimal.js"
import { mapLimit } from "../../src/lib/concurrency.js"

describe("AppError", () => {
  it("carries code, status and optional Retry-After seconds", () => {
    const error = new AppError("UPSTREAM_RATE_LIMITED", "Try later", 503, 30)
    expect(error).toBeInstanceOf(Error)
    expect([error.code, error.statusCode, error.retryAfterSec]).toEqual(["UPSTREAM_RATE_LIMITED", 503, 30])
  })
})

describe("safeEqual", () => {
  it("compares strings of any length without throwing", () => {
    expect(safeEqual("secret", "secret")).toBe(true)
    expect(safeEqual("secret", "secreT")).toBe(false)
    expect(safeEqual("short", "a-much-longer-value")).toBe(false)
  })
})

describe("fixedClock", () => {
  it("returns copies of a settable, advanceable instant", () => {
    const clock = fixedClock(new Date("2026-11-20T15:00:00.000Z"))
    clock.advance(1_500)
    expect(clock.now().toISOString()).toBe("2026-11-20T15:00:01.500Z")
    clock.set(new Date("2026-01-01T00:00:00.000Z"))
    const a = clock.now()
    a.setUTCFullYear(1999)
    expect(clock.now().toISOString()).toBe("2026-01-01T00:00:00.000Z")
  })
})

describe("row helpers", () => {
  it("accept driver-specific shapes", () => {
    expect(asDate("2026-11-20T15:00:00.000Z").toISOString()).toBe("2026-11-20T15:00:00.000Z")
    expect(asDate(new Date(0)).getTime()).toBe(0)
    expect(asNumber("42")).toBe(42)
    expect(asNumber(42n)).toBe(42)
    expect(() => asDate("not a date")).toThrow(TypeError)
    expect(() => asNumber("abc")).toThrow(TypeError)
    expect(asNullableString(null)).toBeNull()
    expect(asNullableString(12.5)).toBe("12.5")
  })
})

describe("toDecimalString", () => {
  it("removes float artifacts and trailing zeros", () => {
    expect(toDecimalString(172.1)).toBe("172.1")
    expect(toDecimalString(0.1 + 0.2)).toBe("0.3")
    expect(toDecimalString(3_500_000_000_000)).toBe("3500000000000")
    expect(toDecimalString(0.0075)).toBe("0.0075")
  })
})

describe("mapLimit", () => {
  it("preserves order and never exceeds the concurrency limit", async () => {
    let active = 0
    let peak = 0
    const result = await mapLimit([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
      active += 1
      peak = Math.max(peak, active)
      await new Promise((resolve) => setTimeout(resolve, 5))
      active -= 1
      return n * 10
    })
    expect(result).toEqual([10, 20, 30, 40, 50, 60, 70])
    expect(peak).toBeLessThanOrEqual(3)
  })
})
