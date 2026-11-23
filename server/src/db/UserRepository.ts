import type { User } from "./types.js"

export interface UserRepository {
  /** Idempotent single-statement upsert keyed by the unique anonymous id. */
  findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User>
  getById(id: string): Promise<User | null>
  /** Cascades to every user-owned row (ON DELETE CASCADE). Returns false if no row existed. */
  deleteById(id: string): Promise<boolean>
}
