"use client";

import type { SearchQuery } from "@better-reverb-search/reverb-api";
import { useEffect, useState } from "react";
import { ApiKeyField } from "@/components/api-key-field";
import { ResultsGrid } from "@/components/results-grid";
import { ResultsTable } from "@/components/results-table";
import { SearchForm } from "@/components/search-form";
import { StatsBar } from "@/components/stats-bar";
import { ThemeToggle } from "@/components/theme-toggle";
import { fromSearchParams, toSearchParams } from "@/lib/query-url";
import { useSearch } from "@/lib/use-search";

type View = "table" | "grid";

const DEFAULT_QUERY: SearchQuery = { perPage: 24 };

export default function Page() {
  const [query, setQuery] = useState<SearchQuery>(DEFAULT_QUERY);
  const [view, setView] = useState<View>("table");
  const { result, error, loading, run, clear } = useSearch();

  // The mode the current *results* were fetched in — not the pending toggle
  // state, so the table doesn't render Ask/Off columns against active listings.
  const [resultsAreSold, setResultsAreSold] = useState(false);

  // replaceState, not push: the search box isn't a navigation stack, and this
  // keeps the URL shareable/reloadable without burying the back button.
  const syncUrl = (q: SearchQuery, v: View) => {
    const qs = toSearchParams(q, v);
    window.history.replaceState(
      null,
      "",
      qs ? `?${qs}` : window.location.pathname,
    );
  };

  // Restore from the URL on mount. Runs after hydration so the server-rendered
  // empty state and the client's first paint agree.
  useEffect(() => {
    const { query: q, view: v } = fromSearchParams(window.location.search);
    if (v === "grid") setView("grid");
    // perPage/page alone are just defaults left over from a clear — nothing to search.
    const meaningful = Object.keys(q).some(
      (k) => k !== "perPage" && k !== "page",
    );
    if (!meaningful) return;
    const next = { ...DEFAULT_QUERY, ...q };
    setQuery(next);
    setResultsAreSold(next.showOnlySold === true);
    void run(next);
  }, [run]);

  const search = (next: SearchQuery = query, page = 1) => {
    const q = { ...next, page };
    setQuery(q);
    setResultsAreSold(q.showOnlySold === true);
    syncUrl(q, view);
    void run(q);
  };

  const setViewAndSync = (v: View) => {
    setView(v);
    syncUrl(query, v);
  };

  const clearAll = () => {
    setQuery(DEFAULT_QUERY);
    setResultsAreSold(false);
    clear();
    syncUrl(DEFAULT_QUERY, view);
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
            onClick={() => setViewAndSync(view === "table" ? "grid" : "table")}
          >
            {view === "table" ? "Table" : "Grid"}
          </Toggle>
          {/* Not a Toggle — it's an action, so no aria-pressed. */}
          <button
            type="button"
            onClick={clearAll}
            className="rounded-full border border-[var(--color-line)] px-4 py-1.5 text-sm text-[var(--color-muted)]"
          >
            Clear
          </button>
          <ApiKeyField />
          <ThemeToggle />
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
          className="rounded-[var(--radius-module)] border border-[var(--color-urgent)] bg-[var(--color-urgent-bg)] p-3 text-sm text-[var(--color-sale)]"
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
      // Reverb marks an active filter with a full-strength border, not a fill.
      className={`rounded-full border px-4 py-1.5 text-sm ${
        active
          ? "border-[var(--color-line-strong)] font-medium text-[var(--color-ink)]"
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
      className="rounded-full border border-[var(--color-line)] px-3 py-1 disabled:opacity-40"
    >
      {children}
    </button>
  );
}
