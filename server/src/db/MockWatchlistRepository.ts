import type { WatchlistRepository } from "./WatchlistRepository.js"
import { normalizeLadder, type LadderValues, type SyncCursor, type WatchlistChange, type WatchlistRow } from "./watchlistTypes.js"

const RUNG_KEYS: Array<keyof LadderValues> = ["buyLow", "buyHigh", "fair", "trim", "sell"]

function sameAnchors(a: LadderValues, b: LadderValues): boolean {
  return RUNG_KEYS.every((key) => {
    const left = a[key]
    const right = b[key]
    if (left === null || right === null) return left === right
    return Number(left) === Number(right)
  })
}

function isAfter(row: WatchlistRow, cursor: SyncCursor): boolean {
  return row.version > cursor.version || (row.version === cursor.version && row.symbol > cursor.symbol)
}

function byVersionThenSymbol(a: WatchlistRow, b: WatchlistRow): number {
  return a.version - b.version || (a.symbol < b.symbol ? -1 : a.symbol > b.symbol ? 1 : 0)
}

/** In-memory twin of NeonWatchlistRepository, for service and route tests. It must pass the same contract suite. */
export class MockWatchlistRepository implements WatchlistRepository {
  private readonly versions = new Map<string, number>()
  private readonly rows = new Map<string, WatchlistRow>()

  seedUser(userId: string): void {
    if (!this.versions.has(userId)) this.versions.set(userId, 0)
  }

  setLastStatus(userId: string, symbol: string, status: string | null): void {
    const row = this.rows.get(this.key(userId, symbol))
    if (row) this.rows.set(this.key(userId, symbol), { ...row, lastStatus: status })
  }

  clear(): void {
    this.versions.clear()
    this.rows.clear()
  }

  async push(userId: string, changes: WatchlistChange[], _now: Date): Promise<string[]> {
    if (changes.length === 0) return []
    const current = this.versions.get(userId)
    if (current === undefined) return []
    const version = current + 1
    this.versions.set(userId, version)
    const applied: string[] = []
    for (const change of changes) {
      const key = this.key(userId, change.symbol)
      const existing = this.rows.get(key)
      if (existing && existing.clientUpdatedAt.getTime() >= change.clientUpdatedAt.getTime()) continue
      const ladder = normalizeLadder(change.ladder)
      const keepStatus = existing !== undefined && sameAnchors(existing.ladder, ladder)
      this.rows.set(key, {
        ...change,
        ladder,
        checklist: structuredClone(change.checklist),
        ladderHistory: structuredClone(change.ladderHistory),
        version,
        lastStatus: keepStatus ? existing.lastStatus : null,
        lastEvaluatedPrice: existing?.lastEvaluatedPrice ?? null,
      })
      applied.push(change.symbol)
    }
    return applied.sort()
  }

  async pull(userId: string, after: SyncCursor, limit: number): Promise<WatchlistRow[]> {
    return this.rowsFor(userId)
      .filter((row) => isAfter(row, after))
      .sort(byVersionThenSymbol)
      .slice(0, limit)
  }

  async findBySymbols(userId: string, symbols: string[]): Promise<WatchlistRow[]> {
    const wanted = new Set(symbols)
    return this.rowsFor(userId)
      .filter((row) => wanted.has(row.symbol))
      .sort((a, b) => (a.symbol < b.symbol ? -1 : 1))
  }

  private key(userId: string, symbol: string): string {
    return `${userId}\u0000${symbol}`
  }

  private rowsFor(userId: string): WatchlistRow[] {
    const prefix = `${userId}\u0000`
    return [...this.rows.entries()].filter(([key]) => key.startsWith(prefix)).map(([, row]) => row)
  }
}
