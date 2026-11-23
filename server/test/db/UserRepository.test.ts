import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { MockUserRepository } from "../../src/db/MockUserRepository.js"
import { NeonUserRepository } from "../../src/db/NeonUserRepository.js"
import type { UserRepository } from "../../src/db/UserRepository.js"
import { createTestDb, type TestDb } from "../support/pglite.js"

const ANON = "6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f"
const T0 = new Date("2026-11-20T15:00:00.000Z")
const T1 = new Date("2026-11-20T16:00:00.000Z")

const implementations: Array<[string, () => Promise<{ repo: UserRepository; close: () => Promise<void> }>]> = [
  ["NeonUserRepository (PGlite)", async () => {
    const db: TestDb = await createTestDb()
    return { repo: new NeonUserRepository(db.sql), close: db.close }
  }],
  ["MockUserRepository", async () => ({ repo: new MockUserRepository(), close: async () => {} })],
]

describe.each(implementations)("%s", (_name, make) => {
  let repo: UserRepository
  let close: () => Promise<void>

  beforeEach(async () => {
    ;({ repo, close } = await make())
  })
  afterEach(async () => {
    await close()
  })

  it("creates a user on first sight of an anonymous id", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(user).toMatchObject({ anonymousId: ANON, createdAt: T0, updatedAt: T0 })
    expect(user.id).toMatch(/^[0-9a-f-]{36}$/)
  })

  it("returns the same user on later calls and bumps updatedAt", async () => {
    const first = await repo.findOrCreateByAnonymousId(ANON, T0)
    const second = await repo.findOrCreateByAnonymousId(ANON, T1)
    expect(second.id).toBe(first.id)
    expect(second.createdAt).toEqual(T0)
    expect(second.updatedAt).toEqual(T1)
  })

  it("gets by id and returns null for unknown ids", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(await repo.getById(user.id)).toEqual(user)
    expect(await repo.getById("00000000-0000-4000-8000-000000000000")).toBeNull()
  })

  it("deletes by id and reports whether a row existed", async () => {
    const user = await repo.findOrCreateByAnonymousId(ANON, T0)
    expect(await repo.deleteById(user.id)).toBe(true)
    expect(await repo.getById(user.id)).toBeNull()
    expect(await repo.deleteById(user.id)).toBe(false)
  })
})
