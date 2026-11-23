import type { ApnsEnvironment, DeviceToken, DeviceTokenRepository } from "../db/DeviceTokenRepository.js"
import { nextOpen } from "../domain/marketCalendar.js"
import type { Clock } from "../lib/clock.js"
import { silentLog, type LogSink } from "../lib/logSink.js"
import type { ApnsPayload } from "./payload.js"
import type { ApnsResponse, ApnsTransport } from "./types.js"

export type SendOutcome = "sent" | "pruned" | "failed"

export interface AlertSender {
  send(device: DeviceToken, payload: ApnsPayload, log?: LogSink): Promise<SendOutcome>
  /** Releases network connections. Safe to call repeatedly; the next `send` reconnects. */
  close(): Promise<void>
}

export type ApnsSenderDependencies = {
  transport: ApnsTransport
  tokens: { token(): string; invalidate(): void }
  topic: string
  devices: Pick<DeviceTokenRepository, "setEnvironment" | "prune" | "markSuccess">
  clock: Clock
  sleep?: (ms: number) => Promise<void>
}

type Kind = "ok" | "unregistered" | "badToken" | "wrongTopic" | "expiredToken" | "transient" | "rejected"
type Attempt = { kind: Kind; environment: ApnsEnvironment; status?: number; reason?: string; timestamp?: number }

const RETRY_DELAY_MS = 1_000

/** Logs carry environment, status and reason, never the device token. */
export class ApnsSender implements AlertSender {
  private readonly deps: ApnsSenderDependencies
  private readonly sleep: (ms: number) => Promise<void>

  constructor(deps: ApnsSenderDependencies) {
    this.deps = deps
    this.sleep = deps.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)))
  }

  close(): Promise<void> {
    return this.deps.transport.close()
  }

  async send(device: DeviceToken, payload: ApnsPayload, log: LogSink = silentLog): Promise<SendOutcome> {
    let result = await this.attempt(device.environment, device.token, payload)
    if (result.kind === "expiredToken") {
      this.deps.tokens.invalidate()
      result = await this.attempt(device.environment, device.token, payload)
    } else if (result.kind === "transient") {
      await this.sleep(RETRY_DELAY_MS)
      result = await this.attempt(device.environment, device.token, payload)
    }

    switch (result.kind) {
      case "ok":
        await this.deps.devices.markSuccess(device.token, this.deps.clock.now())
        return "sent"
      case "unregistered":
        return this.prune(device, result, log)
      case "badToken":
        return this.retryOnOtherEnvironment(device, payload, log)
      case "wrongTopic":
        // Our APNS_TOPIC is wrong for this app: pruning here would wipe every device, so only report it.
        log.warn({ ...describe(result), topic: this.deps.topic }, "apns.topic_mismatch")
        return "failed"
      default:
        log.warn(describe(result), "apns.failed")
        return "failed"
    }
  }

  /** A sandbox/production mismatch also looks like BadDeviceToken, so prune only after both hosts reject the token. */
  private async retryOnOtherEnvironment(device: DeviceToken, payload: ApnsPayload, log: LogSink): Promise<SendOutcome> {
    const other: ApnsEnvironment = device.environment === "sandbox" ? "production" : "sandbox"
    const result = await this.attempt(other, device.token, payload)
    if (result.kind === "ok") {
      await this.deps.devices.setEnvironment(device.token, device.userId, other)
      await this.deps.devices.markSuccess(device.token, this.deps.clock.now())
      log.info({ from: device.environment, to: other }, "apns.environment_repaired")
      return "sent"
    }
    if (result.kind === "badToken" || result.kind === "unregistered") {
      // Both hosts rejected it; the stored environment is the first host we asked, so that is the one to match.
      return this.prune(device, { ...result, environment: device.environment }, log)
    }
    log.warn(describe(result), "apns.failed")
    return "failed"
  }

  /** Deletes the token only if it is still registered for the host that rejected it and was not registered again after APNs' 410 timestamp. */
  private async prune(device: DeviceToken, rejection: Attempt, log: LogSink): Promise<SendOutcome> {
    const unregisteredAt = rejection.timestamp === undefined ? undefined : new Date(rejection.timestamp)
    const deleted = await this.deps.devices.prune(device.token, { environment: rejection.environment, unregisteredAt })
    if (!deleted) {
      log.info(describe(rejection), "apns.prune_skipped")
      return "failed"
    }
    log.info(describe(rejection), "apns.pruned")
    return "pruned"
  }

  private async attempt(environment: ApnsEnvironment, deviceToken: string, payload: ApnsPayload): Promise<Attempt> {
    try {
      const response = await this.deps.transport.send({
        environment,
        deviceToken,
        body: payload.body,
        headers: {
          authorization: `bearer ${this.deps.tokens.token()}`,
          "apns-topic": this.deps.topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": payload.collapseId,
          // A buy/sell signal is about the close; once the next session opens it is stale, so APNs should drop it rather than deliver it days later.
          "apns-expiration": String(Math.floor(nextOpen(this.deps.clock.now()).getTime() / 1000)),
        },
      })
      return { kind: classify(response), environment, status: response.status, reason: response.reason, timestamp: response.timestamp }
    } catch (error) {
      return { kind: "transient", environment, reason: error instanceof Error ? error.message : String(error) }
    }
  }
}

function classify(response: ApnsResponse): Kind {
  if (response.status === 200) return "ok"
  if (response.status === 410) return "unregistered"
  if (response.status === 400 && response.reason === "BadDeviceToken") return "badToken"
  if (response.status === 400 && response.reason === "DeviceTokenNotForTopic") return "wrongTopic"
  if (response.status === 403 && response.reason === "ExpiredProviderToken") return "expiredToken"
  if (response.status === 429 || response.status >= 500) return "transient"
  return "rejected"
}

function describe(result: Attempt): { environment: ApnsEnvironment; status: number | undefined; reason: string | undefined } {
  return { environment: result.environment, status: result.status, reason: result.reason }
}
