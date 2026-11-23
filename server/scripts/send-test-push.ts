import { parseArgs } from "node:util"
import { config as loadEnv } from "dotenv"
import { ApnsTokenProvider } from "../src/apns/ApnsTokenProvider.js"
import { Http2ApnsTransport } from "../src/apns/Http2ApnsTransport.js"
import { buildPayload } from "../src/apns/payload.js"
import { parseLadderStatus } from "../src/domain/ladder.js"
import { systemClock } from "../src/lib/clock.js"

loadEnv({ path: ".env.development.local", quiet: true })
loadEnv({ path: ".env.local", override: true, quiet: true })

const { values } = parseArgs({
  options: {
    token: { type: "string" },
    env: { type: "string", default: "sandbox" },
    symbol: { type: "string", default: "AAPL" },
    status: { type: "string", default: "BUY_ZONE" },
    price: { type: "string", default: "172.10" },
  },
})

function requireEnv(name: string): string {
  const value = process.env[name]
  if (value === undefined || value === "") throw new Error(`${name} is not set (put it in server/.env.local)`)
  return value
}

const token = values.token
if (token === undefined || !/^[0-9a-f]{64,200}$/.test(token)) throw new Error("--token <lowercase hex APNs device token> is required")
const environment = (values.env ?? "sandbox") === "production" ? "production" : "sandbox"
const status = parseLadderStatus(values.status ?? "BUY_ZONE")
if (status === null) throw new Error(`Unknown --status ${String(values.status)}`)
const symbol = values.symbol ?? "AAPL"
const price = values.price ?? "172.10"

const tokens = new ApnsTokenProvider(
  { key: requireEnv("APNS_KEY"), keyId: requireEnv("APNS_KEY_ID"), teamId: requireEnv("APNS_TEAM_ID") },
  systemClock,
)
const payload = buildPayload({
  symbol,
  status,
  price,
  ladder: { buyLow: "150.00", buyHigh: "175.00", fair: "210.00", trim: "240.00", sell: "260.00" },
  temperature: null,
  tradingDate: new Date().toISOString().slice(0, 10),
})

const transport = new Http2ApnsTransport()
const response = await transport.send({
  environment,
  deviceToken: token,
  body: payload.body,
  headers: {
    authorization: `bearer ${tokens.token()}`,
    "apns-topic": process.env.APNS_TOPIC ?? "com.chenkai.wait",
    "apns-push-type": "alert",
    "apns-priority": "10",
    "apns-collapse-id": payload.collapseId,
  },
})
await transport.close()
console.log(JSON.stringify({ environment, ...response }))
process.exit(response.status === 200 ? 0 : 1)
