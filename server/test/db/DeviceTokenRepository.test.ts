import { afterEach, beforeEach, describe, expect, it } from "vitest"
import type { DeviceTokenRepository } from "../../src/db/DeviceTokenRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { NeonDeviceTokenRepository } from "../../src/db/NeonDeviceTokenRepository.js"
import { insertUser } from "../support/alertFixtures.js"
import { createTestDb } from "../support/pglite.js"

type Harness = { repo: DeviceTokenRepository; close: () => Promise<void> }

const harnesses: Array<[string, () => Promise<Harness>]> = [
  [
    "NeonDeviceTokenRepository (PGlite)",
    async () => {
      const created = await createTestDb()
      for (const id of ["user-1", "user-2"]) await insertUser(created.sql, id)
      return { repo: new NeonDeviceTokenRepository(created.sql), close: () => created.close() }
    },
  ],
  ["MockDeviceTokenRepository", async () => ({ repo: new MockDeviceTokenRepository(), close: async () => {} })],
]

const TOKEN_A = "a".repeat(64)
const TOKEN_B = "b".repeat(64)
const T0 = new Date("2026-11-20T10:00:00.000Z")
const T1 = new Date("2026-11-20T11:00:00.000Z")
const BUNDLE = "com.chenkai.wait"

describe.each(harnesses)("%s", (_name, makeHarness) => {
  let harness: Harness

  beforeEach(async () => {
    harness = await makeHarness()
  })

  afterEach(async () => {
    await harness.close()
  })

  it("upserts and lists a user's device", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([
      { token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE, createdAt: T0, updatedAt: T0, lastSuccessAt: null },
    ])
  })

  it("moves a re-registered token to the new user and environment", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-2", environment: "production", bundleId: BUNDLE }, T1)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
    expect(await harness.repo.listByUsers(["user-2"])).toEqual([
      { token: TOKEN_A, userId: "user-2", environment: "production", bundleId: BUNDLE, createdAt: T0, updatedAt: T1, lastSuccessAt: null },
    ])
  })

  it("lists devices for several users ordered by user, then creation", async () => {
    await harness.repo.upsert({ token: TOKEN_B, userId: "user-2", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T1)
    const devices = await harness.repo.listByUsers(["user-2", "user-1"])
    expect(devices.map((device) => [device.userId, device.token])).toEqual([
      ["user-1", TOKEN_A],
      ["user-2", TOKEN_B],
    ])
  })

  it("returns nothing for an empty user list", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    expect(await harness.repo.listByUsers([])).toEqual([])
  })

  it("only removes a token for its owner", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.removeForUser(TOKEN_A, "user-2")
    expect(await harness.repo.listByUsers(["user-1"])).toHaveLength(1)
    await harness.repo.removeForUser(TOKEN_A, "user-1")
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
  })

  it("prunes a token that the host it is registered for rejected", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox" })).toBe(true)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox" })).toBe(false)
  })

  it("keeps a token whose stored environment is not the one that rejected it", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "production", bundleId: BUNDLE }, T0)
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox" })).toBe(false)
    expect(await harness.repo.listByUsers(["user-1"])).toHaveLength(1)
  })

  it("honors the APNs 410 timestamp: only a token last registered before it is deleted", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T1)
    // The app re-registered the token (T1) after APNs invalidated it (T0): it is alive again.
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox", unregisteredAt: T0 })).toBe(false)
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox", unregisteredAt: T1 })).toBe(false)
    expect(await harness.repo.listByUsers(["user-1"])).toHaveLength(1)
    expect(await harness.repo.prune(TOKEN_A, { environment: "sandbox", unregisteredAt: new Date(T1.getTime() + 1) })).toBe(true)
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
  })

  it("repairs only the environment of the token's own user, leaving owner and registration time alone", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.setEnvironment(TOKEN_A, "user-2", "production")
    expect((await harness.repo.listByUsers(["user-1"]))[0]?.environment).toBe("sandbox")
    await harness.repo.setEnvironment(TOKEN_A, "user-1", "production")
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([
      { token: TOKEN_A, userId: "user-1", environment: "production", bundleId: BUNDLE, createdAt: T0, updatedAt: T0, lastSuccessAt: null },
    ])
  })

  it("does not recreate a token that was removed while the repair was in flight", async () => {
    await harness.repo.setEnvironment(TOKEN_A, "user-1", "production")
    expect(await harness.repo.listByUsers(["user-1"])).toEqual([])
  })

  it("records the last successful delivery", async () => {
    await harness.repo.upsert({ token: TOKEN_A, userId: "user-1", environment: "sandbox", bundleId: BUNDLE }, T0)
    await harness.repo.markSuccess(TOKEN_A, T1)
    const [device] = await harness.repo.listByUsers(["user-1"])
    expect(device?.lastSuccessAt).toEqual(T1)
  })
})
