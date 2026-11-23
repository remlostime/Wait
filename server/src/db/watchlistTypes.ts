import type { LadderInput } from "../domain/ladder.js"

/** Every rung is always present: a decimal string, or null when unset. */
export type LadderValues = {
  buyLow: string | null
  buyHigh: string | null
  fair: string | null
  trim: string | null
  sell: string | null
}

export type ChecklistEntry = { id: string; name: string; isChecked: boolean }

/** A history entry's ladder is stored exactly as the client sent it. */
export type LadderHistoryEntry = { date: string; ladder: LadderInput }

/** One item as the client pushes it. `deleted: true` is a tombstone. */
export type WatchlistChange = {
  symbol: string
  name: string
  ladder: LadderValues
  memo: string
  isFavorite: boolean
  sortIndex: number
  checklist: ChecklistEntry[]
  ladderHistory: LadderHistoryEntry[]
  clientUpdatedAt: Date
  deleted: boolean
}

/** A stored item. `lastStatus` and `lastEvaluatedPrice` are server-owned (written by the plan 06 alert job). */
export type WatchlistRow = WatchlistChange & {
  version: number
  lastStatus: string | null
  lastEvaluatedPrice: string | null
}

export type SyncCursor = { version: number; symbol: string }

export const START_CURSOR: SyncCursor = { version: 0, symbol: "" }

export function encodeCursor(cursor: SyncCursor): string {
  return `${cursor.version}:${cursor.symbol}`
}

/** `null`, `undefined` and `""` → start (the empty string is accepted defensively). Returns `null` for a malformed cursor. */
export function decodeCursor(raw: string | null | undefined): SyncCursor | null {
  if (raw === null || raw === undefined || raw === "") return START_CURSOR
  const separator = raw.indexOf(":")
  if (separator <= 0) return null
  const versionText = raw.slice(0, separator)
  if (!/^[0-9]{1,15}$/.test(versionText)) return null
  return { version: Number(versionText), symbol: raw.slice(separator + 1) }
}

/** NUMERIC(18,6) comes back as "16.000000". Normalize to the shortest decimal string ("16", "14.2"). */
export function normalizeDecimal(value: unknown): string | null {
  if (value === null || value === undefined) return null
  const text = String(value)
  if (!text.includes(".")) return text
  return text.replace(/0+$/, "").replace(/\.$/, "")
}

export function normalizeLadder(ladder: Partial<LadderValues>): LadderValues {
  return {
    buyLow: normalizeDecimal(ladder.buyLow),
    buyHigh: normalizeDecimal(ladder.buyHigh),
    fair: normalizeDecimal(ladder.fair),
    trim: normalizeDecimal(ladder.trim),
    sell: normalizeDecimal(ladder.sell),
  }
}
