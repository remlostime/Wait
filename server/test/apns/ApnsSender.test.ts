import { beforeEach, describe, expect, it } from "vitest"
import { ApnsSender } from "../../src/apns/ApnsSender.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"
import type { DeviceToken } from "../../src/db/DeviceTokenRepository.js"
import { MockDeviceTokenRepository } from "../../src/db/MockDeviceTokenRepository.js"
import { nextOpen } from "../../src/domain/marketCalendar.js"
import { RecordingLogger } from "../support/alertFakes.js"

const NOW = new Date("2026-11-20T22:00:00.000Z")
const PAYLOAD = { body: '{"aps":{}}', collapseId: "AAPL-2026-11-20" }
const DEVICE: DeviceToken = {
  token: "a".repeat(64),
  userId: "user-1",
  environment: "sandbox",
  bundleId: "com.chenkai.wait",
  createdAt: NOW,
  updatedAt: NOW,
  lastSuccessAt: null,
}

class FakeTokens {
  current = 1
  invalidations = 0

  token(): string {
    return `provider-${this.current}`
  }

  invalidate(): void {
    this.invalidations += 1
    this.current += 1
  }
}

describe("ApnsSender", () => {
  let transport: MockApnsTransport
  let devices: MockDeviceTokenRepository
  let tokens: FakeTokens
  let sleeps: number[]
  let sender: ApnsSender

  beforeEach(() => {
    transport = new MockApnsTransport()
    devices = new MockDeviceTokenRepository()
    devices.seed([DEVICE])
    tokens = new FakeTokens()
    sleeps = []
    sender = new ApnsSender({
      transport,
      tokens,
      topic: "com.chenkai.wait",
      devices,
      clock: { now: () => NOW },
      sleep: async (ms) => {
        sleeps.push(ms)
      },
    })
  })

  it("sends with the APNs headers and records the success", async () => {
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(transport.calls).toEqual([
      {
        environment: "sandbox",
        deviceToken: DEVICE.token,
        body: PAYLOAD.body,
        headers: {
          authorization: "bearer provider-1",
          "apns-topic": "com.chenkai.wait",
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": "AAPL-2026-11-20",
          "apns-expiration": String(Math.floor(nextOpen(NOW).getTime() / 1000)),
        },
      },
    ])
    expect(devices.all()[0]?.lastSuccessAt).toEqual(NOW)
  })

  it("expires the push at the next market open so a stale signal is not delivered days later", async () => {
    await sender.send(DEVICE, PAYLOAD)
    // NOW is Friday 5pm ET; the next open is Monday 2026-11-23 09:30 ET = 14:30 UTC.
    expect(transport.calls[0]?.headers["apns-expiration"]).toBe(String(Date.parse("2026-11-23T14:30:00.000Z") / 1000))
  })

  it("prunes a token APNs reports as unregistered (410)", async () => {
    transport.script({ status: 410, reason: "Unregistered" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("pruned")
    expect(devices.all()).toEqual([])
  })

  it("repairs the environment when the token only works on the other host", async () => {
    transport.script({ status: 400, reason: "BadDeviceToken" }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(transport.calls.map((call) => call.environment)).toEqual(["sandbox", "production"])
    expect(devices.all()[0]?.environment).toBe("production")
  })

  it("prunes when both hosts reject the token", async () => {
    transport.script({ status: 400, reason: "BadDeviceToken" }, { status: 400, reason: "BadDeviceToken" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("pruned")
    expect(devices.all()).toEqual([])
  })

  it("repairs the environment without touching the owner when the token was re-registered by someone else", async () => {
    devices.seed([{ ...DEVICE, userId: "user-2" }])
    transport.script({ status: 400, reason: "BadDeviceToken" }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(devices.all()).toEqual([{ ...DEVICE, userId: "user-2", lastSuccessAt: NOW }])
  })

  it("does not prune a token that was moved to another environment while the send was in flight", async () => {
    devices.seed([{ ...DEVICE, environment: "production" }])
    transport.script({ status: 410, reason: "Unregistered" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("failed")
    expect(devices.all()).toHaveLength(1)
  })

  it("keeps a token that registered again after the 410 timestamp, and prunes one that did not", async () => {
    transport.script({ status: 410, reason: "Unregistered", timestamp: NOW.getTime() - 3_600_000 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("failed")
    expect(devices.all()).toHaveLength(1)

    transport.script({ status: 410, reason: "Unregistered", timestamp: NOW.getTime() + 3_600_000 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("pruned")
    expect(devices.all()).toEqual([])
  })

  it("refreshes the provider token once on ExpiredProviderToken", async () => {
    transport.script({ status: 403, reason: "ExpiredProviderToken" }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(tokens.invalidations).toBe(1)
    expect(transport.calls.map((call) => call.headers.authorization)).toEqual(["bearer provider-1", "bearer provider-2"])
  })

  it("retries a 5xx once after one second", async () => {
    transport.script({ status: 503 }, { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
    expect(sleeps).toEqual([1000])
  })

  it("gives up after a second 429 and keeps the device", async () => {
    transport.script({ status: 429, reason: "TooManyRequests" }, { status: 429, reason: "TooManyRequests" })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("failed")
    expect(transport.calls).toHaveLength(2)
    expect(devices.all()).toHaveLength(1)
  })

  it("retries once when the transport throws", async () => {
    transport.script(new Error("socket hang up"), { status: 200 })
    expect(await sender.send(DEVICE, PAYLOAD)).toBe("sent")
  })

  it("does not retry other rejections, and logs status and reason without the token", async () => {
    const log = new RecordingLogger()
    transport.script({ status: 400, reason: "BadTopic" })
    expect(await sender.send(DEVICE, PAYLOAD, log)).toBe("failed")
    expect(transport.calls).toHaveLength(1)
    expect(devices.all()).toHaveLength(1)
    expect(log.entries).toEqual([{ level: "warn", message: "apns.failed", details: { environment: "sandbox", status: 400, reason: "BadTopic" } }])
    expect(JSON.stringify(log.entries)).not.toContain(DEVICE.token)
  })

  it("never prunes on DeviceTokenNotForTopic (a misconfigured topic) and reports it", async () => {
    const log = new RecordingLogger()
    transport.script({ status: 400, reason: "DeviceTokenNotForTopic" })
    expect(await sender.send(DEVICE, PAYLOAD, log)).toBe("failed")
    expect(transport.calls).toHaveLength(1)
    expect(devices.all()).toHaveLength(1)
    expect(log.entries[0]?.message).toBe("apns.topic_mismatch")
  })
})
