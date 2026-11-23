import type { DeviceRegistration, DeviceToken, DeviceTokenRepository } from "./DeviceTokenRepository.js"

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

export class MockDeviceTokenRepository implements DeviceTokenRepository {
  private readonly devices = new Map<string, DeviceToken>()

  seed(devices: DeviceToken[]): void {
    for (const device of devices) this.devices.set(device.token, { ...device })
  }

  all(): DeviceToken[] {
    return [...this.devices.values()].map((device) => ({ ...device }))
  }

  clear(): void {
    this.devices.clear()
  }

  async upsert(registration: DeviceRegistration, now: Date): Promise<void> {
    const existing = this.devices.get(registration.token)
    this.devices.set(registration.token, {
      ...registration,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastSuccessAt: existing?.lastSuccessAt ?? null,
    })
  }

  async removeForUser(token: string, userId: string): Promise<void> {
    if (this.devices.get(token)?.userId === userId) this.devices.delete(token)
  }

  async listByUsers(userIds: string[]): Promise<DeviceToken[]> {
    const wanted = new Set(userIds)
    return this.all()
      .filter((device) => wanted.has(device.userId))
      .sort((a, b) => compare(a.userId, b.userId) || a.createdAt.getTime() - b.createdAt.getTime() || compare(a.token, b.token))
  }

  async prune(token: string): Promise<void> {
    this.devices.delete(token)
  }

  async markSuccess(token: string, now: Date): Promise<void> {
    const device = this.devices.get(token)
    if (device) this.devices.set(token, { ...device, lastSuccessAt: now })
  }
}
