import { toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import { ProviderError, type Bar, type DailyBarsProvider } from "./types.js"

interface TiingoDailyRow {
  date: string
  adjClose: number
}

export class TiingoProvider implements DailyBarsProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://api.tiingo.com",
  ) {}

  async getDailyBars(symbol: string, from: string, to: string): Promise<Bar[]> {
    const ticker = symbol.toLowerCase().replace(".", "-")
    const url = new URL(`${this.baseUrl}/tiingo/daily/${encodeURIComponent(ticker)}/prices`)
    url.searchParams.set("startDate", from)
    url.searchParams.set("endDate", to)
    url.searchParams.set("resampleFreq", "daily")
    let body: unknown
    try {
      body = await getJson<unknown>(this.fetchImpl, url.toString(), {
        provider: "tiingo",
        headers: { Authorization: `Token ${this.apiKey}` },
      })
    } catch (error) {
      if (error instanceof ProviderError && error.kind === "not_found") return []
      throw error
    }
    // Tiingo sometimes answers 200 with {"detail": "..."} instead of an array.
    if (!Array.isArray(body)) throw new ProviderError("tiingo", "bad_response")
    const rows = body as TiingoDailyRow[]
    return rows
      .filter((row) => typeof row.adjClose === "number" && Number.isFinite(row.adjClose))
      .map((row) => ({ t: new Date(row.date).toISOString(), c: toDecimalString(row.adjClose) }))
  }
}
