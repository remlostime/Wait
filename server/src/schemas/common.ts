import { Type, type Static } from "@sinclair/typebox"

export const ErrorResponseSchema = Type.Object({
  error: Type.Object({ code: Type.String(), message: Type.String() }),
})
export type ErrorResponse = Static<typeof ErrorResponseSchema>

/** US tickers like AAPL, BRK.B, BF-B (overview §8.4). */
export const SYMBOL_PATTERN = "^[A-Z]{1,5}([.-][A-Z]{1,2})?$"
export const SYMBOL_REGEX = new RegExp(SYMBOL_PATTERN)
export const SymbolSchema = Type.String({ pattern: SYMBOL_PATTERN })
