"use client";

import {
  CONDITIONS,
  CONDITION_BUCKETS,
  PRODUCT_TYPES,
  SORTS,
  type SearchQuery,
} from "@better-reverb-search/reverb-api";
import { useState } from "react";

// Cadence: --rc-inputs-border-radius is radius-md, NOT full — only buttons are
// pills (--rc-buttons-border-radius: radius-full). Border is --rc-inputs-color-border.
const field =
  "w-full rounded-[var(--radius-input)] border border-[var(--color-line-input)] bg-[var(--color-input-bg)] px-3 py-2 text-sm outline-none focus:border-[var(--color-line-strong)]";
const label = "block text-xs font-medium text-[var(--color-muted)] mb-1";

export interface SearchFormProps {
  value: SearchQuery;
  onChange: (next: SearchQuery) => void;
  onSubmit: () => void;
  loading: boolean;
}

export function SearchForm({ value, onChange, onSubmit, loading }: SearchFormProps) {
  const set = <K extends keyof SearchQuery>(key: K, v: SearchQuery[K]) =>
    onChange({ ...value, [key]: v });

  const num = (s: string) => (s === "" ? undefined : Number(s));

  // Mobile-only collapse: the grid is `sm:grid` regardless, so this state is
  // inert at desktop widths and the toggle that drives it is `sm:hidden`.
  const [filtersOpen, setFiltersOpen] = useState(false);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit();
      }}
      className="space-y-4"
    >
      {/* Reverb's search field is a tall, full-strength-bordered box. */}
      <div className="flex gap-2">
        <input
          // --rc-inputs-size-height: 4.8rem
          className="h-12 w-full rounded-[var(--radius-input)] border border-[var(--color-line-strong)] bg-[var(--color-input-bg)] px-3 text-base outline-none"
          placeholder="Search Reverb — e.g. 1963 Stratocaster"
          value={value.query ?? ""}
          onChange={(e) => set("query", e.target.value)}
          aria-label="Search query"
        />
        <button
          type="submit"
          disabled={loading}
          // --rc-buttons-color-background-loud + radius-full + semibold,
          // disabled at --rc-buttons-opacity-disabled: 0.5.
          className="h-12 shrink-0 rounded-full bg-[var(--color-accent)] px-6 text-base font-semibold text-white transition-colors hover:bg-[var(--color-accent-hovered)] disabled:opacity-50"
        >
          {loading ? "Searching…" : "Search"}
        </button>
      </div>

      <button
        type="button"
        onClick={() => setFiltersOpen(!filtersOpen)}
        aria-expanded={filtersOpen}
        aria-controls="filters"
        className="rounded-full border border-[var(--color-line)] px-4 py-1.5 text-sm text-[var(--color-muted)] sm:hidden"
      >
        {filtersOpen ? "Hide filters" : "Filters"}
      </button>

      <div
        id="filters"
        className={`${filtersOpen ? "grid" : "hidden"} grid-cols-2 gap-3 sm:grid sm:grid-cols-3 lg:grid-cols-6`}
      >
        <div>
          <label className={label} htmlFor="make">
            Make
          </label>
          <input
            id="make"
            className={field}
            value={value.make ?? ""}
            onChange={(e) => set("make", e.target.value || undefined)}
          />
        </div>
        <div>
          <label className={label} htmlFor="model">
            Model
          </label>
          <input
            id="model"
            className={field}
            value={value.model ?? ""}
            onChange={(e) => set("model", e.target.value || undefined)}
          />
        </div>
        <div>
          <label className={label} htmlFor="productType">
            Category
          </label>
          <select
            id="productType"
            className={field}
            value={value.productType ?? ""}
            onChange={(e) => set("productType", (e.target.value || undefined) as never)}
          >
            <option value="">All</option>
            {PRODUCT_TYPES.map((p) => (
              <option key={p} value={p}>
                {p.replace(/-/g, " ")}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className={label} htmlFor="condition">
            Condition
          </label>
          <select
            id="condition"
            className={field}
            value={value.condition ?? ""}
            onChange={(e) => set("condition", (e.target.value || undefined) as never)}
          >
            <option value="">Any</option>
            {CONDITION_BUCKETS.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
            {/* Grades are a slice of `used`, so they read as a sub-list. */}
            <optgroup label="Used — by grade">
              {CONDITIONS.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </optgroup>
          </select>
        </div>
        <div>
          <label className={label} htmlFor="sort">
            Sort
          </label>
          <select
            id="sort"
            className={field}
            value={value.sort ?? ""}
            onChange={(e) => set("sort", (e.target.value || undefined) as never)}
          >
            <option value="">Newest first</option>
            {SORTS.map((s) => (
              <option key={s} value={s}>
                {s.replace("|", " ")}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className={label} htmlFor="priceMin">
            Price min
          </label>
          <input
            id="priceMin"
            type="number"
            min={0}
            className={`${field} tnum`}
            value={value.priceMin ?? ""}
            onChange={(e) => set("priceMin", num(e.target.value))}
          />
        </div>
        <div>
          <label className={label} htmlFor="priceMax">
            Price max
          </label>
          <input
            id="priceMax"
            type="number"
            min={0}
            className={`${field} tnum`}
            value={value.priceMax ?? ""}
            onChange={(e) => set("priceMax", num(e.target.value))}
          />
        </div>
        <div>
          <label className={label} htmlFor="yearMin">
            Year min
          </label>
          <input
            id="yearMin"
            type="number"
            className={`${field} tnum`}
            value={value.yearMin ?? ""}
            onChange={(e) => set("yearMin", num(e.target.value))}
          />
        </div>
        <div>
          <label className={label} htmlFor="yearMax">
            Year max
          </label>
          <input
            id="yearMax"
            type="number"
            className={`${field} tnum`}
            value={value.yearMax ?? ""}
            onChange={(e) => set("yearMax", num(e.target.value))}
          />
        </div>
        <div>
          <label className={label} htmlFor="perPage">
            Per page
          </label>
          <select
            id="perPage"
            className={field}
            value={value.perPage ?? 24}
            onChange={(e) => set("perPage", Number(e.target.value))}
          >
            {[12, 24, 50, 90].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </div>
      </div>
    </form>
  );
}
