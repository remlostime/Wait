import type { EvaluableItem } from "../../src/db/AlertRepository.js"
import type { LadderInput } from "../../src/domain/ladder.js"
import type { LogSink } from "../../src/lib/logSink.js"
import type { CloseResolution, CloseResolver } from "../../src/services/DailyCloseResolver.js"

function ladder(values: Partial<Record<keyof LadderInput, string>>): LadderInput {
  return { buyLow: null, buyHigh: null, fair: null, trim: null, sell: null, ...values }
}

export function scenarioItems(): EvaluableItem[] {
  return [
    { userId: "user-1", symbol: "AAPL", ladder: ladder({ buyLow: "150", buyHigh: "175", fair: "210", trim: "240", sell: "260" }), lastStatus: "WATCH", lastEvaluatedPrice: "180" },
    { userId: "user-1", symbol: "MSFT", ladder: ladder({ buyHigh: "300", trim: "450" }), lastStatus: null, lastEvaluatedPrice: null },
    { userId: "user-2", symbol: "NVDA", ladder: ladder({ buyHigh: "100", trim: "180" }), lastStatus: "WATCH", lastEvaluatedPrice: "170" },
    { userId: "user-2", symbol: "TSLA", ladder: ladder({ buyLow: "100", buyHigh: "120", fair: "200" }), lastStatus: "WATCH", lastEvaluatedPrice: "300" },
    { userId: "user-1", symbol: "AMD", ladder: ladder({ buyHigh: "100" }), lastStatus: "BUY_ZONE", lastEvaluatedPrice: "95" },
    { userId: "user-2", symbol: "BRK.B", ladder: ladder({ buyHigh: "400" }), lastStatus: "WATCH", lastEvaluatedPrice: "470" },
  ]
}

export const SCENARIO_RESOLUTION: CloseResolution = {
  kind: "closes",
  closes: new Map([["AAPL", "172.1"], ["MSFT", "420"], ["NVDA", "185"], ["TSLA", "30"], ["AMD", "90"]]),
  groupedCount: 5,
  fallbackCount: 0,
  missing: ["BRK.B"],
}

export class FakeCloseResolver implements CloseResolver {
  readonly calls: Array<{ tradingDate: string; symbols: string[] }> = []
  private readonly result: CloseResolution

  constructor(result: CloseResolution) {
    this.result = result
  }

  async resolve(tradingDate: string, symbols: string[], _log?: LogSink): Promise<CloseResolution> {
    this.calls.push({ tradingDate, symbols: [...symbols] })
    return this.result
  }
}
