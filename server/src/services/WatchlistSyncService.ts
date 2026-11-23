import type { WatchlistRepository } from "../db/WatchlistRepository.js"
import {
  START_CURSOR,
  decodeCursor,
  encodeCursor,
  type SyncCursor,
  type WatchlistChange,
  type WatchlistRow,
} from "../db/watchlistTypes.js"
import { validateLadder } from "../domain/ladder.js"
import { AppError } from "../lib/errors.js"

export const SYNC_PUSH_LIMIT = 200
export const SYNC_PULL_LIMIT = 500
export const LIST_LIMIT = 5_000
export const MAX_MEMO_LENGTH = 10_000
export const MAX_NAME_LENGTH = 500
export const MAX_CHECKLIST_ITEMS = 100
export const MAX_LADDER_HISTORY = 200
export const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000

export type SyncRequest = { cursor: string | null; changes: WatchlistChange[] }
export type SyncResult = { changes: WatchlistRow[]; cursor: string; hasMore: boolean }
export type ListResult = { items: WatchlistRow[]; cursor: string }

function invalidInput(message: string): AppError {
  return new AppError("INVALID_INPUT", message, 400)
}

function validateChange(change: WatchlistChange): void {
  const { symbol } = change
  const ladder = validateLadder(change.ladder)
  if (!ladder.ok) {
    const detail = ladder.kind === "nonPositive" ? `${ladder.rung} must be greater than 0` : `${ladder.lower} is above ${ladder.upper}`
    throw new AppError("INVALID_LADDER", `${symbol}: ${detail}`, 400)
  }
  if (change.name.length > MAX_NAME_LENGTH) throw invalidInput(`${symbol}: name is longer than ${MAX_NAME_LENGTH} characters`)
  if (change.memo.length > MAX_MEMO_LENGTH) throw invalidInput(`${symbol}: memo is longer than ${MAX_MEMO_LENGTH} characters`)
  if (change.checklist.length > MAX_CHECKLIST_ITEMS) {
    throw invalidInput(`${symbol}: checklist has more than ${MAX_CHECKLIST_ITEMS} items`)
  }
  if (change.checklist.some((entry) => entry.name.length > MAX_NAME_LENGTH)) {
    throw invalidInput(`${symbol}: checklist item name is longer than ${MAX_NAME_LENGTH} characters`)
  }
  if (change.ladderHistory.length > MAX_LADDER_HISTORY) {
    throw invalidInput(`${symbol}: ladderHistory has more than ${MAX_LADDER_HISTORY} entries`)
  }
  // The pattern only checks the shape: "2026-13-01T…" or year 0000 would otherwise reach toISOString()/Postgres as a 500.
  if (!isSaneTimestamp(change.clientUpdatedAt.getTime())) throw invalidInput(`${symbol}: clientUpdatedAt is not a valid timestamp`)
  if (change.ladderHistory.some((entry) => !isSaneTimestamp(Date.parse(entry.date)))) {
    throw invalidInput(`${symbol}: ladderHistory has an invalid date`)
  }
  // Postgres jsonb/text reject U+0000; a 500 here would make the client retry the batch forever.
  const texts = [change.name, change.memo, ...change.checklist.flatMap((entry) => [entry.id, entry.name])]
  if (texts.some((text) => text.includes("\u0000"))) throw invalidInput(`${symbol}: text fields must not contain NUL characters`)
}


function isSaneTimestamp(ms: number): boolean {
  return Number.isFinite(ms) && ms >= 0
}

function clamp(change: WatchlistChange, now: Date): WatchlistChange {
  const limit = now.getTime() + MAX_CLOCK_SKEW_MS
  return change.clientUpdatedAt.getTime() > limit ? { ...change, clientUpdatedAt: new Date(limit) } : change
}

/** One row per symbol; the latest clientUpdatedAt wins, and later entries win ties. */
function dedupeLatest(changes: WatchlistChange[]): WatchlistChange[] {
  const latest = new Map<string, WatchlistChange>()
  for (const change of changes) {
    const existing = latest.get(change.symbol)
    if (!existing || existing.clientUpdatedAt.getTime() <= change.clientUpdatedAt.getTime()) latest.set(change.symbol, change)
  }
  return [...latest.values()]
}

function cursorOf(row: WatchlistRow | undefined, fallback: SyncCursor): string {
  return encodeCursor(row ? { version: row.version, symbol: row.symbol } : fallback)
}

export class WatchlistSyncService {
  constructor(private readonly repository: WatchlistRepository) {}

  /** Overview §8.5, server steps 1–6. */
  async sync(userId: string, request: SyncRequest, now: Date): Promise<SyncResult> {
    const cursor = decodeCursor(request.cursor)
    if (!cursor) throw invalidInput("Invalid sync cursor")
    if (request.changes.length > SYNC_PUSH_LIMIT) throw invalidInput(`At most ${SYNC_PUSH_LIMIT} changes per request`)
    request.changes.forEach(validateChange)

    const changes = dedupeLatest(request.changes.map((change) => clamp(change, now)))
    const applied = new Set(await this.repository.push(userId, changes, now))
    const rejected = changes.map((change) => change.symbol).filter((symbol) => !applied.has(symbol))

    const pulled = await this.repository.pull(userId, cursor, SYNC_PULL_LIMIT)
    const pulledSymbols = new Set(pulled.map((row) => row.symbol))
    const current = rejected.length > 0 ? await this.repository.findBySymbols(userId, rejected) : []
    const extra = current.filter((row) => !pulledSymbols.has(row.symbol))

    return {
      changes: [...pulled, ...extra],
      cursor: cursorOf(pulled.at(-1), cursor),
      hasMore: pulled.length === SYNC_PULL_LIMIT,
    }
  }

  /** Pages through every row (tombstones included) so the returned cursor never skips anything. */
  async list(userId: string): Promise<ListResult> {
    const rows: WatchlistRow[] = []
    let cursor: SyncCursor = START_CURSOR
    for (;;) {
      const page = await this.repository.pull(userId, cursor, LIST_LIMIT)
      rows.push(...page)
      if (page.length < LIST_LIMIT) break
      cursor = { version: page[page.length - 1]!.version, symbol: page[page.length - 1]!.symbol }
    }
    return { items: rows.filter((row) => !row.deleted), cursor: cursorOf(rows.at(-1), START_CURSOR) }
  }
}
