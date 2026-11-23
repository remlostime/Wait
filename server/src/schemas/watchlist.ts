import { Type, type Static } from "@sinclair/typebox"
import type { WatchlistChange, WatchlistRow } from "../db/watchlistTypes.js"

/** Wider than the market-route symbol pattern on purpose (plan 05, deviation 1): legacy non-US symbols must never block sync. */
export const SYNC_SYMBOL_PATTERN = "^[A-Z0-9][A-Z0-9.-]{0,14}$"
const DECIMAL_PATTERN = "^(0|[1-9][0-9]{0,11})(\\.[0-9]{1,6})?$"
const ISO_TIMESTAMP_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?Z$"

// Null-first unions (overview §8.1): with plan 04's Ajv options null is never coerced, and listing Null first is a second safeguard.
const NullableDecimal = Type.Union([Type.Null(), Type.String({ pattern: DECIMAL_PATTERN })])
const IsoTimestamp = Type.String({ pattern: ISO_TIMESTAMP_PATTERN })

export const LadderSchema = Type.Object(
  {
    buyLow: Type.Optional(NullableDecimal),
    buyHigh: Type.Optional(NullableDecimal),
    fair: Type.Optional(NullableDecimal),
    trim: Type.Optional(NullableDecimal),
    sell: Type.Optional(NullableDecimal),
  },
  { additionalProperties: false },
)

export const ChecklistEntrySchema = Type.Object(
  { id: Type.String({ minLength: 1, maxLength: 64 }), name: Type.String(), isChecked: Type.Boolean() },
  { additionalProperties: false },
)

export const LadderHistoryEntrySchema = Type.Object({ date: IsoTimestamp, ladder: LadderSchema }, { additionalProperties: false })

// Size limits (memo, names, counts) are enforced by WatchlistSyncService, so the error names the symbol.
const itemFields = {
  symbol: Type.String({ pattern: SYNC_SYMBOL_PATTERN }),
  name: Type.String(),
  ladder: LadderSchema,
  memo: Type.String(),
  isFavorite: Type.Boolean(),
  sortIndex: Type.Integer({ minimum: -1_000_000, maximum: 1_000_000 }),
  checklist: Type.Array(ChecklistEntrySchema),
  ladderHistory: Type.Array(LadderHistoryEntrySchema),
  clientUpdatedAt: IsoTimestamp,
  deleted: Type.Boolean(),
}

export const WatchlistChangeSchema = Type.Object(itemFields, { additionalProperties: false })
export const WatchlistItemSchema = Type.Object({ ...itemFields, version: Type.Integer({ minimum: 0 }) })

export const SyncBodySchema = Type.Object(
  {
    cursor: Type.Optional(Type.Union([Type.Null(), Type.String({ maxLength: 64 })])),
    changes: Type.Array(WatchlistChangeSchema, { maxItems: 200 }),
  },
  { additionalProperties: false },
)
export const SyncResponseSchema = Type.Object({
  changes: Type.Array(WatchlistItemSchema),
  cursor: Type.String(),
  hasMore: Type.Boolean(),
})
export const WatchlistListResponseSchema = Type.Object({ items: Type.Array(WatchlistItemSchema), cursor: Type.String() })

export type WatchlistChangeDto = Static<typeof WatchlistChangeSchema>
export type WatchlistItemDto = Static<typeof WatchlistItemSchema>

export function toWatchlistChange(dto: WatchlistChangeDto): WatchlistChange {
  return {
    symbol: dto.symbol,
    name: dto.name,
    ladder: {
      buyLow: dto.ladder.buyLow ?? null,
      buyHigh: dto.ladder.buyHigh ?? null,
      fair: dto.ladder.fair ?? null,
      trim: dto.ladder.trim ?? null,
      sell: dto.ladder.sell ?? null,
    },
    memo: dto.memo,
    isFavorite: dto.isFavorite,
    sortIndex: dto.sortIndex,
    checklist: dto.checklist,
    ladderHistory: dto.ladderHistory,
    clientUpdatedAt: new Date(dto.clientUpdatedAt),
    deleted: dto.deleted,
  }
}

export function toWatchlistItemDto(row: WatchlistRow): WatchlistItemDto {
  return {
    symbol: row.symbol,
    name: row.name,
    ladder: row.ladder,
    memo: row.memo,
    isFavorite: row.isFavorite,
    sortIndex: row.sortIndex,
    checklist: row.checklist,
    ladderHistory: row.ladderHistory,
    clientUpdatedAt: row.clientUpdatedAt.toISOString(),
    deleted: row.deleted,
    version: row.version,
  }
}
