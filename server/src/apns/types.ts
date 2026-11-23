import type { ApnsEnvironment } from "../db/DeviceTokenRepository.js"

export type { ApnsEnvironment }

export type ApnsRequest = { environment: ApnsEnvironment; deviceToken: string; headers: Record<string, string>; body: string }
export type ApnsResponse = {
  status: number
  reason?: string | undefined
  apnsId?: string | undefined
  /** A 410's `timestamp`: epoch milliseconds at which APNs confirmed the token was no longer valid. */
  timestamp?: number | undefined
}

export interface ApnsTransport {
  send(request: ApnsRequest): Promise<ApnsResponse>
  close(): Promise<void>
}
