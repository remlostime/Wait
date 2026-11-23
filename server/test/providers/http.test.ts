import { describe, expect, it } from "vitest"
import { getJson, parseRetryAfter } from "../../src/providers/http.js"
import { ProviderError } from "../../src/providers/types.js"
import { fakeFetch, headerOf, json } from "../support/fakeFetch.js"

const always = (response: () => Response) => fakeFetch([{ match: () => true, respond: response }])

async function errorOf(promise: Promise<unknown>): Promise<ProviderError> {
  try {
    await promise
  } catch (error) {
    if (error instanceof ProviderError) return error
    throw error
  }
  throw new Error("expected a ProviderError")
}

describe("getJson", () => {
  it("parses JSON and sends the provider headers", async () => {
    const { fetch, calls } = always(() => json({ ok: true }))
    expect(await getJson(fetch, "https://example.test/x", { provider: "finnhub", headers: { "X-Key": "k" } })).toEqual({ ok: true })
    expect(headerOf(calls[0]?.init, "x-key")).toBe("k")
    expect(headerOf(calls[0]?.init, "accept")).toBe("application/json")
  })

  it("maps 429 to rate_limited with Retry-After seconds", async () => {
    const { fetch } = always(() => new Response("{}", { status: 429, headers: { "retry-after": "12" } }))
    const error = await errorOf(getJson(fetch, "https://example.test/x", { provider: "tiingo" }))
    expect([error.provider, error.kind, error.retryAfterSec]).toEqual(["tiingo", "rate_limited", 12])
  })

  it("maps 404, 5xx, bad JSON and timeouts", async () => {
    expect((await errorOf(getJson(always(() => new Response("{}", { status: 404 })).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("not_found")
    expect((await errorOf(getJson(always(() => new Response("{}", { status: 503 })).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("upstream")
    expect((await errorOf(getJson(always(() => new Response("<html>")).fetch, "https://e.test", { provider: "alpaca" }))).kind).toBe("bad_response")
    const timeout = async () => {
      throw Object.assign(new Error("The operation timed out"), { name: "TimeoutError" })
    }
    expect((await errorOf(getJson(timeout, "https://e.test", { provider: "alpaca" }))).kind).toBe("timeout")
  })
})

describe("parseRetryAfter", () => {
  it("accepts seconds and ignores garbage", () => {
    expect(parseRetryAfter("30")).toBe(30)
    expect(parseRetryAfter(null)).toBeUndefined()
    expect(parseRetryAfter("soon")).toBeUndefined()
  })
})
