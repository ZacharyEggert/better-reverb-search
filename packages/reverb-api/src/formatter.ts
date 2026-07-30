import { RevError } from "./error.js";

/**
 * Port of `reverb-api-cli/src/formatter.rs`.
 *
 * The Rust version writes into a `&mut dyn Write`. There is no stdout in a
 * browser, so each function returns the string it would have written; a CLI
 * host writes it, the web app renders it (used for CSV/JSON export).
 */
export type Format = "json" | "table" | "yaml" | "csv";

/** `page` is 0-indexed; headers/separators are only emitted on page 0. */
export function format(
  value: unknown,
  fmt: Format | "",
  page: number,
): string {
  switch (fmt) {
    case "json":
    case "":
      return formatJson(value, page);
    case "table":
      return formatTable(value, page);
    case "yaml":
      return formatYaml(value, page);
    case "csv":
      return formatCsv(value, page);
    default:
      throw RevError.validation(`unknown format '${fmt}'`);
  }
}

function formatJson(value: unknown, page: number): string {
  // NDJSON for subsequent pages, pretty for the first.
  return page === 0
    ? `${JSON.stringify(value, null, 2)}\n`
    : `${JSON.stringify(value)}\n`;
}

function formatTable(value: unknown, page: number): string {
  const rows = extractRows(value);
  if (rows.length === 0) {
    return page === 0 ? "(no results)\n" : "";
  }

  const columns = collectColumns(rows);
  const widths = columns.map((c) => c.length);
  for (const row of rows) {
    columns.forEach((col, i) => {
      widths[i] = Math.max(widths[i]!, cellStr(row[col]).length);
    });
  }

  const out: string[] = [];
  if (page === 0) {
    const header = columns.map((c, i) => c.padEnd(widths[i]!)).join("  ");
    out.push(header, "-".repeat(header.length));
  }
  for (const row of rows) {
    out.push(columns.map((c, i) => cellStr(row[c]).padEnd(widths[i]!)).join("  "));
  }
  return `${out.join("\n")}\n`;
}

function formatYaml(value: unknown, page: number): string {
  // Simple YAML-like output, same caveat as the Rust original.
  const prefix = page > 0 ? "---\n" : "";
  return `${prefix}${JSON.stringify(value, null, 2)}\n`;
}

function formatCsv(value: unknown, page: number): string {
  const rows = extractRows(value);
  if (rows.length === 0) return "";

  const columns = collectColumns(rows);
  const out: string[] = [];
  if (page === 0) out.push(columns.join(","));
  for (const row of rows) {
    out.push(columns.map((c) => csvEscape(cellStr(row[c]))).join(","));
  }
  return `${out.join("\n")}\n`;
}

/** Extract the inner data array from a response, or wrap the value in an array. */
function extractRows(value: unknown): Record<string, unknown>[] {
  // Common Reverb response shapes: { "listings": [...] } or just [...]
  if (Array.isArray(value)) return value as Record<string, unknown>[];
  if (isObject(value)) {
    for (const key of [
      "listings",
      "orders",
      "conversations",
      "items",
      "results",
      "data",
    ]) {
      const inner = value[key];
      if (Array.isArray(inner)) return inner as Record<string, unknown>[];
    }
    return [value];
  }
  return [{ value } as Record<string, unknown>];
}

function collectColumns(rows: Record<string, unknown>[]): string[] {
  const columns: string[] = [];
  for (const row of rows) {
    for (const k of Object.keys(row)) {
      if (!columns.includes(k)) columns.push(k);
    }
  }
  return columns;
}

function cellStr(v: unknown): string {
  if (v === undefined || v === null) return "";
  return typeof v === "string" ? v : JSON.stringify(v);
}

function csvEscape(s: string): string {
  return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
