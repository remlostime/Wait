import { afterEach, describe, expect, it } from "vitest"
import { Writable } from "node:stream"
import { createLogger } from "../../src/lib/logger.js"
import { buildTestApp } from "../support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>
const TOKEN = "a".repeat(64)
const OTHER = "b".repeat(64)

describe("devices routes", () => {
  let harness: TestApp | undefined

  afterEach(async () => {
    await harness?.app.close()
    harness = undefined
  })

  async function setup(): Promise<TestApp> {
    harness = await buildTestApp()
    return harness
  }

  it("stores the device for the signed-in user (204)", async () => {
    const { app, container, user, authHeaders } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    expect(response.statusCode).toBe(204)
    expect(await container.deviceTokens.listByUsers([user.id])).toMatchObject([
      { token: TOKEN, userId: user.id, environment: "sandbox", bundleId: "com.chenkai.wait", lastSuccessAt: null },
    ])
  })

  it("moves a token to whoever registers it last", async () => {
    const { app, container, user, authHeaders } = await setup()
    const other = await container.users.findOrCreateByAnonymousId("00000000-0000-4000-8000-000000000002", container.clock.now())
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    await app.inject({
      method: "POST",
      url: "/api/devices",
      headers: authHeaders(other.id),
      payload: { token: TOKEN, environment: "production", bundleId: "com.chenkai.wait" },
    })
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
    expect((await container.deviceTokens.listByUsers([other.id])).map((device) => device.environment)).toEqual(["production"])
  })

  it.each([
    { name: "uppercase hex", payload: { token: "A".repeat(64), environment: "sandbox" } },
    { name: "too short", payload: { token: "a".repeat(63), environment: "sandbox" } },
    { name: "unknown environment", payload: { token: TOKEN, environment: "development" } },
    { name: "extra property", payload: { token: TOKEN, environment: "sandbox", userId: "user-9" } },
    { name: "null token", payload: { token: null, environment: "sandbox" } },
  ])("rejects $name with 400 VALIDATION_ERROR", async ({ payload }) => {
    const { app, container, user, authHeaders } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
  })

  it("requires authentication", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "POST", url: "/api/devices", payload: { token: TOKEN, environment: "sandbox" } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("answers 401, not 400, when an unauthenticated request is also invalid", async () => {
    const { app } = await setup()
    const badBody = await app.inject({ method: "POST", url: "/api/devices", payload: { token: "nope" } })
    const badParam = await app.inject({ method: "DELETE", url: "/api/devices/NOT-HEX" })
    expect([badBody.statusCode, badParam.statusCode]).toEqual([401, 401])
  })

  it("deletes only the caller's own token (204 either way)", async () => {
    const { app, container, user, authHeaders } = await setup()
    const other = await container.users.findOrCreateByAnonymousId("00000000-0000-4000-8000-000000000002", container.clock.now())
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
    await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(other.id), payload: { token: OTHER, environment: "sandbox" } })

    const foreign = await app.inject({ method: "DELETE", url: `/api/devices/${OTHER}`, headers: authHeaders() })
    const own = await app.inject({ method: "DELETE", url: `/api/devices/${TOKEN}`, headers: authHeaders() })

    expect([foreign.statusCode, own.statusCode]).toEqual([204, 204])
    expect(await container.deviceTokens.listByUsers([user.id])).toEqual([])
    expect((await container.deviceTokens.listByUsers([other.id])).map((device) => device.token)).toEqual([OTHER])
  })

  describe("request logging", () => {
    function capturingLogger() {
      const lines: string[] = []
      const stream = new Writable({
        write(chunk, _encoding, callback) {
          lines.push(String(chunk))
          callback()
        },
      })
      return { lines, logger: createLogger("trace", stream) }
    }

    it("never writes a device token to the logs, whether it travels in the DELETE path or the POST body", async () => {
      const { lines, logger } = capturingLogger()
      const { app, authHeaders } = (harness = await buildTestApp({ logger }))
      await app.inject({ method: "POST", url: "/api/devices", headers: authHeaders(), payload: { token: TOKEN, environment: "sandbox" } })
      await app.inject({ method: "DELETE", url: `/api/devices/${TOKEN}`, headers: authHeaders() })
      await app.inject({ method: "DELETE", url: `/api/devices/${TOKEN}?x=1` }) // unauthenticated, still must not log it
      await app.inject({ method: "DELETE", url: `/api/devices/${TOKEN}/nope`, headers: authHeaders() }) // 404 path

      expect(lines.length).toBeGreaterThan(0)
      expect(lines.join("")).not.toContain(TOKEN)
      expect(lines.join("")).toContain('"url":"/api/devices/[redacted]"') // still useful: the route is logged, the token is not
    })
  })
})
