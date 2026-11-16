// Minimale Typen für SQLite aus Node 22 (nur in Tests; der Worker selbst nutzt D1).
declare module "node:sqlite" {
  export class StatementSync {
    get(...values: unknown[]): Record<string, unknown> | undefined;
    all(...values: unknown[]): Record<string, unknown>[];
    run(...values: unknown[]): { changes: number | bigint };
  }
  export class DatabaseSync {
    constructor(path: string);
    exec(sql: string): void;
    prepare(sql: string): StatementSync;
  }
}
