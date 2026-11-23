import type { ApnsEnvironment } from "../db/DeviceTokenRepository.js"

export type { ApnsEnvironment }

export type ApnsRequest = { environment: ApnsEnvironment; deviceToken: string; headers: Record<string, string>; body: string }
export type ApnsResponse = { status: number; reason?: string | undefined; apnsId?: string | undefined }

export interface ApnsTransport {
  send(request: ApnsRequest): Promise<ApnsResponse>
  close(): Promise<void>
}
