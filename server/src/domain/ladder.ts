// Ladder math mirrored from the Swift `Domain` target (PriceLadder).
// Spec: docs/superpowers/plans/2026-11-22-wait-00-overview.md §7.1–§7.2.
// Anchors arrive as decimal strings and are compared as numbers. Server prices have ≤ 6 decimals,
// so double precision is exact enough for ordering, and temperatures carry a ±0.05 tolerance.

export const RUNGS = ["buyLow", "buyHigh", "fair", "trim", "sell"] as const
export type Rung = (typeof RUNGS)[number]

/** A ladder as it travels on the wire: each rung is a decimal string, null, or absent. */
export type LadderInput = Partial<Record<Rung, string | null>>

/** A knot is [price, score]. */
export type Knot = [price: number, score: number]

export const RUNG_SCORES: Readonly<Record<Rung, number>> = {
  buyLow: 10,
  buyHigh: 30,
  fair: 50,
  trim: 80,
  sell: 95,
}

export const LADDER_STATUSES = [
  "DEEP_BUY",
  "BUY_ZONE",
  "WATCH",
  "AT_OR_ABOVE_FAIR",
  "TRIM",
  "SELL",
  "NO_ANCHORS",
] as const
export type LadderStatus = (typeof LADDER_STATUSES)[number]

export type TemperatureBand = "freezing" | "cold" | "neutral" | "warm" | "hot"

export type LadderValidation =
  | { ok: true }
  | { ok: false; kind: "nonPositive"; rung: Rung }
  | { ok: false; kind: "outOfOrder"; lower: Rung; upper: Rung }

type Anchor = { rung: Rung; value: number }

const BOTTOM_TAIL_FACTOR = 0.5
const TOP_TAIL_FACTOR = 1.5

function anchorValue(ladder: LadderInput, rung: Rung): number | null {
  const raw = ladder[rung]
  return raw === undefined || raw === null ? null : Number(raw)
}

function presentAnchors(ladder: LadderInput): Anchor[] {
  const anchors: Anchor[] = []
  for (const rung of RUNGS) {
    const value = anchorValue(ladder, rung)
    if (value !== null) anchors.push({ rung, value })
  }
  return anchors
}

export function isEmptyLadder(ladder: LadderInput): boolean {
  return presentAnchors(ladder).length === 0
}

/** Every present anchor must be > 0. Present anchors must be non-decreasing in rung order; the first failing adjacent pair is reported. */
export function validateLadder(ladder: LadderInput): LadderValidation {
  const anchors = presentAnchors(ladder)
  for (const anchor of anchors) {
    if (!Number.isFinite(anchor.value) || anchor.value <= 0) {
      return { ok: false, kind: "nonPositive", rung: anchor.rung }
    }
  }
  for (let index = 1; index < anchors.length; index++) {
    const lower = anchors[index - 1]!
    const upper = anchors[index]!
    if (lower.value > upper.value) {
      return { ok: false, kind: "outOfOrder", lower: lower.rung, upper: upper.rung }
    }
  }
  return { ok: true }
}

/** (buyHigh ?? buyLow) × 10 / 7. Applies only when a buy band exists and fair, trim and sell are all absent. */
export function derivedFair(ladder: LadderInput): number | null {
  const buyLow = anchorValue(ladder, "buyLow")
  const buyHigh = anchorValue(ladder, "buyHigh")
  const hasBand = buyLow !== null || buyHigh !== null
  const hasUpper =
    anchorValue(ladder, "fair") !== null || anchorValue(ladder, "trim") !== null || anchorValue(ladder, "sell") !== null
  if (!hasBand || hasUpper) return null
  const top = buyHigh ?? buyLow!
  return (top * 10) / 7
}

export function effectiveFair(ladder: LadderInput): number | null {
  return anchorValue(ladder, "fair") ?? derivedFair(ladder)
}

