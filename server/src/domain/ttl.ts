import { isMarketOpen, lastSessionOpen, nextClose, nextOpen } from "./marketCalendar.js"

export type CacheKind = "quote" | "history1D" | "history1W" | "daily5y" | "search" | "profile" | "metrics"

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const plus = (date: Date, ms: number) => new Date(date.getTime() + ms)

/**
 * Closed-market expiry for quotes and intraday bars. Data fetched within 20 min of the close may still
 * miss the closing print (Alpaca serves nothing from the latest ~16 min), so it expires 20 min after the
 * close instead of surviving until the next open (e.g. a whole weekend).
 */
function closedExpiry(fetchedAt: Date): Date {
  const settled = plus(nextClose(lastSessionOpen(fetchedAt)), 20 * MINUTE)
  return fetchedAt.getTime() < settled.getTime() ? settled : nextOpen(fetchedAt)
}

/** When a cached value fetched at `fetchedAt` stops being fresh (overview §6.3 item 3). */
export function expiresAt(kind: CacheKind, fetchedAt: Date): Date {
  const open = isMarketOpen(fetchedAt)
  switch (kind) {
    case "quote":
      return open ? plus(fetchedAt, 3 * MINUTE) : closedExpiry(fetchedAt)
    case "history1D":
      return open ? plus(fetchedAt, 5 * MINUTE) : closedExpiry(fetchedAt)
    case "history1W":
      return open ? plus(fetchedAt, 15 * MINUTE) : closedExpiry(fetchedAt)
    case "daily5y":
      // "Next close + 2 h", measured so a fetch at 16:30 still refreshes at 18:00 the same day
      // (end-of-day bars publish shortly after the close).
      return plus(nextClose(plus(fetchedAt, -2 * HOUR)), 2 * HOUR)
    case "search":
    case "profile":
      return plus(fetchedAt, 7 * DAY)
    case "metrics":
      return plus(fetchedAt, DAY)
  }
}
