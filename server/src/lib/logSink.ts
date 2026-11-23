/** The subset of pino's logger the alert job uses. Fastify's `request.log` satisfies it. */
export type LogSink = { info(details: object, message: string): void; warn(details: object, message: string): void }

export const silentLog: LogSink = { info: () => {}, warn: () => {} }
