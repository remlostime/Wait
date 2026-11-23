import type { Sql } from "../db/sql.js"
import type { Clock } from "../lib/clock.js"

export interface BucketPolicy {
  capacity: number
  refillPerSec: number
}

/** Provider budgets (overview §6.3 item 4). Keys are stable: they are rows in rate_buckets. */
export const PROVIDER_BUCKETS = {
  finnhub: { key: "provider:finnhub", policy: { capacity: 30, refillPerSec: 1 } },
  tiingoHour: { key: "provider:tiingo:hour", policy: { capacity: 50, refillPerSec: 50 / 3600 } },
  tiingoDay: { key: "provider:tiingo:day", policy: { capacity: 1000, refillPerSec: 1000 / 86_400 } },
  alpaca: { key: "provider:alpaca", policy: { capacity: 100, refillPerSec: 200 / 60 } },
  massive: { key: "provider:massive", policy: { capacity: 5, refillPerSec: 5 / 60 } },
} as const satisfies Record<string, { key: string; policy: BucketPolicy }>

export const REGISTER_IP_POLICY: BucketPolicy = { capacity: 20, refillPerSec: 20 / 60 }
export const REGISTER_ANON_POLICY: BucketPolicy = { capacity: 5, refillPerSec: 5 / 60 }

export interface RateLimiter {
  /** Atomically refills and takes `cost` tokens. False when empty or blocked. */
  tryTake(key: string, policy: BucketPolicy, cost?: number): Promise<boolean>
  /** Empties the bucket and denies every take for `seconds` (used after a provider 429). */
  block(key: string, seconds: number): Promise<void>
  /** Seconds until a block on `key` ends, or null when it isn't blocked. Optional for simple fakes. */
  retryAfterSec?(key: string): Promise<number | null>
}

export class PostgresRateLimiter implements RateLimiter {
  constructor(
    private readonly sql: Sql,
    private readonly clock: Clock,
  ) {}

  async tryTake(key: string, policy: BucketPolicy, cost = 1): Promise<boolean> {
    const now = this.clock.now()
    const rows = await this.sql`
      INSERT INTO rate_buckets AS b (key, tokens, updated_at)
      VALUES (${key}, ${policy.capacity}::float8 - ${cost}::float8, ${now}::timestamptz)
      ON CONFLICT (key) DO UPDATE SET
        tokens = LEAST(${policy.capacity}::float8,
                       b.tokens + EXTRACT(EPOCH FROM (${now}::timestamptz - b.updated_at))::float8 * ${policy.refillPerSec}::float8)
                 - ${cost}::float8,
        updated_at = ${now}::timestamptz
      WHERE (b.blocked_until IS NULL OR b.blocked_until <= ${now}::timestamptz)
        AND LEAST(${policy.capacity}::float8,
                  b.tokens + EXTRACT(EPOCH FROM (${now}::timestamptz - b.updated_at))::float8 * ${policy.refillPerSec}::float8)
            >= ${cost}::float8
      RETURNING tokens`
    return rows.length > 0
  }

  async block(key: string, seconds: number): Promise<void> {
    const until = new Date(this.clock.now().getTime() + seconds * 1000)
    // updated_at = until: the refill clock starts when the block ends, so no tokens accrue during it.
    await this.sql`
      INSERT INTO rate_buckets (key, tokens, updated_at, blocked_until)
      VALUES (${key}, 0, ${until}::timestamptz, ${until}::timestamptz)
      ON CONFLICT (key) DO UPDATE SET tokens = 0, updated_at = EXCLUDED.updated_at, blocked_until = EXCLUDED.blocked_until`
  }

  async retryAfterSec(key: string): Promise<number | null> {
    const now = this.clock.now()
    const rows = await this.sql`
      SELECT CEIL(EXTRACT(EPOCH FROM (blocked_until - ${now}::timestamptz)))::int AS seconds
      FROM rate_buckets WHERE key = ${key} AND blocked_until > ${now}::timestamptz`
    return rows[0] ? Number(rows[0].seconds) : null
  }
}

export class MockRateLimiter implements RateLimiter {
  readonly denied = new Set<string>()
  readonly takes: Array<{ key: string; cost: number }> = []
  readonly blocks: Array<{ key: string; seconds: number }> = []
  /** Blocks never expire in the mock; tests assert on `blocks` and `retryAfterSec`. */
  private readonly blocked = new Map<string, number>()

  async tryTake(key: string, _policy: BucketPolicy, cost = 1): Promise<boolean> {
    this.takes.push({ key, cost })
    return !this.denied.has(key) && !this.blocked.has(key)
  }

  async block(key: string, seconds: number): Promise<void> {
    this.blocks.push({ key, seconds })
    this.blocked.set(key, seconds)
  }

  async retryAfterSec(key: string): Promise<number | null> {
    return this.blocked.get(key) ?? null
  }
}
