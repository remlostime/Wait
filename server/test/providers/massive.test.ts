import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"
import { createMassiveProvider } from "../../src/providers/massive.js"

const fixture = (name: string): string => readFileSync(new URL(`../support/fixtures/massive/${name}`, import.meta.url), "utf8")

type Call = { url: string; init: RequestInit | undefined }

function fakeFetch(respond: () => Response | Promise<Response>) {
  const calls: Call[] = []
  const impl = async (url: string, init?: RequestInit): Promise<Response> => {
    calls.push({ url, init })
    return respond()
  }
  return { calls, impl }
}

const json = (body: string, status = 200, headers: Record<string, string> = {}) =>
  new Response(body, { status, headers: { "content-type": "application/json", ...headers } })

describe("createMassiveProvider", () => {
  it("requests grouped daily bars with a bearer token and maps closes", async () => {
    const fake = fakeFetch(() => json(fixture("grouped-2026-11-20.json")))
    const provider = createMassiveProvider({ apiKey: "test-key", baseUrl: "https://api.massive.com/", fetchImpl: fake.impl })

    const closes = await provider.getGroupedDaily("2026-11-20")

    expect(fake.calls).toHaveLength(1)
    expect(fake.calls[0]?.url).toBe("https://api.massive.com/v2/aggs/grouped/locale/us/market/stocks/2026-11-20?adjusted=true")
    expect(fake.calls[0]?.url).not.toContain("test-key")
    expect(new Headers(fake.calls[0]?.init?.headers).get("authorization")).toBe("Bearer test-key")
    expect([...closes.keys()]).toEqual(["AAPL", "NVDA", "BRK.B"])
    expect(closes.get("AAPL")).toEqual({ symbol: "AAPL", close: "172.1", at: new Date("2026-11-20T21:00:00.000Z") })
    expect(closes.get("NVDA")?.close).toBe("185")
  })

  it("returns an empty map when the day has no results", async () => {
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json(fixture("grouped-empty.json"))).impl })
    expect((await provider.getGroupedDaily("2026-11-26")).size).toBe(0)
  })

  it("skips malformed rows", async () => {
    const body = JSON.stringify({ results: [null, 7, { T: "AAPL", c: 172.1, t: 1795208400000 }, { T: "MSFT", t: 1795208400000 }, { T: "TSLA", c: "30", t: 1795208400000 }] })
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json(body)).impl })
    expect([...(await provider.getGroupedDaily("2026-11-20")).keys()]).toEqual(["AAPL"])
  })

  it("maps 429 to rate_limited with Retry-After", async () => {
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("{}", 429, { "retry-after": "30" })).impl })
    await expect(provider.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ provider: "massive", kind: "rate_limited", retryAfterSec: 30 })
  })

  it("maps 5xx to upstream and other non-OK responses to bad_response", async () => {
    const upstream = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("{}", 502)).impl })
    await expect(upstream.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "upstream" })
    const forbidden = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json('{"status":"NOT_AUTHORIZED"}', 403)).impl })
    await expect(forbidden.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "bad_response" })
  })

  it("maps a network failure to upstream", async () => {
    const provider = createMassiveProvider({
      apiKey: "k",
      baseUrl: "https://api.massive.com",
      fetchImpl: fakeFetch(() => Promise.reject(new TypeError("fetch failed"))).impl,
    })
    await expect(provider.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "upstream" })
  })

  it("maps a failed body read to timeout/upstream and an unparsable body to bad_response", async () => {
    const failingBody = (name: string) => {
      const response = json("{}")
      Object.defineProperty(response, "text", { value: () => Promise.reject(Object.assign(new Error("body failed"), { name })) })
      return response
    }
    const timedOut = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => failingBody("TimeoutError")).impl })
    await expect(timedOut.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "timeout" })
    const reset = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => failingBody("TypeError")).impl })
    await expect(reset.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "upstream" })
    const garbage = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("<html>")).impl })
    await expect(garbage.getGroupedDaily("2026-11-20")).rejects.toMatchObject({ kind: "bad_response" })
  })

  it("never puts the key in a ProviderError message", async () => {
    const provider = createMassiveProvider({ apiKey: "secret-key-123", baseUrl: "https://api.massive.com", fetchImpl: fakeFetch(() => json("{}", 403)).impl })
    const error = await provider.getGroupedDaily("2026-11-20").catch((caught: unknown) => caught)
    expect(String((error as Error).message)).not.toContain("secret-key-123")
  })

  it("rejects a malformed trading date before calling the network", async () => {
    const fake = fakeFetch(() => json("{}"))
    const provider = createMassiveProvider({ apiKey: "k", baseUrl: "https://api.massive.com", fetchImpl: fake.impl })
    await expect(provider.getGroupedDaily("2026/11/20")).rejects.toThrow("Invalid trading date")
    expect(fake.calls).toHaveLength(0)
  })
})
