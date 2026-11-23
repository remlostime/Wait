import type { ApnsRequest, ApnsResponse, ApnsTransport } from "./types.js"

export class MockApnsTransport implements ApnsTransport {
  readonly calls: ApnsRequest[] = []
  closeCalls = 0
  private readonly scripted: Array<ApnsResponse | Error> = []

  /** Queue responses (or thrown errors) for the next sends; unscripted sends answer 200. */
  script(...responses: Array<ApnsResponse | Error>): void {
    this.scripted.push(...responses)
  }

  async send(request: ApnsRequest): Promise<ApnsResponse> {
    this.calls.push(request)
    const next = this.scripted.shift()
    if (next instanceof Error) throw next
    return next ?? { status: 200, apnsId: `mock-${this.calls.length}` }
  }

  async close(): Promise<void> {
    this.closeCalls += 1
  }
}
