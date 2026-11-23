import { Type, type Static } from "@sinclair/typebox"

export const DEVICE_TOKEN_PATTERN = "^[0-9a-f]{64,200}$"
export const DEFAULT_BUNDLE_ID = "com.chenkai.wait"

export const RegisterDeviceBodySchema = Type.Object(
  {
    token: Type.String({ pattern: DEVICE_TOKEN_PATTERN }),
    environment: Type.Union([Type.Literal("sandbox"), Type.Literal("production")]),
    bundleId: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
  },
  { additionalProperties: false },
)
export type RegisterDeviceBody = Static<typeof RegisterDeviceBodySchema>

export const DeviceTokenParamsSchema = Type.Object({ token: Type.String({ pattern: DEVICE_TOKEN_PATTERN }) }, { additionalProperties: false })
