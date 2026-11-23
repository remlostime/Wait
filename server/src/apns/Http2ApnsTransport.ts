import { connect, constants, type ClientHttp2Session } from "node:http2"
import type { ApnsEnvironment, ApnsRequest, ApnsResponse, ApnsTransport } from "./types.js"

export const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
}

/** A healthy APNs round trip takes tens of milliseconds; a hung one must not eat the cron function's time budget. */
export const DEFAULT_APNS_TIMEOUT_MS = 3_000
const DEFAULT_CLOSE_GRACE_MS = 1_000

export type Http2ApnsTransportOptions = {
  hosts?: Record<ApnsEnvironment, string>
  timeoutMs?: number
  /** How long `close()` waits for a session to finish gracefully before destroying it. */
  closeGraceMs?: number
}

/** One HTTP/2 session per APNs host, opened lazily and reused across sends. Call `close()` when a run is done (a frozen warm instance would keep a dead socket). */
export class Http2ApnsTransport implements ApnsTransport {
  private readonly hosts: Record<ApnsEnvironment, string>
  private readonly timeoutMs: number
  private readonly closeGraceMs: number
  private readonly sessions = new Map<ApnsEnvironment, ClientHttp2Session>()

  constructor(options: Http2ApnsTransportOptions = {}) {
    this.hosts = options.hosts ?? APNS_HOSTS
    this.timeoutMs = options.timeoutMs ?? DEFAULT_APNS_TIMEOUT_MS
    this.closeGraceMs = options.closeGraceMs ?? DEFAULT_CLOSE_GRACE_MS
  }

  send(request: ApnsRequest): Promise<ApnsResponse> {
    const session = this.session(request.environment)
    return new Promise((resolve, reject) => {
      const stream = session.request({
        ":method": "POST",
        ":path": `/3/device/${request.deviceToken}`,
        "content-type": "application/json",
        ...request.headers,
      })
      let status = 0
      let apnsId: string | undefined
      let data = ""
      let responded = false
      stream.setEncoding("utf8")
      stream.setTimeout(this.timeoutMs, () => {
        stream.close(constants.NGHTTP2_CANCEL)
        // A hung stream usually means a dead connection: drop the session so the next send reconnects.
        if (this.sessions.get(request.environment) === session) this.sessions.delete(request.environment)
        session.destroy()
        reject(new Error(`APNs request timed out after ${this.timeoutMs} ms`))
      })
      stream.on("response", (headers) => {
        responded = true
        status = Number(headers[":status"] ?? 0)
        const id = headers["apns-id"]
        apnsId = typeof id === "string" ? id : undefined
      })
      stream.on("data", (chunk: string) => {
        data += chunk
      })
      stream.on("end", () => {
        if (!responded) return reject(new Error("APNs stream ended without a response"))
        resolve({ status, apnsId, ...parseBody(data) })
      })
      stream.on("error", reject)
      // A stream reset or closed before it ended (a dead connection, a GOAWAY) emits neither "end" nor always "error": fail now, not at the timeout.
      stream.on("close", () => reject(new Error(`APNs stream closed before a response (rstCode ${stream.rstCode})`)))
      stream.end(request.body)
    })
  }

  async close(): Promise<void> {
    const open = [...this.sessions.values()]
    this.sessions.clear()
    await Promise.all(
      open.map(
        (session) =>
          new Promise<void>((resolve) => {
            // Graceful close waits for in-flight streams; a frozen/dead connection never finishes, so destroy it after a grace period.
            const timer = setTimeout(() => {
              session.destroy()
              resolve()
            }, this.closeGraceMs)
            session.close(() => {
              clearTimeout(timer)
              resolve()
            })
          }),
      ),
    )
  }

  private session(environment: ApnsEnvironment): ClientHttp2Session {
    const existing = this.sessions.get(environment)
    if (existing !== undefined && !existing.closed && !existing.destroyed) return existing
    const session = connect(this.hosts[environment])
    const forget = (): void => {
      if (this.sessions.get(environment) === session) this.sessions.delete(environment)
    }
    session.on("error", forget)
    session.on("close", forget)
    this.sessions.set(environment, session)
    return session
  }
}

function parseBody(body: string): { reason?: string | undefined; timestamp?: number | undefined } {
  if (body === "") return { reason: undefined }
  try {
    const parsed = JSON.parse(body) as { reason?: unknown; timestamp?: unknown }
    const reason = typeof parsed.reason === "string" ? parsed.reason : undefined
    return typeof parsed.timestamp === "number" ? { reason, timestamp: parsed.timestamp } : { reason }
  } catch {
    return { reason: undefined }
  }
}
