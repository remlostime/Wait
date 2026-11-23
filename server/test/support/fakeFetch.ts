import { readFileSync } from "node:fs"
import path from "node:path"
import type { FetchLike } from "../../src/providers/http.js"

export interface FakeRoute {
  match: (url: URL) => boolean
  respond: (url: URL, init?: RequestInit) => Response | Promise<Response>
}

export interface FakeCall {
  url: URL
  init?: RequestInit
}

/** Records every call; unmatched URLs return HTTP 500 so tests fail loudly. */
export function fakeFetch(routes: FakeRoute[]): { fetch: FetchLike; calls: FakeCall[] } {
  const calls: FakeCall[] = []
  const impl: FetchLike = async (url, init) => {
    const parsed = new URL(url)
    calls.push({ url: parsed, init })
    const route = routes.find((r) => r.match(parsed))
    if (!route) return new Response(JSON.stringify({ error: `no fake route for ${parsed.pathname}` }), { status: 500 })
    return route.respond(parsed, init)
  }
  return { fetch: impl, calls }
}

export const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" }, ...init })

export function fixture(name: string): unknown {
  return JSON.parse(readFileSync(path.resolve(import.meta.dirname, "fixtures", name), "utf8"))
}

export function headerOf(init: RequestInit | undefined, name: string): string | null {
  return new Headers(init?.headers).get(name)
}
