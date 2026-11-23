import { asDate, asNullableDate } from "../lib/time.js"
import type { ApnsEnvironment, DeviceRegistration, DeviceToken, DeviceTokenRepository, PruneRejection } from "./DeviceTokenRepository.js"
import type { Sql } from "./sql.js"

type DeviceTokenRow = {
  token: string
  user_id: string
  environment: string
  bundle_id: string
  created_at: unknown
  updated_at: unknown
  last_success_at: unknown
}

function toEnvironment(value: string): ApnsEnvironment {
  if (value === "sandbox" || value === "production") return value
  throw new Error(`Unknown APNs environment in device_tokens: ${value}`)
}

function mapRow(row: DeviceTokenRow): DeviceToken {
  return {
    token: row.token,
    userId: row.user_id,
    environment: toEnvironment(row.environment),
    bundleId: row.bundle_id,
    createdAt: asDate(row.created_at),
    updatedAt: asDate(row.updated_at),
    lastSuccessAt: asNullableDate(row.last_success_at),
  }
}

export class NeonDeviceTokenRepository implements DeviceTokenRepository {
  private readonly sql: Sql

  constructor(sql: Sql) {
    this.sql = sql
  }

  async upsert(registration: DeviceRegistration, now: Date): Promise<void> {
    const at = now.toISOString()
    await this.sql`
      INSERT INTO device_tokens (token, user_id, environment, bundle_id, created_at, updated_at)
      VALUES (${registration.token}, ${registration.userId}, ${registration.environment}, ${registration.bundleId},
        ${at}::timestamptz, ${at}::timestamptz)
      ON CONFLICT (token) DO UPDATE SET
        user_id = EXCLUDED.user_id, environment = EXCLUDED.environment,
        bundle_id = EXCLUDED.bundle_id, updated_at = EXCLUDED.updated_at`
  }

  async removeForUser(token: string, userId: string): Promise<void> {
    await this.sql`DELETE FROM device_tokens WHERE token = ${token} AND user_id = ${userId}`
  }

  async listByUsers(userIds: string[]): Promise<DeviceToken[]> {
    if (userIds.length === 0) return []
    const rows = await this.sql`
      SELECT token, user_id, environment, bundle_id, created_at, updated_at, last_success_at
      FROM device_tokens
      WHERE user_id IN (SELECT jsonb_array_elements_text(${JSON.stringify(userIds)}::jsonb))
      ORDER BY user_id, created_at, token`
    return rows.map((row) => mapRow(row as DeviceTokenRow))
  }

  async prune(token: string, rejection: PruneRejection): Promise<boolean> {
    const unregisteredAt = rejection.unregisteredAt?.toISOString() ?? null
    const rows = await this.sql`
      DELETE FROM device_tokens
      WHERE token = ${token} AND environment = ${rejection.environment}
        AND (${unregisteredAt}::timestamptz IS NULL OR updated_at < ${unregisteredAt}::timestamptz)
      RETURNING token`
    return rows.length > 0
  }

  async setEnvironment(token: string, userId: string, environment: ApnsEnvironment): Promise<void> {
    await this.sql`UPDATE device_tokens SET environment = ${environment} WHERE token = ${token} AND user_id = ${userId}`
  }

  async markSuccess(token: string, now: Date): Promise<void> {
    await this.sql`UPDATE device_tokens SET last_success_at = ${now.toISOString()}::timestamptz WHERE token = ${token}`
  }
}
