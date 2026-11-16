import { DatabaseSync } from "node:sqlite";
import type { SqlDatabase, SqlStatement } from "../src/db";

/** D1-ähnliche Datenbank auf SQLite aus Node: gleiche SQL-Dialekte wie D1, für Tests ohne Cloudflare. */
export function memoryDatabase(): SqlDatabase & { raw: DatabaseSync } {
  const raw = new DatabaseSync(":memory:");
  const statement = (sql: string, values: unknown[] = []): SqlStatement => ({
    bind: (...next: unknown[]) => statement(sql, next),
    first: async <T>() => (raw.prepare(sql).get(...values) as T | undefined) ?? null,
    all: async <T>() => ({ results: raw.prepare(sql).all(...values) as T[] }),
    run: async () => ({ meta: { changes: Number(raw.prepare(sql).run(...values).changes) } }),
  });
  return {
    raw,
    prepare: (sql) => statement(sql),
    batch: async (statements) => {
      raw.exec("BEGIN");
      try {
        const results = [];
        for (const item of statements) results.push(await item.run());
        raw.exec("COMMIT");
        return results;
      } catch (error) {
        raw.exec("ROLLBACK");
        throw error;
      }
    },
  };
}
