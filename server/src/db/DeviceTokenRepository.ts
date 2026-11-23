export type ApnsEnvironment = "sandbox" | "production"

export type DeviceToken = {
  token: string
  userId: string
  environment: ApnsEnvironment
  bundleId: string
  createdAt: Date
  updatedAt: Date
  lastSuccessAt: Date | null
}

export type DeviceRegistration = { token: string; userId: string; environment: ApnsEnvironment; bundleId: string }

export interface DeviceTokenRepository {
  /** Insert or move the token to `userId` (a token belongs to exactly one user). */
  upsert(registration: DeviceRegistration, now: Date): Promise<void>
  /** DELETE /api/devices/:token: removes the token only if `userId` owns it. */
  removeForUser(token: string, userId: string): Promise<void>
  /** Devices for the given users, ordered by user id, then creation time, then token. */
  listByUsers(userIds: string[]): Promise<DeviceToken[]>
  /** APNs said the token is dead. */
  prune(token: string): Promise<void>
  markSuccess(token: string, now: Date): Promise<void>
}
