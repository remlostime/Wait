import type { SyncCursor, WatchlistChange, WatchlistRow } from "./watchlistTypes.js"

export interface WatchlistRepository {
  /**
   * Upserts the changes in one statement under one new per-user version.
   * Last write wins on `clientUpdatedAt`. On a tie, the stored row wins.
   * Callers must dedupe symbols first (Postgres can't update the same row twice in one statement).
   * @returns the applied symbols, sorted.
   */
  push(userId: string, changes: WatchlistChange[], now: Date): Promise<string[]>
  /** Rows (tombstones included) with (version, symbol) > `after`, ordered by (version, symbol). */
  pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]>
  /** The current rows (tombstones included) for `symbols`, sorted by symbol. */
  findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]>
}
