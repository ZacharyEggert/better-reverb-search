"use client";

import { priceStats, type Listing } from "@better-reverb-search/reverb-api";

export function StatsBar({
  listings,
  total,
  sold,
}: {
  listings: Listing[];
  total: number;
  sold: boolean;
}) {
  const stats = priceStats(listings);
  if (!stats) return null;

  const money = (n: number) =>
    new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: stats.currency,
      maximumFractionDigits: 0,
    }).format(n);

  return (
    <div className="rounded-lg border border-[var(--color-line)] p-4">
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Stat label={sold ? "Lowest sold" : "Lowest ask"} value={money(stats.min)} />
        <Stat
          label={sold ? "Median sold" : "Median ask"}
          value={money(stats.median)}
          emphasis
        />
        <Stat label={sold ? "Highest sold" : "Highest ask"} value={money(stats.max)} />
        <Stat label="In sample" value={String(stats.count)} />
      </div>
      {/* The API caps out at 50 pages; stats can only ever describe what we loaded. */}
      <p className="mt-3 text-xs text-[var(--color-muted)]">
        Computed over the {stats.count} loaded{" "}
        {sold ? "sold listings" : "listings"} — not all{" "}
        {total.toLocaleString()} matches.
      </p>
    </div>
  );
}

function Stat({
  label,
  value,
  emphasis,
}: {
  label: string;
  value: string;
  emphasis?: boolean;
}) {
  return (
    <div>
      <div className="text-xs text-[var(--color-muted)]">{label}</div>
      <div
        className={`tnum ${emphasis ? "text-2xl font-semibold text-[var(--color-accent)]" : "text-2xl font-medium"}`}
      >
        {value}
      </div>
    </div>
  );
}
