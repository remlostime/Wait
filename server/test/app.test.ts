import { Type } from "@sinclair/typebox"
import { afterEach, describe, expect, it } from "vitest"
import { AppError } from "../src/lib/errors.js"
import { createLogger } from "../src/lib/logger.js"
import { buildTestApp } from "./support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

describe("buildApp", () => {
  it("serves /health with the container clock and security headers", async () => {
    app = (await buildTestApp()).app
    const response = await app.inject({ method: "GET", url: "/health" })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ status: "ok", timestamp: "2026-11-20T15:00:00.000Z" })
    expect(response.headers["x-content-type-options"]).toBe("nosniff")
  })

  it("returns the error envelope for unknown routes", async () => {
    app = (await buildTestApp()).app
    const response = await app.inject({ method: "GET", url: "/nope" })
    expect(response.statusCode).toBe(404)
    expect(response.json()).toEqual({ error: { code: "NOT_FOUND", message: "The requested resource was not found" } })
  })

  it("maps AppError to its status and sets Retry-After", async () => {
    app = (await buildTestApp()).app
    app.get("/boom", async () => {
      throw new AppError("UPSTREAM_RATE_LIMITED", "Slow down", 503, 30)
    })
    const response = await app.inject({ method: "GET", url: "/boom" })
    expect(response.statusCode).toBe(503)
    expect(response.headers["retry-after"]).toBe("30")
    expect(response.json()).toEqual({ error: { code: "UPSTREAM_RATE_LIMITED", message: "Slow down" } })
  })

  it("maps schema validation failures to VALIDATION_ERROR", async () => {
    app = (await buildTestApp()).app
    app.post("/echo", { schema: { body: Type.Object({ n: Type.Integer() }) } }, async (request) => request.body)
    const response = await app.inject({ method: "POST", url: "/echo", payload: { n: "not-a-number" } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
  })

  it("keeps a nullable body field null (no Ajv coercion)", async () => {
    app = (await buildTestApp()).app
    // Deliberately string-first: with Fastify's default coercion, Ajv would turn null into "" here.
    // Production schemas are null-first (overview §8.1); this test guards the ajv option itself.
    app.post("/nullable", {
      schema: { body: Type.Object({ cursor: Type.Union([Type.String(), Type.Null()]) }, { additionalProperties: false }) },
    }, async (request) => ({ isNull: request.body.cursor === null }))
    const response = await app.inject({ method: "POST", url: "/nullable", payload: { cursor: null } })
    expect(response.statusCode).toBe(200)
    expect(response.json()).toEqual({ isNull: true })
  })

  it("rejects unknown body fields instead of stripping them", async () => {
    app = (await buildTestApp()).app
    app.post("/strict", {
      schema: { body: Type.Object({ cursor: Type.Union([Type.Null(), Type.String()]) }, { additionalProperties: false }) },
    }, async () => ({ ok: true }))
    const response = await app.inject({ method: "POST", url: "/strict", payload: { cursor: null, surprise: 1 } })
    expect(response.statusCode).toBe(400)
    expect(response.json().error.code).toBe("VALIDATION_ERROR")
  })

  it("hides unexpected error messages behind INTERNAL_ERROR", async () => {
    app = (await buildTestApp()).app
    app.get("/crash", async () => {
      throw new Error("database password is hunter2")
    })
    const response = await app.inject({ method: "GET", url: "/crash" })
    expect(response.statusCode).toBe(500)
    expect(response.json()).toEqual({ error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred" } })
  })

  it("redacts authorization headers and tokens in logs", async () => {
    const lines: string[] = []
    const logger = createLogger("info", { write: (line: string) => { lines.push(line) } })
    app = (await buildTestApp({ logger })).app
    app.get("/probe", async (request) => {
      request.log.info(
        { token: "top-token", headers: { authorization: "Bearer secret-123" }, device: { token: "abc-token" }, a: { b: { token: "deep-token" } } },
        "probe",
      )
      return { ok: true }
    })
    await app.inject({ method: "GET", url: "/probe" })
    const probe = lines.find((line) => line.includes('"msg":"probe"'))
    expect(probe).toContain("[redacted]")
    expect(probe).not.toContain("secret-123")
    expect(probe).not.toContain("abc-token")
    expect(probe).not.toContain("top-token")
    expect(probe).not.toContain("deep-token")
  })
})
