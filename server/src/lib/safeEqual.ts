import { createHash, timingSafeEqual } from "node:crypto"

/** Constant-time comparison; hashing first makes unequal lengths safe for timingSafeEqual. */
export function safeEqual(a: string, b: string): boolean {
  const left = createHash("sha256").update(a).digest()
  const right = createHash("sha256").update(b).digest()
  return timingSafeEqual(left, right)
}
