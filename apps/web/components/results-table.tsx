"use client";

import {
  CONDITIONS,
  discountPercent,
  listingUrl,
  type Listing,
} from "@better-reverb-search/reverb-api";
import { useMemo, useState } from "react";

type SortKey = "title" | "price" | "year" | "condition" | "shop" | "discount";

/** Worst → best, so a condition sort reads as an ascending quality ramp. */
const CONDITION_RANK = new Map(
  [...CONDITIONS].reverse().map((c, i) => [c, i] as const),
);

/**
 * Dense sortable table. Sorting is client-side over the loaded page only —
 * Reverb's own `sort` param reorders the entire result set server-side, which
 * is a different (and slower) question. Both are available.
 */
export function ResultsTable({
  listings,
  sold,
}: {
  listings: Listing[];
  sold: boolean;
}) {
  const [key, setKey] = useState<SortKey>("price");
  const [asc, setAsc] = useState(true);

  const sorted = useMemo(() => {
    const dir = asc ? 1 : -1;
    return [...listings].sort((a, b) => dir * compare(a, b, key));
  }, [listings, key, asc]);

  const toggle = (next: SortKey) => {
    if (next === key) setAsc(!asc);
    else {
      setKey(next);
      setAsc(true);
    }
  };

  const columns: [SortKey, string][] = [
    ["title", "Listing"],
    ["year", "Year"],
    ["condition", "Condition"],
    ...(sold ? ([["discount", "Ask / Off"]] as [SortKey, string][]) : []),
    ["price", sold ? "Sold" : "Price"],
    ["shop", "Shop"],
  ];

  return (
    <div className="overflow-x-auto rounded-[var(--radius-module)] border border-[var(--color-line)]">
      <table className="w-full min-w-3xl text-sm">
        <thead>
          <tr className="border-b border-[var(--color-line)] text-left">
            {columns.map(([k, headerLabel]) => (
              <th key={k} className="p-2 font-medium">
                <button
                  type="button"
                  onClick={() => toggle(k)}
                  className="flex items-center gap-1 text-[var(--color-muted)] hover:text-[var(--color-ink)]"
                  aria-sort={
                    key === k ? (asc ? "ascending" : "descending") : "none"
                  }
                >
                  {headerLabel}
                  <span aria-hidden className="text-[10px]">
                    {key === k ? (asc ? "▲" : "▼") : "↕"}
                  </span>
                </button>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((l) => {
            const off = discountPercent(l);
            return (
              <tr
                key={l.id}
                className="border-b border-[var(--color-line)] last:border-0 hover:bg-[var(--color-overlay-hovered)]"
              >
                <td className="max-w-md p-2">
                  <a
                    href={listingUrl(l) ?? "#"}
                    target="_blank"
                    rel="noreferrer noopener"
                    className="hover:underline"
                  >
                    {l.title}
                  </a>
                </td>
                <td className="tnum p-2 text-[var(--color-muted)]">
                  {l.year ?? "—"}
                </td>
                <td className="p-2 text-[var(--color-muted)]">
                  {l.condition?.display_name ?? "—"}
                </td>
                {sold && (
                  <td className="tnum p-2 text-[var(--color-muted)]">
                    {l.original_price?.display ?? "—"}
                    {off !== undefined && (
                      <span className="ml-1 font-medium text-[var(--color-sale)]">
                        −{off}%
                      </span>
                    )}
                  </td>
                )}
                <td className="tnum p-2 font-medium">{l.price?.display}</td>
                <td className="max-w-40 truncate p-2 text-[var(--color-muted)]">
                  {l.shop_name}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function compare(a: Listing, b: Listing, key: SortKey): number {
  switch (key) {
    case "price":
      return (a.price?.amount_cents ?? 0) - (b.price?.amount_cents ?? 0);
    case "year":
      // Years are free-text strings on Reverb ("1963", "2020s", null).
      return (Number(a.year) || 0) - (Number(b.year) || 0);
    case "condition":
      return (
        (CONDITION_RANK.get(a.condition?.slug as never) ?? -1) -
        (CONDITION_RANK.get(b.condition?.slug as never) ?? -1)
      );
    case "discount":
      return (discountPercent(a) ?? -1) - (discountPercent(b) ?? -1);
    case "shop":
      return (a.shop_name ?? "").localeCompare(b.shop_name ?? "");
    case "title":
      return (a.title ?? "").localeCompare(b.title ?? "");
  }
}
