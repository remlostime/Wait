/** Neon returns timestamptz as Date or string depending on driver path; PGlite returns Date. */
export function asDate(value: unknown): Date {
  if (value instanceof Date) return new Date(value.getTime())
  if (typeof value === "string" || typeof value === "number") return new Date(value)
  throw new TypeError(`Expected a timestamp, got ${typeof value}`)
}

export function asNullableDate(value: unknown): Date | null {
  return value === null || value === undefined ? null : asDate(value)
}

/** BIGINT/NUMERIC come back as string (Neon) or number/bigint (PGlite). */
export function asNumber(value: unknown): number {
  if (typeof value === "number") return value
  if (typeof value === "bigint") return Number(value)
  if (typeof value === "string") return Number(value)
  throw new TypeError(`Expected a number, got ${typeof value}`)
}

export function asNullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value)
}
