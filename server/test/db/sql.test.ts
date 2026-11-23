import { PGlite } from "@electric-sql/pglite"
import { afterEach, describe, expect, it } from "vitest"
import { pgliteSql, toParameterized } from "../../src/db/sql.js"

const tag = (strings: TemplateStringsArray, ...values: unknown[]) => toParameterized(strings, values)
let db: PGlite | undefined

afterEach(async () => {
  await db?.close()
  db = undefined
})

describe("toParameterized", () => {
  it("numbers interpolations as $1..$n", () => {
    expect(tag`SELECT ${1}::int + ${2}::int AS total WHERE ${"x"} = ${"x"}`).toEqual({
      text: "SELECT $1::int + $2::int AS total WHERE $3 = $4",
      values: [1, 2, "x", "x"],
    })
  })
})

describe("pgliteSql", () => {
  it("runs a parameterized tagged query against PGlite", async () => {
    db = new PGlite()
    const sql = pgliteSql(db)
    const rows = await sql`SELECT ${20}::int + ${22}::int AS total, ${JSON.stringify(["A", "B"])}::jsonb AS list`
    expect(rows).toEqual([{ total: 42, list: ["A", "B"] }])
  })
})
