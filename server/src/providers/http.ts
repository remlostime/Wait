import { ProviderError, type ProviderName } from "./types.js"

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>

export interface GetJsonOptions {
  provider: ProviderName
  headers?: Record<string, string>
  timeoutMs?: number
}

export function parseRetryAfter(value: string | null): number | undefined {
  if (!value) return undefined
  const seconds = Number(value)
  if (Number.isFinite(seconds) && seconds >= 0) return seconds
  const date = Date.parse(value)
  return Number.isNaN(date) ? undefined : Math.max(0, Math.ceil((date - Date.now()) / 1000))
}

/** GET + JSON with an 8 s timeout. Keys travel in headers only, never in the URL. */
export async function getJson<T>(fetchImpl: FetchLike, url: string, options: GetJsonOptions): Promise<T> {
  const { provider } = options
  let response: Response
  try {
    response = await fetchImpl(url, {
      method: "GET",
      headers: { accept: "application/json", ...options.headers },
      signal: AbortSignal.timeout(options.timeoutMs ?? 8_000),
    })
  } catch (error) {
    const name = (error as { name?: string }).name
    throw new ProviderError(provider, name === "TimeoutError" || name === "AbortError" ? "timeout" : "upstream")
  }
  if (response.status === 429) throw new ProviderError(provider, "rate_limited", parseRetryAfter(response.headers.get("retry-after")), 429)
  if (response.status === 404) throw new ProviderError(provider, "not_found", undefined, 404)
  if (!response.ok) throw new ProviderError(provider, "upstream", undefined, response.status)
  const text = await response.text()
  try {
    return JSON.parse(text) as T
  } catch {
    throw new ProviderError(provider, "bad_response", undefined, response.status)
  }
}
