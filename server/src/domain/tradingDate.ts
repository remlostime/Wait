/** The America/New_York calendar date ("YYYY-MM-DD") of an instant. Plan 04's calendar already computes it. */
export { etDateString as easternDate } from "./marketCalendar.js"

/** True for Saturday and Sunday. US market holidays are detected separately (DailyCloseResolver's SPY check). */
export function isWeekend(tradingDate: string): boolean {
  const weekday = new Date(`${tradingDate}T12:00:00.000Z`).getUTCDay()
  return weekday === 0 || weekday === 6
}
