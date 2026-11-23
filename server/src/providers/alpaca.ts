import type { Clock } from "../lib/clock.js"
import { toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import { ProviderError, type Bar, type IntradayBarsProvider, type IntradayTimeframe } from "./types.js"

interface AlpacaBarsResponse {
  bars: Array<{ t: string; c: number }> | null
  next_page_token: string | null
}

/** Basic (free) plan: full SIP tape, but nothing from the latest 15 minutes. */
const SIP_DELAY_MS = 16 * 60_000
const MAX_BARS = 20_000
/** Guards against a provider that keeps returning page tokens (each page is one request on one bucket token). */
const MAX_PAGES = 10

export class AlpacaProvider implements IntradayBarsProvider {
  constructor(
    private readonly keyId: string,
    private readonly secretKey: string,
    private readonly clock: Clock,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://data.alpaca.markets",
  ) {}

  async getIntradayBars(symbol: string, timeframe: IntradayTimeframe, start: Date, end: Date): Promise<Bar[]> {
    const latestAllowed = this.clock.now().getTime() - SIP_DELAY_MS
    const clampedEnd = new Date(Math.min(end.getTime(), latestAllowed))
    // Alpaca answers an empty or inverted window with 422; there is simply nothing to fetch yet.
    if (clampedEnd.getTime() <= start.getTime()) return []
    const bars: Bar[] = []
    let pageToken: string | null = null
    let pages = 0
    do {
      const url = new URL(`${this.baseUrl}/v2/stocks/${encodeURIComponent(symbol)}/bars`)
      url.searchParams.set("timeframe", timeframe)
      url.searchParams.set("start", start.toISOString())
      url.searchParams.set("end", clampedEnd.toISOString())
      url.searchParams.set("feed", "sip")
      url.searchParams.set("adjustment", "split")
      url.searchParams.set("limit", "10000")
      url.searchParams.set("sort", "asc")
      if (pageToken) url.searchParams.set("page_token", pageToken)
      const body: AlpacaBarsResponse = await getJson<AlpacaBarsResponse>(this.fetchImpl, url.toString(), {
        provider: "alpaca",
        headers: { "APCA-API-KEY-ID": this.keyId, "APCA-API-SECRET-KEY": this.secretKey },
      })
      if (body.bars !== null && body.bars !== undefined && !Array.isArray(body.bars)) throw new ProviderError("alpaca", "bad_response")
      for (const bar of body.bars ?? []) {
        if (typeof bar?.t !== "string" || typeof bar.c !== "number") throw new ProviderError("alpaca", "bad_response")
        bars.push({ t: new Date(bar.t).toISOString(), c: toDecimalString(bar.c) })
      }
      const previousToken: string | null = pageToken
      pageToken = body.next_page_token === previousToken ? null : body.next_page_token
      pages += 1
    } while (pageToken && bars.length < MAX_BARS && pages < MAX_PAGES)
    return bars
  }
}
