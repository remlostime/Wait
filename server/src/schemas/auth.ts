import { Type, type Static } from "@sinclair/typebox"

export const RegisterBodySchema = Type.Object({ anonymousId: Type.String({ minLength: 1, maxLength: 64 }) }, { additionalProperties: false })
export type RegisterBody = Static<typeof RegisterBodySchema>

export const RegisterResponseSchema = Type.Object({
  token: Type.String(),
  user: Type.Object({ id: Type.String() }),
})
