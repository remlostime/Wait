import { readFileSync } from "node:fs"
import { describe, expect, it } from "vitest"

type VercelConfig = { crons?: Array<{ path: string; schedule: string }>; routes?: Array<{ src?: string; dest?: string }> }

const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8")) as VercelConfig

describe("vercel.json", () => {
  it("schedules the daily alert job after the US close on weekdays, with a second daily catch-up run", () => {
    // Hobby crons run at most once per day each, so the catch-up is a separate entry for the same path.
    expect(config.crons).toEqual([
      { path: "/api/internal/daily-alerts", schedule: "0 22 * * 1-5" },
      { path: "/api/internal/daily-alerts", schedule: "30 23 * * 1-5" },
    ])
  })

  it("routes the cron path to the Fastify function", () => {
    const route = config.routes?.find((candidate) => candidate.src !== undefined && new RegExp(`^${candidate.src}$`).test("/api/internal/daily-alerts"))
    expect(route?.dest).toBe("src/server.ts")
  })
})
