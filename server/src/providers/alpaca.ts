import type { Clock } from "../lib/clock.js"
import { toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import type { Bar, IntradayBarsProvider, IntradayTimeframe } from "./types.js"

interface AlpacaBarsResponse {
  bars: Array<{ t: string; c: number }> | null
  next_page_token: string | null
}

/** Basic (free) plan: full SIP tape, but nothing from the latest 15 minutes. */
const SIP_DELAY_MS = 16 * 60_000
const MAX_BARS = 20_000

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
    const bars: Bar[] = []
    let pageToken: string | null = null
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
      for (const bar of body.bars ?? []) bars.push({ t: new Date(bar.t).toISOString(), c: toDecimalString(bar.c) })
      pageToken = body.next_page_token
    } while (pageToken && bars.length < MAX_BARS)
    return bars
  }
}
