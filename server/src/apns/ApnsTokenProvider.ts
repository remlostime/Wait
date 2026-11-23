import { createPrivateKey, sign, type KeyObject } from "node:crypto"
import type { Clock } from "../lib/clock.js"

export type ApnsKeyConfig = { key: string; keyId: string; teamId: string }

/** Apple accepts provider tokens for 20–60 minutes; refresh well inside that window. */
export const APNS_TOKEN_MAX_AGE_MS = 50 * 60 * 1000

/** Accepts a raw PEM, a PEM with literal "\n" sequences (env vars), or a base64-encoded PEM. */
export function normalizeApnsKey(raw: string): string {
  const pem = raw.includes("-----BEGIN") ? raw : Buffer.from(raw.trim(), "base64").toString("utf8")
  if (!pem.includes("-----BEGIN") || !pem.includes("PRIVATE KEY-----")) {
    throw new Error("APNS_KEY must be a PEM private key or a base64-encoded PEM")
  }
  return pem.replaceAll("\\n", "\n").trim()
}

/**
 * ES256 provider token for APNs. The key is parsed on the first `token()` call, never in the constructor,
 * so a malformed APNS_KEY breaks only push delivery, not the cold start of every other route.
 */
export class ApnsTokenProvider {
  private readonly config: ApnsKeyConfig
  private readonly clock: Clock
  private readonly maxAgeMs: number
  private privateKey: KeyObject | null = null
  private cached: { token: string; issuedAtMs: number } | null = null

  constructor(config: ApnsKeyConfig, clock: Clock, maxAgeMs: number = APNS_TOKEN_MAX_AGE_MS) {
    this.config = config
    this.clock = clock
    this.maxAgeMs = maxAgeMs
  }

  /** `<header>.<claims>.<signature>`, cached for up to `maxAgeMs`. */
  token(): string {
    const nowMs = this.clock.now().getTime()
    if (this.cached !== null && nowMs - this.cached.issuedAtMs < this.maxAgeMs) return this.cached.token

    this.privateKey ??= createPrivateKey(normalizeApnsKey(this.config.key))
    const input = `${base64url({ alg: "ES256", kid: this.config.keyId })}.${base64url({ iss: this.config.teamId, iat: Math.floor(nowMs / 1000) })}`
    const signature = sign("sha256", Buffer.from(input), { key: this.privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")
    const token = `${input}.${signature}`
    this.cached = { token, issuedAtMs: nowMs }
    return token
  }

  /** Call after APNs answers 403 ExpiredProviderToken. */
  invalidate(): void {
    this.cached = null
  }
}

function base64url(value: object): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url")
}
