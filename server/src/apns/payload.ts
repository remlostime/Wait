import type { LadderInput, LadderStatus } from "../domain/ladder.js"

export type ApnsPayload = { body: string; collapseId: string }

export type AlertPayloadInput = {
  symbol: string
  status: LadderStatus
  price: string
  ladder: LadderInput
  temperature: number | null
  tradingDate: string
}

const TITLES: Record<LadderStatus, string> = {
  DEEP_BUY: "DEEP BUY",
  BUY_ZONE: "BUY ZONE",
  WATCH: "WATCH",
  AT_OR_ABOVE_FAIR: "AT/ABOVE FAIR",
  TRIM: "TRIM",
  SELL: "SELL",
  NO_ANCHORS: "NO ANCHORS",
}

function money(value: string): string {
  return `$${Number(value).toFixed(2)}`
}

function rungPhrase(status: LadderStatus, ladder: LadderInput): string | null {
  switch (status) {
    case "DEEP_BUY":
      return ladder.buyLow ? `at or below buy-low ${money(ladder.buyLow)}` : null
    case "BUY_ZONE":
      return ladder.buyHigh ? `at or below buy-high ${money(ladder.buyHigh)}` : null
    case "TRIM":
      return ladder.trim ? `at or above trim ${money(ladder.trim)}` : null
    case "SELL":
      return ladder.sell ? `at or above sell ${money(ladder.sell)}` : null
    default:
      return null
  }
}

/** The APNs JSON body (key order is part of the contract) and its collapse id "<SYMBOL>-<tradingDate>". */
export function buildPayload(input: AlertPayloadInput): ApnsPayload {
  const phrase = rungPhrase(input.status, input.ladder)
  let body = phrase === null ? `Closed ${money(input.price)}` : `Closed ${money(input.price)}, ${phrase}`
  if (input.temperature !== null) body += ` · ${Math.round(input.temperature)}°`

  const payload = {
    aps: { alert: { title: `${input.symbol} · ${TITLES[input.status]}`, body }, sound: "default", "thread-id": input.symbol },
    symbol: input.symbol,
    status: input.status,
    deepLink: `wait://stock/${input.symbol}`,
  }
  return { body: JSON.stringify(payload), collapseId: `${input.symbol}-${input.tradingDate}` }
}
