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

/** The host that rejected the token, and APNs' 410 `timestamp` (converted to a Date) when it sent one. */
export type PruneRejection = { environment: ApnsEnvironment; unregisteredAt?: Date | undefined }

export interface DeviceTokenRepository {
  /** Insert or move the token to `userId` (a token belongs to exactly one user). */
  upsert(registration: DeviceRegistration, now: Date): Promise<void>
  /** DELETE /api/devices/:token: removes the token only if `userId` owns it. */
  removeForUser(token: string, userId: string): Promise<void>
  /** Devices for the given users, ordered by user id, then creation time, then token. */
  listByUsers(userIds: string[]): Promise<DeviceToken[]>
  /**
   * APNs said the token is dead. Deletes only if the stored environment is the one that rejected it and, when APNs gave a
   * 410 `timestamp`, only if the token was last registered before it (a newer registration is a live token). Returns whether a row was deleted.
   */
  prune(token: string, rejection: PruneRejection): Promise<boolean>
  /** Fixes a sandbox/production mismatch. Touches nothing but `environment`, and only for `userId`'s own row. */
  setEnvironment(token: string, userId: string, environment: ApnsEnvironment): Promise<void>
  markSuccess(token: string, now: Date): Promise<void>
}
