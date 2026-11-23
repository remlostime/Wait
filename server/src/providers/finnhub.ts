import { nullableDecimal, toDecimalString } from "../lib/decimal.js"
import { getJson, type FetchLike } from "./http.js"
import type { ProfileProvider, ProviderMetrics, ProviderProfile, ProviderQuote, QuoteProvider, SymbolMatch, SymbolSearchProvider } from "./types.js"

interface FinnhubQuote { c: number; d: number | null; dp: number | null; h: number; l: number; o: number; pc: number; t: number }
interface FinnhubSearch { count: number; result: Array<{ description: string; displaySymbol: string; symbol: string; type: string }> }
interface FinnhubProfile { exchange?: string; finnhubIndustry?: string; logo?: string; marketCapitalization?: number; name?: string; ticker?: string }
interface FinnhubMetric { metric: Record<string, number | null | undefined> }

const SEARCH_TYPES = new Set(["Common Stock", "ETP", "ADR"])
const SEARCH_SYMBOL = /^[A-Z]{1,5}(\.[A-Z])?$/
const positive = (n: number | null | undefined) => (typeof n === "number" && n > 0 ? toDecimalString(n) : null)
const finite = (n: number | null | undefined) => (typeof n === "number" && Number.isFinite(n) ? n : null)

export class FinnhubProvider implements QuoteProvider, SymbolSearchProvider, ProfileProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
    private readonly baseUrl = "https://finnhub.io/api/v1",
  ) {}

  private get<T>(path: string, params: Record<string, string>): Promise<T> {
    const url = new URL(`${this.baseUrl}${path}`)
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value)
    return getJson<T>(this.fetchImpl, url.toString(), { provider: "finnhub", headers: { "X-Finnhub-Token": this.apiKey } })
  }

  async getQuote(symbol: string): Promise<ProviderQuote | null> {
    const q = await this.get<FinnhubQuote>("/quote", { symbol })
    if (!q.c || !q.t) return null // Finnhub answers unknown symbols with an all-zero quote
    return {
      symbol,
      price: toDecimalString(q.c),
      previousClose: positive(q.pc),
      open: positive(q.o),
      high: positive(q.h),
      low: positive(q.l),
      change: nullableDecimal(q.d),
      changePercent: finite(q.dp),
      asOf: new Date(q.t * 1000).toISOString(),
    }
  }

  async search(query: string): Promise<SymbolMatch[]> {
    const body = await this.get<FinnhubSearch>("/search", { q: query, exchange: "US" })
    return body.result
      .filter((r) => SEARCH_TYPES.has(r.type) && SEARCH_SYMBOL.test(r.symbol))
      .map((r) => ({ symbol: r.symbol, name: r.description, exchange: null, type: r.type }))
  }

  async getProfile(symbol: string): Promise<ProviderProfile | null> {
    const p = await this.get<FinnhubProfile>("/stock/profile2", { symbol })
    if (!p.ticker && !p.name) return null
    return {
      symbol,
      name: p.name ?? null,
      exchange: p.exchange ?? null,
      industry: p.finnhubIndustry ?? null,
      logoUrl: p.logo ? p.logo : null,
      marketCap: typeof p.marketCapitalization === "number" ? toDecimalString(p.marketCapitalization * 1_000_000, 0) : null,
    }
  }

  /** Ratios are as Finnhub reports them: yield, ROE, ROA and margin are percentages (0.55 = 0.55%). */
  async getMetrics(symbol: string): Promise<ProviderMetrics | null> {
    const m = (await this.get<FinnhubMetric>("/stock/metric", { symbol, metric: "all" })).metric ?? {}
    const metrics: ProviderMetrics = {
      peRatio: finite(m.peBasicExclExtraTTM),
      pbRatio: finite(m.pbAnnual),
      dividendYield: finite(m.dividendYieldIndicatedAnnual),
      roe: finite(m.roeTTM),
      roa: finite(m.roaTTM),
      profitMargin: finite(m.netProfitMarginTTM),
      fiftyTwoWeekHigh: positive(m["52WeekHigh"]),
      fiftyTwoWeekLow: positive(m["52WeekLow"]),
      beta: finite(m.beta),
    }
    return Object.values(metrics).every((value) => value === null) ? null : metrics
  }
}