/** The anchor knots (plus the derived fair), the 0.5× and 1.5× tails, stable-sorted by price. */
export function buildKnots(ladder: LadderInput): Knot[] {
  const knots: Knot[] = presentAnchors(ladder).map((anchor) => [anchor.value, RUNG_SCORES[anchor.rung]])
  const fair = derivedFair(ladder)
  if (fair !== null) knots.push([fair, RUNG_SCORES.fair])
  if (knots.length === 0) return []
  const prices = knots.map(([price]) => price)
  knots.push([Math.min(...prices) * BOTTOM_TAIL_FACTOR, 0], [Math.max(...prices) * TOP_TAIL_FACTOR, 100])
  return knots.sort((a, b) => a[0] - b[0])
}

/** Piecewise-linear and clamped. Uses the first segment that contains the price. Returns null for an empty ladder. */
export function temperature(ladder: LadderInput, price: number): number | null {
  const knots = buildKnots(ladder)
  if (knots.length === 0) return null
  const first = knots[0]!
  const last = knots[knots.length - 1]!
  if (price <= first[0]) return first[1]
  if (price >= last[0]) return last[1]
  for (let index = 0; index < knots.length - 1; index++) {
    const [x0, y0] = knots[index]!
    const [x1, y1] = knots[index + 1]!
    if (x0 <= price && price <= x1) {
      return x1 === x0 ? y0 : y0 + ((price - x0) / (x1 - x0)) * (y1 - y0)
    }
  }
  return last[1]
}

export function temperatureBand(value: number): TemperatureBand {
  if (value < 20) return "freezing"
  if (value < 40) return "cold"
  if (value < 60) return "neutral"
  if (value < 80) return "warm"
  return "hot"
}

/** Status from price vs anchors (overview §7.2 step 5). Independent of the temperature. */
export function classifyStatus(ladder: LadderInput, price: number): LadderStatus {
  if (isEmptyLadder(ladder)) return "NO_ANCHORS"
  const sell = anchorValue(ladder, "sell")
  const trim = anchorValue(ladder, "trim")
  const fair = effectiveFair(ladder)
  const buyLow = anchorValue(ladder, "buyLow")
  const buyHigh = anchorValue(ladder, "buyHigh")
  if (sell !== null && price >= sell) return "SELL"
  if (trim !== null && price >= trim) return "TRIM"
  if (fair !== null && price >= fair) return "AT_OR_ABOVE_FAIR"
  if (buyLow !== null && price <= buyLow) return "DEEP_BUY"
  if (buyHigh !== null && price <= buyHigh) return "BUY_ZONE"
  return "WATCH"
}

/** Statuses that can trigger a push (overview §7.3). */
export type AlertStatus = "DEEP_BUY" | "BUY_ZONE" | "TRIM" | "SELL"

const STATUS_RANK = {
  DEEP_BUY: 0,
  BUY_ZONE: 1,
  WATCH: 2,
  AT_OR_ABOVE_FAIR: 3,
  TRIM: 4,
  SELL: 5,
} as const satisfies Record<Exclude<LadderStatus, "NO_ANCHORS">, number>

const ALERT_STATUSES: readonly string[] = ["DEEP_BUY", "BUY_ZONE", "TRIM", "SELL"]

/** Parses a stored status string (reusing plan 05's `LADDER_STATUSES`); unknown values become null. */
export function parseLadderStatus(value: unknown): LadderStatus | null {
  return typeof value === "string" && (LADDER_STATUSES as readonly string[]).includes(value) ? (value as LadderStatus) : null
}

export function isAlertStatus(value: string): value is AlertStatus {
  return ALERT_STATUSES.includes(value)
}

/** DEEP_BUY = 0 … SELL = 5; NO_ANCHORS has no rank. */
export function statusRank(status: LadderStatus): number | null {
  return status === "NO_ANCHORS" ? null : STATUS_RANK[status]
}

/**
 * Directional alert rule: push only when moving *down* into DEEP_BUY/BUY_ZONE or *up* into TRIM/SELL.
 * A null previous status seeds silently.
 */
export function shouldAlert(previous: LadderStatus | null, next: LadderStatus): boolean {
  if (previous === null || previous === next) return false
  const previousRank = statusRank(previous)
  const nextRank = statusRank(next)
  if (previousRank === null || nextRank === null) return false
  if ((next === "DEEP_BUY" || next === "BUY_ZONE") && nextRank < previousRank) return true
  if ((next === "TRIM" || next === "SELL") && nextRank > previousRank) return true
  return false
}
