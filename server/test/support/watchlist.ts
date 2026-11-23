import type { WatchlistChange } from "../../src/db/watchlistTypes.js"

export const T0 = new Date("2026-11-20T15:00:00.000Z")

/** Returns T0 shifted by `ms` milliseconds. */
export function at(ms: number): Date {
  return new Date(T0.getTime() + ms)
}

export function makeChange(overrides: Partial<WatchlistChange> & { symbol: string }): WatchlistChange {
  return {
    name: `${overrides.symbol} Inc.`,
    ladder: { buyLow: null, buyHigh: "100", fair: null, trim: null, sell: null },
    memo: "",
    isFavorite: false,
    sortIndex: 0,
    checklist: [],
    ladderHistory: [],
    clientUpdatedAt: T0,
    deleted: false,
    ...overrides,
  }
}
