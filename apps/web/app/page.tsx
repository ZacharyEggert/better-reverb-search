"use client";

import type { SearchQuery } from "@better-reverb-search/reverb-api";
import { useState } from "react";
import { ResultsGrid } from "@/components/results-grid";
import { ResultsTable } from "@/components/results-table";
import { SearchForm } from "@/components/search-form";
import { StatsBar } from "@/components/stats-bar";
import { useSearch } from "@/lib/use-search";

type View = "table" | "grid";

export default function Page() {
  const [query, setQuery] = useState<SearchQuery>({ perPage: 24 });
  const [view, setView] = useState<View>("table");
  const { result, error, loading, run } = useSearch();

  // The mode the current *results* were fetched in — not the pending toggle
  // state, so the table doesn't render Ask/Off columns against active listings.
  const [resultsAreSold, setResultsAreSold] = useState(false);

  const search = (next: SearchQuery = query, page = 1) => {
    const q = { ...next, page };
    setQuery(q);
    setResultsAreSold(q.showOnlySold === true);
    void run(q);
  };

  const sold = query.showOnlySold === true;
  const totalPages = result ? Math.min(result.totalPages, 50) : 0;
  const currentPage = result?.currentPage ?? 1;

  return (
    <main className="mx-auto max-w-7xl space-y-6 p-6">
      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">
          Better Reverb Search
        </h1>
        <div className="flex items-center gap-2">
          <Toggle
            active={sold}
            onClick={() => search({ ...query, showOnlySold: !sold })}
          >
            {sold ? "Sold comps" : "Active listings"}
          </Toggle>
          <Toggle
            active={view === "table"}
            onClick={() => setView(view === "table" ? "grid" : "table")}
          >
            {view === "table" ? "Table" : "Grid"}
          </Toggle>
        </div>
      </header>

      <SearchForm
        value={query}
        onChange={setQuery}
        onSubmit={() => search(query, 1)}
        loading={loading}
      />

      {error && (
        <p
          role="alert"
          className="rounded-md border border-[var(--color-accent)] p-3 text-sm text-[var(--color-accent)]"
        >
          {error}
        </p>
      )}

      {result && (
        <>
          <div className="flex flex-wrap items-baseline justify-between gap-2 text-sm text-[var(--color-muted)]">
            <span>
              <strong className="tnum text-[var(--color-ink)]">
                {result.total.toLocaleString()}
              </strong>{" "}
              matches
              {/* Reverb echoes how it actually parsed the filters. Surfacing it
                  is the cheapest guard against a filter silently doing nothing. */}
              {result.humanizedParams && ` — ${result.humanizedParams}`}
            </span>
            {totalPages > 1 && (
              <span className="flex items-center gap-2">
                <Pager
                  disabled={currentPage <= 1 || loading}
                  onClick={() => search(query, currentPage - 1)}
                >
                  ← Prev
                </Pager>
                <span className="tnum">
                  {currentPage} / {totalPages}
                </span>
                <Pager
                  disabled={currentPage >= totalPages || loading}
                  onClick={() => search(query, currentPage + 1)}
                >
                  Next →
                </Pager>
              </span>
            )}
          </div>

          <StatsBar
            listings={result.listings}
            total={result.total}
            sold={resultsAreSold}
          />

          {result.listings.length === 0 ? (
            <p className="py-12 text-center text-[var(--color-muted)]">
              No listings matched.
            </p>
          ) : view === "table" ? (
            <ResultsTable listings={result.listings} sold={resultsAreSold} />
          ) : (
            <ResultsGrid listings={result.listings} sold={resultsAreSold} />
          )}
        </>
      )}

      {!result && !loading && !error && (
        <p className="py-16 text-center text-[var(--color-muted)]">
          Search active listings, or flip to sold comps to see what gear
          actually clears for.
        </p>
      )}
    </main>
  );
}

function Toggle({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-md border px-3 py-1.5 text-sm ${
        active
          ? "border-[var(--color-accent)] text-[var(--color-accent)]"
          : "border-[var(--color-line)] text-[var(--color-muted)]"
      }`}
    >
      {children}
    </button>
  );
}

function Pager({
  disabled,
  onClick,
  children,
}: {
  disabled: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="rounded-md border border-[var(--color-line)] px-2 py-1 disabled:opacity-40"
    >
      {children}
    </button>
  );
}
