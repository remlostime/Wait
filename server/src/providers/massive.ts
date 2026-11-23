import { parseRetryAfter, type FetchLike } from "./http.js"
import { ProviderError, type DailyClose, type GroupedDailyProvider } from "./types.js"

type GroupedResult = { T?: unknown; c?: unknown; t?: unknown }

export type MassiveOptions = { apiKey: string; baseUrl: string; fetchImpl?: FetchLike; timeoutMs?: number }

/** One call inside a cron run that must finish well under 10 s (overview §8.6). */
export const MASSIVE_TIMEOUT_MS = 4_000

const isTimeout = (error: unknown): boolean => {
  const name = (error as { name?: string } | null)?.name
  return name === "TimeoutError" || name === "AbortError"
}

/** Massive (ex-Polygon) grouped daily: GET /v2/aggs/grouped/locale/us/market/stocks/{date}. One call covers every US stock. */
export function createMassiveProvider(options: MassiveOptions): GroupedDailyProvider {
  const fetchImpl: FetchLike = options.fetchImpl ?? ((url, init) => fetch(url, init))
  const baseUrl = options.baseUrl.replace(/\/+$/, "")

  return {
    async getGroupedDaily(date: string): Promise<Map<string, DailyClose>> {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error(`Invalid trading date: ${date}`)
      // The key travels only in the Authorization header, so it can never appear in the URL, an error message or a log line.
      const url = `${baseUrl}/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true`

      let response: Response
      try {
        response = await fetchImpl(url, {
          headers: { Authorization: `Bearer ${options.apiKey}`, Accept: "application/json" },
          signal: AbortSignal.timeout(options.timeoutMs ?? MASSIVE_TIMEOUT_MS),
        })
      } catch (error) {
        throw new ProviderError("massive", isTimeout(error) ? "timeout" : "upstream")
      }

      if (response.status === 429) throw new ProviderError("massive", "rate_limited", parseRetryAfter(response.headers.get("retry-after")), 429)
      if (response.status >= 500) throw new ProviderError("massive", "upstream", undefined, response.status)
      if (!response.ok) throw new ProviderError("massive", "bad_response", undefined, response.status)

      // The timeout signal also covers the body download, so a failed read is a timeout/upstream error, not a bad body.
      let text: string
      try {
        text = await response.text()
      } catch (error) {
        throw new ProviderError("massive", isTimeout(error) ? "timeout" : "upstream", undefined, response.status)
      }
      let body: unknown
      try {
        body = JSON.parse(text)
      } catch {
        throw new ProviderError("massive", "bad_response", undefined, response.status)
      }
      return parseGroupedDaily(body)
    },
  }
}

export function parseGroupedDaily(body: unknown): Map<string, DailyClose> {
  const closes = new Map<string, DailyClose>()
  const results = typeof body === "object" && body !== null ? (body as { results?: unknown }).results : undefined
  if (!Array.isArray(results)) return closes
  for (const entry of results as Array<GroupedResult | null>) {
    if (typeof entry !== "object" || entry === null) continue
    if (typeof entry.T !== "string" || typeof entry.c !== "number" || !Number.isFinite(entry.c) || typeof entry.t !== "number") continue
    closes.set(entry.T, { symbol: entry.T, close: String(entry.c), at: new Date(entry.t) })
  }
  return closes
}
