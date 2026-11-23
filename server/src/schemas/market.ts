import { Type, type TSchema } from "@sinclair/typebox"
import { SymbolSchema } from "./common.js"

/** Null-first unions (overview §8.1): with coercion off, Ajv tries `null` before the value type. */
const Nullable = <T extends TSchema>(schema: T) => Type.Union([Type.Null(), schema])

// Every querystring field is a string schema, so nothing depends on Ajv coercion.
export const QuotesQuerySchema = Type.Object({ symbols: Type.String({ minLength: 1, maxLength: 600 }) })

export const QuoteSchema = Type.Object({
  symbol: Type.String(),
  price: Type.String(),
  previousClose: Nullable(Type.String()),
  open: Nullable(Type.String()),
  high: Nullable(Type.String()),
  low: Nullable(Type.String()),
  change: Nullable(Type.String()),
  changePercent: Nullable(Type.Number()),
  volume: Nullable(Type.Integer()),
  fiftyTwoWeekHigh: Nullable(Type.String()),
  fiftyTwoWeekLow: Nullable(Type.String()),
  asOf: Type.String(),
  source: Type.String(),
  stale: Type.Boolean(),
})

export const QuotesResponseSchema = Type.Object({ quotes: Type.Array(QuoteSchema), missing: Type.Array(Type.String()) })

export const ChartRangeSchema = Type.Union([Type.Literal("1D"), Type.Literal("1W"), Type.Literal("1M"), Type.Literal("1Y"), Type.Literal("5Y")])

export const HistoryQuerySchema = Type.Object({ symbol: SymbolSchema, range: ChartRangeSchema })

export const HistoryResponseSchema = Type.Object({
  symbol: Type.String(),
  range: ChartRangeSchema,
  points: Type.Array(Type.Object({ t: Type.String(), c: Type.String() })),
  source: Type.String(),
  asOf: Type.String(),
  stale: Type.Boolean(),
  delayedMinutes: Nullable(Type.Integer()),
})

/** The pattern means "contains a non-space character", so whitespace-only queries get 400. */
export const SearchQuerySchema = Type.Object({ q: Type.String({ minLength: 1, maxLength: 30, pattern: "\\S" }) })

export const SearchResponseSchema = Type.Object({
  results: Type.Array(Type.Object({ symbol: Type.String(), name: Type.String(), exchange: Nullable(Type.String()), type: Type.String() })),
})

export const ProfileQuerySchema = Type.Object({ symbol: SymbolSchema })

export const ProfileResponseSchema = Type.Object({
  symbol: Type.String(),
  name: Nullable(Type.String()),
  exchange: Nullable(Type.String()),
  industry: Nullable(Type.String()),
  logoUrl: Nullable(Type.String()),
  marketCap: Nullable(Type.String()),
  peRatio: Nullable(Type.Number()),
  pbRatio: Nullable(Type.Number()),
  dividendYield: Nullable(Type.Number()),
  roe: Nullable(Type.Number()),
  roa: Nullable(Type.Number()),
  profitMargin: Nullable(Type.Number()),
  fiftyTwoWeekHigh: Nullable(Type.String()),
  fiftyTwoWeekLow: Nullable(Type.String()),
  beta: Nullable(Type.Number()),
  asOf: Type.String(),
})
