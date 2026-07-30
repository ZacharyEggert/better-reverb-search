"use client";

import {
  CONDITIONS,
  SORTS,
  type SearchQuery,
} from "@better-reverb-search/reverb-api";

const field =
  "w-full rounded-md border border-[var(--color-line)] bg-transparent px-3 py-2 text-sm outline-none focus:border-[var(--color-accent)]";
const label = "block text-xs font-medium text-[var(--color-muted)] mb-1";

export interface SearchFormProps {
  value: SearchQuery;
  onChange: (next: SearchQuery) => void;
  onSubmit: () => void;
  loading: boolean;
}

export function SearchForm({
  value,
  onChange,
  onSubmit,
  loading,
}: SearchFormProps) {
  const set = <K extends keyof SearchQuery>(key: K, v: SearchQuery[K]) =>
    onChange({ ...value, [key]: v });

  const num = (s: string) => (s === "" ? undefined : Number(s));

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit();
      }}
      className="space-y-4"
    >
      <div className="flex gap-2">
        <input
          className={`${field} text-base`}
          placeholder="Search Reverb — e.g. 1963 Stratocaster"
          value={value.query ?? ""}
          onChange={(e) => set("query", e.target.value)}
          aria-label="Search query"
        />
        <button
          type="submit"
          disabled={loading}
          className="shrink-0 rounded-md bg-[var(--color-accent)] px-5 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {loading ? "Searching…" : "Search"}
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
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
          <label className={label} htmlFor="condition">
            Condition
          </label>
          <select
            id="condition"
            className={field}
            value={value.condition ?? ""}
            onChange={(e) =>
              set("condition", (e.target.value || undefined) as never)
            }
          >
            <option value="">Any</option>
            {CONDITIONS.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
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
            <option value="">Relevance</option>
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
