import { verify } from "node:crypto"
import { describe, expect, it } from "vitest"
import { ApnsTokenProvider, normalizeApnsKey } from "../../src/apns/ApnsTokenProvider.js"
import { fixedClock } from "../../src/lib/clock.js"
import { TEST_APNS_KEY_BASE64, TEST_APNS_PRIVATE_KEY_PEM, TEST_APNS_PUBLIC_KEY_PEM } from "../support/apnsKey.js"

const decode = (segment: string | undefined): unknown => JSON.parse(Buffer.from(segment ?? "", "base64url").toString("utf8"))
const issuedAt = (token: string): unknown => (decode(token.split(".")[1]) as { iat: number }).iat
const KEY = { key: TEST_APNS_KEY_BASE64, keyId: "ABC123DEFG", teamId: "5WDN96EM72" }

describe("ApnsTokenProvider", () => {
  it("signs an ES256 JWT with the key id, team id and issue time", () => {
    const provider = new ApnsTokenProvider(KEY, fixedClock(new Date("2026-11-20T22:00:00.000Z")))
    const [header, claims, signature] = provider.token().split(".")

    expect(decode(header)).toEqual({ alg: "ES256", kid: "ABC123DEFG" })
    expect(decode(claims)).toEqual({ iss: "5WDN96EM72", iat: 1795212000 })
    const raw = Buffer.from(signature ?? "", "base64url")
    expect(raw).toHaveLength(64) // raw r||s, not DER
    expect(verify("sha256", Buffer.from(`${header}.${claims}`), { key: TEST_APNS_PUBLIC_KEY_PEM, dsaEncoding: "ieee-p1363" }, raw)).toBe(true)
  })

  it("reuses the token for just under 50 minutes", () => {
    const clock = fixedClock(new Date("2026-11-20T22:00:00.000Z"))
    const provider = new ApnsTokenProvider(KEY, clock)
    const first = provider.token()
    clock.set(new Date("2026-11-20T22:49:59.000Z"))
    expect(provider.token()).toBe(first)
    clock.set(new Date("2026-11-20T22:50:00.000Z"))
    const second = provider.token()
    expect(second).not.toBe(first)
    expect(issuedAt(second)).toBe(1795215000)
  })

  it("issues a fresh token after invalidate()", () => {
    const clock = fixedClock(new Date("2026-11-20T22:00:00.000Z"))
    const provider = new ApnsTokenProvider(KEY, clock)
    const first = provider.token()
    clock.advance(5_000)
    provider.invalidate()
    const second = provider.token()
    expect(second).not.toBe(first)
    expect(issuedAt(second)).toBe(1795212005)
  })

  it("does not parse the key until the first token is needed", () => {
    const provider = new ApnsTokenProvider({ ...KEY, key: "not-a-key" }, fixedClock(new Date("2026-11-20T22:00:00.000Z")))
    expect(() => provider.token()).toThrow("APNS_KEY")
  })
})

describe("normalizeApnsKey", () => {
  const pem = TEST_APNS_PRIVATE_KEY_PEM.trim()

  it("keeps a raw PEM", () => {
    expect(normalizeApnsKey(TEST_APNS_PRIVATE_KEY_PEM)).toBe(pem)
  })

  it("turns literal \\n sequences into newlines", () => {
    expect(normalizeApnsKey(pem.replaceAll("\n", "\\n"))).toBe(pem)
  })

  it("decodes a base64-encoded PEM", () => {
    expect(normalizeApnsKey(TEST_APNS_KEY_BASE64)).toBe(pem)
  })

  it("rejects anything else", () => {
    expect(() => normalizeApnsKey("not-a-key")).toThrow("APNS_KEY")
  })
})
