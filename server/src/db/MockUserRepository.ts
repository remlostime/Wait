import { randomUUID } from "node:crypto"
import type { User } from "./types.js"
import type { UserRepository } from "./UserRepository.js"

export class MockUserRepository implements UserRepository {
  private readonly users = new Map<string, User>()

  clear(): void {
    this.users.clear()
  }

  seed(users: User[]): void {
    for (const user of users) this.users.set(user.id, { ...user })
  }

  async findOrCreateByAnonymousId(anonymousId: string, now: Date): Promise<User> {
    const existing = [...this.users.values()].find((user) => user.anonymousId === anonymousId)
    if (existing) {
      existing.updatedAt = new Date(now.getTime())
      return { ...existing }
    }
    const user: User = { id: randomUUID(), anonymousId, createdAt: new Date(now.getTime()), updatedAt: new Date(now.getTime()) }
    this.users.set(user.id, user)
    return { ...user }
  }

  async getById(id: string): Promise<User | null> {
    const user = this.users.get(id)
    return user ? { ...user } : null
  }

  async deleteById(id: string): Promise<boolean> {
    return this.users.delete(id)
  }
}
