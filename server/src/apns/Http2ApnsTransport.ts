import { connect, constants, type ClientHttp2Session } from "node:http2"
import type { ApnsEnvironment, ApnsRequest, ApnsResponse, ApnsTransport } from "./types.js"

export const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
}

export type Http2ApnsTransportOptions = { hosts?: Record<ApnsEnvironment, string>; timeoutMs?: number }

/** One HTTP/2 session per APNs host, opened lazily and reused across sends. */
export class Http2ApnsTransport implements ApnsTransport {
  private readonly hosts: Record<ApnsEnvironment, string>
  private readonly timeoutMs: number
  private readonly sessions = new Map<ApnsEnvironment, ClientHttp2Session>()

  constructor(options: Http2ApnsTransportOptions = {}) {
    this.hosts = options.hosts ?? APNS_HOSTS
    this.timeoutMs = options.timeoutMs ?? 10_000
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
      stream.setEncoding("utf8")
      stream.setTimeout(this.timeoutMs, () => {
        stream.close(constants.NGHTTP2_CANCEL)
        // A hung stream usually means a dead connection: drop the session so the next send reconnects.
        if (this.sessions.get(request.environment) === session) this.sessions.delete(request.environment)
        session.destroy()
        reject(new Error(`APNs request timed out after ${this.timeoutMs} ms`))
      })
      stream.on("response", (headers) => {
        status = Number(headers[":status"] ?? 0)
        const id = headers["apns-id"]
        apnsId = typeof id === "string" ? id : undefined
      })
      stream.on("data", (chunk: string) => {
        data += chunk
      })
      stream.on("end", () => resolve({ status, apnsId, reason: parseReason(data) }))
      stream.on("error", reject)
      stream.end(request.body)
    })
  }

  async close(): Promise<void> {
    const open = [...this.sessions.values()]
    this.sessions.clear()
    await Promise.all(open.map((session) => new Promise<void>((resolve) => session.close(() => resolve()))))
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

function parseReason(body: string): string | undefined {
  if (body === "") return undefined
  try {
    const parsed = JSON.parse(body) as { reason?: unknown }
    return typeof parsed.reason === "string" ? parsed.reason : undefined
  } catch {
    return undefined
  }
}
