import { Type } from "@sinclair/typebox"

const Count = Type.Integer({ minimum: 0 })

export const DailyAlertsResponseSchema = Type.Object(
  {
    tradingDate: Type.String({ pattern: "^\\d{4}-\\d{2}-\\d{2}$" }),
    status: Type.Union([Type.Literal("completed"), Type.Literal("holiday"), Type.Literal("skipped"), Type.Literal("resent")]),
    evaluated: Count,
    transitions: Count,
    alertsCreated: Count,
    alertsSent: Count,
    pruned: Count,
  },
  { additionalProperties: false },
)
