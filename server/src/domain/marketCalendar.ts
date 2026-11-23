const ET = "America/New_York"
const OPEN_MINUTES = 9 * 60 + 30
const CLOSE_MINUTES = 16 * 60
const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }

const formatter = new Intl.DateTimeFormat("en-US", {
  timeZone: ET,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
  weekday: "short",
})

export interface EtParts {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
  /** 0 = Sunday … 6 = Saturday */
  weekday: number
}

interface CalendarDay {
  year: number
  month: number
  day: number
  weekday: number
}

export function etParts(at: Date): EtParts {
  const parts = Object.fromEntries(formatter.formatToParts(at).map((part) => [part.type, part.value]))
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
    weekday: WEEKDAYS[parts.weekday ?? ""] ?? 0,
  }
}

const pad = (n: number) => String(n).padStart(2, "0")

/** ET calendar date as YYYY-MM-DD (the "trading date" of an instant). */
export function etDateString(at: Date): string {
  const p = etParts(at)
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`
}

function offsetMs(at: Date): number {
  const p = etParts(at)
  const wallAsUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second)
  return wallAsUtc - Math.floor(at.getTime() / 1000) * 1000
}

/** Converts an ET wall-clock time (outside the 02:00 DST gap) to a UTC instant. */
export function etWallTimeToUtc(year: number, month: number, day: number, hour: number, minute: number): Date {
  const guess = Date.UTC(year, month - 1, day, hour, minute)
  const first = guess - offsetMs(new Date(guess))
  return new Date(guess - offsetMs(new Date(first)))
}

function addDays(day: { year: number; month: number; day: number }, n: number): CalendarDay {
  const d = new Date(Date.UTC(day.year, day.month - 1, day.day + n))
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(), weekday: d.getUTCDay() }
}

const isWeekday = (weekday: number) => weekday >= 1 && weekday <= 5
const atMinutes = (d: CalendarDay, minutes: number) => etWallTimeToUtc(d.year, d.month, d.day, Math.floor(minutes / 60), minutes % 60)

export function isMarketOpen(at: Date): boolean {
  const p = etParts(at)
  if (!isWeekday(p.weekday)) return false
  const minutes = p.hour * 60 + p.minute
  return minutes >= OPEN_MINUTES && minutes < CLOSE_MINUTES
}

/** Bar start times inside the regular session (Alpaca returns extended hours too). */
export const isRegularSessionTime = isMarketOpen

function scan(from: Date, direction: 1 | -1, minutes: number, accept: (candidate: Date) => boolean): Date {
  const start = etParts(from)
  for (let k = 0; k <= 8; k += 1) {
    const day = addDays(start, direction * k)
    if (!isWeekday(day.weekday)) continue
    const candidate = atMinutes(day, minutes)
    if (accept(candidate)) return candidate
  }
  throw new Error(`No session boundary found near ${from.toISOString()}`)
}

export function nextOpen(after: Date): Date {
  return scan(after, 1, OPEN_MINUTES, (c) => c.getTime() > after.getTime())
}

export function nextClose(after: Date): Date {
  return scan(after, 1, CLOSE_MINUTES, (c) => c.getTime() > after.getTime())
}

export function lastSessionOpen(atOrBefore: Date): Date {
  return scan(atOrBefore, -1, OPEN_MINUTES, (c) => c.getTime() <= atOrBefore.getTime())
}
