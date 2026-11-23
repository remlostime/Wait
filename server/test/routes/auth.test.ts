import { afterEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { MockRateLimiter } from "../../src/services/RateLimiter.js"
import { buildTestApp } from "../support/app.js"

const ANON = "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"
type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup() {
  const users = new MockUserRepository()
  const rateLimiter = new MockRateLimiter()
  const built = await buildTestApp({ users, rateLimiter })
  app = built.app
  return { app: built.app, users, rateLimiter }
}

describe("POST /api/auth/register", () => {
  it("creates a user and returns a token whose payload is { userId }", async () => {
    const { app, users } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON } })
    expect(response.statusCode).toBe(200)
    const body = response.json()
    expect(app.jwt.verify<{ userId: string }>(body.token).userId).toBe(body.user.id)
    expect((await users.getById(body.user.id))?.anonymousId).toBe(ANON.toLowerCase())
  })

  it("is idempotent per anonymous id regardless of case", async () => {
    const { app } = await setup()
    const first = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON } })
    const second = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: ANON.toLowerCase() } })
    expect(second.json().user.id).toBe(first.json().user.id)
  })

  it("rejects ids that are not UUIDs", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/auth/register", payload: { anonymousId: "not-a-uuid" } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("INVALID_INPUT")
  })

  it("rate-limits per client IP and per anonymous id", async () => {
    const { app, rateLimiter } = await setup()
    await app.inject({ method: "POST", url: "/api/auth/register", headers: { "x-real-ip": "1.2.3.4" }, payload: { anonymousId: ANON } })
    expect(rateLimiter.takes.map((t) => t.key)).toEqual(["register:ip:1.2.3.4", `register:anon:${ANON.toLowerCase()}`])

    rateLimiter.denied.add("register:ip:1.2.3.4")
    const limited = await app.inject({ method: "POST", url: "/api/auth/register", headers: { "x-real-ip": "1.2.3.4" }, payload: { anonymousId: ANON } })
    expect(limited.statusCode).toBe(429)
    expect(limited.headers["retry-after"]).toBe("3") // one token of REGISTER_IP_POLICY (20 per minute)
    expect(limited.json().error.code).toBe("RATE_LIMITED")
  })
})
