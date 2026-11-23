/** Wire prices are decimal strings (overview D20). Rounds to `scale` places and drops float noise. */
export function toDecimalString(value: number, scale = 6): string {
  if (!Number.isFinite(value)) throw new RangeError(`Not a finite number: ${value}`)
  return String(Number(value.toFixed(scale)))
}

export function nullableDecimal(value: number | null | undefined, scale = 6): string | null {
  return value === null || value === undefined || !Number.isFinite(value) ? null : toDecimalString(value, scale)
}
