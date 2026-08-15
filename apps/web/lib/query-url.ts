import type { SearchQuery } from "@better-reverb-search/reverb-api";

const NUM_KEYS = ["priceMin", "priceMax", "yearMin", "yearMax", "page", "perPage"] as const;

// ponytail: `extra` isn't serialized — nothing in the UI sets it.
const STR_KEYS = [
  "query",
  "make",
  "model",
  "category",
  "productType",
  "condition",
  "sort",
  "shipsTo",
] as const;

/** SearchQuery + view → `?q=...&view=grid`. Empty values are omitted. */
export function toSearchParams(query: SearchQuery, view: string): string {
  const p = new URLSearchParams();
  for (const k of STR_KEYS) if (query[k]) p.set(k, String(query[k]));
  for (const k of NUM_KEYS) if (query[k] !== undefined) p.set(k, String(query[k]));
  if (query.showOnlySold) p.set("showOnlySold", "1");
  if (view !== "table") p.set("view", view);
  return p.toString();
}

export function fromSearchParams(search: string): {
  query: SearchQuery;
  view: string | null;
} {
  const p = new URLSearchParams(search);
  const query: SearchQuery = {};
  for (const k of STR_KEYS) {
    const v = p.get(k);
    if (v) query[k] = v as never;
  }
  for (const k of NUM_KEYS) {
    const v = p.get(k);
    if (v !== null && v !== "" && !Number.isNaN(Number(v))) query[k] = Number(v);
  }
  if (p.get("showOnlySold")) query.showOnlySold = true;
  return { query, view: p.get("view") };
}
