import type { User } from "../db/types.js"
import type { UserRepository } from "../db/UserRepository.js"
import type { Clock } from "../lib/clock.js"
import { AppError } from "../lib/errors.js"
import { REGISTER_ANON_POLICY, REGISTER_IP_POLICY, type RateLimiter } from "./RateLimiter.js"

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class AuthService {
  constructor(
    private readonly users: UserRepository,
    private readonly limiter: RateLimiter,
    private readonly clock: Clock,
  ) {}

  /** Find-or-create by anonymous id (stored lowercase; iOS sends uppercase uuidString). */
  async register(anonymousId: string, clientIp: string): Promise<User> {
    if (!UUID_REGEX.test(anonymousId)) throw new AppError("INVALID_INPUT", "anonymousId must be a valid UUID", 400)
    const normalized = anonymousId.toLowerCase()
    if (!(await this.limiter.tryTake(`register:ip:${clientIp}`, REGISTER_IP_POLICY))) {
      throw new AppError("RATE_LIMITED", "Too many registration attempts, try again later", 429, 60)
    }
    if (!(await this.limiter.tryTake(`register:anon:${normalized}`, REGISTER_ANON_POLICY))) {
      throw new AppError("RATE_LIMITED", "Too many registration attempts, try again later", 429, 60)
    }
    return this.users.findOrCreateByAnonymousId(normalized, this.clock.now())
  }

  async deleteAccount(userId: string): Promise<void> {
    const deleted = await this.users.deleteById(userId)
    if (!deleted) throw new AppError("USER_NOT_FOUND", "User associated with token no longer exists", 401)
  }
}
