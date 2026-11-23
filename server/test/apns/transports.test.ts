import { createServer, type Http2Server, type IncomingHttpHeaders } from "node:http2"
import type { AddressInfo } from "node:net"
import { afterAll, beforeAll, describe, expect, it } from "vitest"
import { Http2ApnsTransport } from "../../src/apns/Http2ApnsTransport.js"
import { MockApnsTransport } from "../../src/apns/MockApnsTransport.js"

describe("Http2ApnsTransport", () => {
  let server: Http2Server
  let baseUrl = ""
  let sessions = 0
  const received: Array<{ headers: IncomingHttpHeaders; body: string }> = []

  beforeAll(async () => {
    server = createServer()
    server.on("session", () => {
      sessions += 1
    })
    server.on("stream", (stream, headers) => {
      let body = ""
      stream.setEncoding("utf8")
      stream.on("data", (chunk: string) => {
        body += chunk
      })
      stream.on("end", () => {
        received.push({ headers, body })
        if (headers[":path"] === "/3/device/slow-token") return // never answers; the client must time out
        if (headers[":path"] === "/3/device/bad-token") {
          stream.respond({ ":status": 400, "apns-id": "apns-2", "content-type": "application/json" })
          stream.end(JSON.stringify({ reason: "BadDeviceToken" }))
        } else {
          stream.respond({ ":status": 200, "apns-id": "apns-1" })
          stream.end()
        }
      })
    })
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
    baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  })

  afterAll(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()))
  })

  it("POSTs to /3/device/<token> with the given headers, parses the reason, and reuses one session", async () => {
    const transport = new Http2ApnsTransport({ hosts: { sandbox: baseUrl, production: baseUrl } })

    const ok = await transport.send({
      environment: "sandbox",
      deviceToken: "good-token",
      headers: { authorization: "bearer jwt", "apns-topic": "com.chenkai.wait", "apns-push-type": "alert" },
      body: '{"aps":{}}',
    })
    const bad = await transport.send({ environment: "sandbox", deviceToken: "bad-token", headers: { authorization: "bearer jwt" }, body: "{}" })
    await transport.close()

    expect(ok).toEqual({ status: 200, apnsId: "apns-1", reason: undefined })
    expect(bad).toEqual({ status: 400, apnsId: "apns-2", reason: "BadDeviceToken" })
    expect(received[0]?.headers[":method"]).toBe("POST")
    expect(received[0]?.headers[":path"]).toBe("/3/device/good-token")
    expect(received[0]?.headers["apns-topic"]).toBe("com.chenkai.wait")
    expect(received[0]?.headers["authorization"]).toBe("bearer jwt")
    expect(received[0]?.body).toBe('{"aps":{}}')
    expect(sessions).toBe(1)
  })

  it("destroys the session on timeout so the next send opens a fresh one", async () => {
    const transport = new Http2ApnsTransport({ hosts: { sandbox: baseUrl, production: baseUrl }, timeoutMs: 100 })
    const before = sessions

    await expect(transport.send({ environment: "sandbox", deviceToken: "slow-token", headers: {}, body: "{}" })).rejects.toThrow("timed out")
    const after = await transport.send({ environment: "sandbox", deviceToken: "good-token", headers: {}, body: "{}" })
    await transport.close()

    expect(after.status).toBe(200)
    expect(sessions - before).toBe(2)
  })
})

describe("MockApnsTransport", () => {
  it("records requests, replays scripted responses in order, then answers 200", async () => {
    const transport = new MockApnsTransport()
    transport.script({ status: 410, reason: "Unregistered" }, new Error("socket hang up"))
    const request = { environment: "sandbox" as const, deviceToken: "t", headers: {}, body: "{}" }

    expect(await transport.send(request)).toEqual({ status: 410, reason: "Unregistered" })
    await expect(transport.send(request)).rejects.toThrow("socket hang up")
    expect(await transport.send(request)).toEqual({ status: 200, apnsId: "mock-3" })
    expect(transport.calls).toHaveLength(3)
  })
})
