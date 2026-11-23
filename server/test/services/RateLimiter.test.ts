import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { fixedClock, type FixedClock } from "../../src/lib/clock.js"
import { MockRateLimiter, PostgresRateLimiter, type BucketPolicy } from "../../src/services/RateLimiter.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

const TWO_PER_SECOND: BucketPolicy = { capacity: 2, refillPerSec: 1 }

describe("PostgresRateLimiter", () => {
  let db: TestDb
  let clock: FixedClock
  let limiter: PostgresRateLimiter

  beforeEach(async () => {
    db = await createTestDb()
    clock = fixedClock(new Date("2026-11-20T15:00:00.000Z"))
    limiter = new PostgresRateLimiter(db.sql, clock)
  })
  afterEach(async () => {
    await db.close()
  })

  it("allows up to capacity, then refills at the configured rate", async () => {
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
  })

  it("never refills above capacity", async () => {
    await limiter.tryTake("k", TWO_PER_SECOND)
    clock.advance(3_600_000)
    const results = [
      await limiter.tryTake("k", TWO_PER_SECOND),
      await limiter.tryTake("k", TWO_PER_SECOND),
      await limiter.tryTake("k", TWO_PER_SECOND),
    ]
    expect(results).toEqual([true, true, false])
  })

  it("keeps keys independent and honours cost", async () => {
    expect(await limiter.tryTake("a", TWO_PER_SECOND, 2)).toBe(true)
    expect(await limiter.tryTake("a", TWO_PER_SECOND)).toBe(false)
    expect(await limiter.tryTake("b", TWO_PER_SECOND)).toBe(true)
  })

  it("denies everything while blocked and only refills after the block ends", async () => {
    await limiter.block("k", 30)
    clock.advance(29_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000) // block over, but no tokens accrued during it
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(false)
    clock.advance(1_000)
    expect(await limiter.tryTake("k", TWO_PER_SECOND)).toBe(true)
  })

  it("reports the remaining block as Retry-After seconds", async () => {
    expect(await limiter.retryAfterSec("k")).toBeNull()
    await limiter.block("k", 30)
    clock.advance(10_500)
    expect(await limiter.retryAfterSec("k")).toBe(20)
    clock.advance(20_000)
    expect(await limiter.retryAfterSec("k")).toBeNull()
  })
})

describe("MockRateLimiter", () => {
  it("records takes and blocks and denies listed keys", async () => {
    const limiter = new MockRateLimiter()
    limiter.denied.add("no")
    expect(await limiter.tryTake("yes", TWO_PER_SECOND)).toBe(true)
    expect(await limiter.tryTake("no", TWO_PER_SECOND)).toBe(false)
    await limiter.block("yes", 10)
    expect(await limiter.tryTake("yes", TWO_PER_SECOND)).toBe(false)
    expect(await limiter.retryAfterSec("yes")).toBe(10)
    expect(await limiter.retryAfterSec("no")).toBeNull()
    expect(limiter.takes.map((t) => t.key)).toEqual(["yes", "no", "yes"])
    expect(limiter.blocks).toEqual([{ key: "yes", seconds: 10 }])
  })
})
