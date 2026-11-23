import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { describe, expect, it } from "vitest"
import {
  buildKnots,
  classifyStatus,
  derivedFair,
  temperature,
  temperatureBand,
  validateLadder,
  type LadderInput,
} from "../../src/domain/ladder.js"

type LadderRef = string | LadderInput
type Vectors = {
  version: number
  ladders: Record<string, LadderInput>
  validation: Array<{
    ladder: LadderRef
    valid: boolean
    error?: { kind: string; rung?: string; lower?: string; upper?: string }
  }>
  knots: Array<{ ladder: LadderRef; derivedFair?: number; knots: Array<[number, number]> }>
  evaluations: Array<{ ladder: LadderRef; price: string; temperature: number | null; band: string | null; status: string }>
}

// server/test/domain → repo root is three levels up.
const vectorsPath = fileURLToPath(new URL("../../../shared/ladder-test-vectors.json", import.meta.url))
const vectors = JSON.parse(readFileSync(vectorsPath, "utf8")) as Vectors

const TEMPERATURE_TOLERANCE = 0.05
const KNOT_TOLERANCE = 0.001

function resolveLadder(ref: LadderRef): LadderInput {
  if (typeof ref !== "string") return ref
  const ladder = vectors.ladders[ref]
  if (!ladder) throw new Error(`Unknown ladder "${ref}" in vectors`)
  return ladder
}

function label(ref: LadderRef): string {
  return typeof ref === "string" ? ref : JSON.stringify(ref)
}

function expectNear(actual: number, expected: number, tolerance: number) {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance)
}

describe("ladder vectors", () => {
  it("reads version 1 of the shared vectors", () => {
    expect(vectors.version).toBe(1)
  })

  describe("validateLadder", () => {
    for (const [index, vector] of vectors.validation.entries()) {
      it(`validation #${index} ${label(vector.ladder)}`, () => {
        const result = validateLadder(resolveLadder(vector.ladder))
        if (vector.valid) {
          expect(result).toEqual({ ok: true })
        } else {
          expect(result).toEqual({ ok: false, ...vector.error })
        }
      })
    }
  })

  describe("buildKnots and derivedFair", () => {
    for (const [index, vector] of vectors.knots.entries()) {
      it(`knots #${index} ${label(vector.ladder)}`, () => {
        const ladder = resolveLadder(vector.ladder)
        const knots = buildKnots(ladder)
        expect(knots).toHaveLength(vector.knots.length)
        vector.knots.forEach(([price, score], k) => {
          expectNear(knots[k]![0], price, KNOT_TOLERANCE)
          expectNear(knots[k]![1], score, KNOT_TOLERANCE)
        })
        if (vector.derivedFair !== undefined) {
          expectNear(derivedFair(ladder)!, vector.derivedFair, KNOT_TOLERANCE)
        }
      })
    }
  })

  describe("temperature, band and status", () => {
    for (const [index, vector] of vectors.evaluations.entries()) {
      it(`evaluation #${index} ${label(vector.ladder)} @ ${vector.price}`, () => {
        const ladder = resolveLadder(vector.ladder)
        const price = Number(vector.price)
        const actual = temperature(ladder, price)
        if (vector.temperature === null) {
          expect(actual).toBeNull()
        } else {
          expectNear(actual!, vector.temperature, TEMPERATURE_TOLERANCE)
          if (vector.band !== null) expect(temperatureBand(actual!)).toBe(vector.band)
        }
        expect(classifyStatus(ladder, price)).toBe(vector.status)
      })
    }
  })
})

describe("ladder edge cases", () => {
  it("rejects a non-numeric anchor as nonPositive", () => {
    expect(validateLadder({ buyHigh: "abc" })).toEqual({ ok: false, kind: "nonPositive", rung: "buyHigh" })
  })

  it("derives fair from buyLow when buyHigh is absent", () => {
    expectNear(derivedFair({ buyLow: "70" })!, 100, KNOT_TOLERANCE)
  })

  it("does not derive fair when any upper anchor is present", () => {
    expect(derivedFair({ buyHigh: "90", sell: "200" })).toBeNull()
  })

  it("treats null and missing anchors the same", () => {
    expect(buildKnots({ buyLow: null, buyHigh: "16", fair: null })).toEqual(buildKnots({ buyHigh: "16" }))
  })
})
