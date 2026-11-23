import { afterEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { buildTestApp } from "../support/app.js"

type TestApp = Awaited<ReturnType<typeof buildTestApp>>["app"]
let app: TestApp | undefined

afterEach(async () => {
  await app?.close()
  app = undefined
})

async function setup() {
  const users = new MockUserRepository()
  const built = await buildTestApp({ users })
  app = built.app
  return { app: built.app, users, user: built.user, headers: built.authHeaders() }
}

describe("DELETE /api/auth/account", () => {
  it("requires a bearer token", async () => {
    const { app } = await setup()
    const response = await app.inject({ method: "DELETE", url: "/api/auth/account" })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("rejects a token signed with another secret", async () => {
    const { app } = await setup()
    const forged = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJ4In0.c2lnbmF0dXJl"
    const response = await app.inject({ method: "DELETE", url: "/api/auth/account", headers: { authorization: `Bearer ${forged}` } })
    expect(response.statusCode).toBe(401)
    expect(response.json().error.code).toBe("UNAUTHORIZED")
  })

  it("deletes the user, then the same token reports USER_NOT_FOUND", async () => {
    const { app, users, user, headers } = await setup()
    const deleted = await app.inject({ method: "DELETE", url: "/api/auth/account", headers })
    expect(deleted.statusCode).toBe(204)
    expect(deleted.body).toBe("")
    expect(await users.getById(user.id)).toBeNull()

    const again = await app.inject({ method: "DELETE", url: "/api/auth/account", headers })
    expect(again.statusCode).toBe(401)
    expect(again.json().error.code).toBe("USER_NOT_FOUND")
  })
})
