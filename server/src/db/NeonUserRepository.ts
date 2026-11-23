import { randomUUID } from "node:crypto"
import { asDate } from "../lib/time.js"
import type { Row, Sql } from "./sql.js"
import type { User } from "./types.js"
import type { UserRepository } from "./UserRepository.js"

function mapRowToUser(row: Row): User {
  return {
    id: String(row.id),
    anonymousId: String(row.anonymous_id),
    createdAt: asDate(row.created_at),
    updatedAt: asDate(row.updated_at),
  }
}

export class NeonUserRepository implements UserRepository {
  constructor(private readonly sql: Sql) {}

  async findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User> {
    const rows = await this.sql`
      INSERT INTO users (id, anonymous_id, created_at, updated_at)
      VALUES (${randomUUID()}, ${anonymousId}, ${now}, ${now})
      ON CONFLICT (anonymous_id) DO UPDATE SET updated_at = EXCLUDED.updated_at
      RETURNING id, anonymous_id, created_at, updated_at`
    const row = rows[0]
    if (!row) throw new Error("users upsert returned no row")
    return mapRowToUser(row)
  }

  async getById(id: string): Promise<User | null> {
    const rows = await this.sql`SELECT id, anonymous_id, created_at, updated_at FROM users WHERE id = ${id}`
    return rows[0] ? mapRowToUser(rows[0]) : null
  }

  async deleteById(id: string): Promise<boolean> {
    const rows = await this.sql`DELETE FROM users WHERE id = ${id} RETURNING id`
    return rows.length > 0
  }
}
