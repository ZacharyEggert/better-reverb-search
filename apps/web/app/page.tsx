"use client";

import type { SearchQuery } from "@better-reverb-search/reverb-api";
import { useEffect, useRef, useState } from "react";
import { ApiKeyField } from "@/components/api-key-field";
import {
  BUCKET_MONTHS,
  fullRange,
  inRecencyRange,
  RecencyFilter,
  recencyBuckets,
  type RecencyRange,
} from "@/components/recency-filter";
import { ResultsGrid } from "@/components/results-grid";
import { ResultsTable } from "@/components/results-table";
import { SearchForm } from "@/components/search-form";
import { StatsBar } from "@/components/stats-bar";
import { ThemeToggle } from "@/components/theme-toggle";
import { fromSearchParams, toSearchParams } from "@/lib/query-url";
import { useSearch } from "@/lib/use-search";

type View = "table" | "grid";

/** How more results are reached: auto on scroll, a button, discrete pages, or all at once. */
type Paging = "scroll" | "more" | "pages" | "all";

const PAGING_KEY = "brs.paging";
const PAGING_LABELS: Record<Paging, string> = {
  scroll: "Infinite scroll",
  more: "Load more",
  pages: "Pages",
  all: "Load all pages",
};

/** Gap between the automatic page fetches in "all" mode — Reverb rate-limits. */
const ALL_PAGES_DELAY_MS = 500;

const DEFAULT_QUERY: SearchQuery = { perPage: 24 };

export default function Page() {
  const [query, setQuery] = useState<SearchQuery>(DEFAULT_QUERY);
  const [view, setView] = useState<View>("table");
  // Starts at the default so SSR and first client render agree; the stored
  // preference lands in the mount effect below.
  const [paging, setPaging] = useState<Paging>("scroll");
  const { result, error, loading, run, clear } = useSearch();

  // The mode the current *results* were fetched in — not the pending toggle
  // state, so the table doesn't render Ask/Off columns against active listings.
  const [resultsAreSold, setResultsAreSold] = useState(false);

  // replaceState, not push: the search box isn't a navigation stack, and this
  // keeps the URL shareable/reloadable without burying the back button.
  const syncUrl = (q: SearchQuery, v: View) => {
    const qs = toSearchParams(q, v);
    window.history.replaceState(null, "", qs ? `?${qs}` : window.location.pathname);
  };

  // Restore from the URL on mount. Runs after hydration so the server-rendered
  // empty state and the client's first paint agree.
  useEffect(() => {
    try {
      const stored = localStorage.getItem(PAGING_KEY);
      if (stored && stored in PAGING_LABELS) setPaging(stored as Paging);
    } catch {
      // localStorage can throw in sandboxed contexts; the default is fine.
    }

    const { query: q, view: v } = fromSearchParams(window.location.search);
    if (v === "grid") setView("grid");
    // perPage/page alone are just defaults left over from a clear — nothing to search.
    const meaningful = Object.keys(q).some((k) => k !== "perPage" && k !== "page");
    if (!meaningful) return;
    const next = { ...DEFAULT_QUERY, ...q };
    setQuery(next);
    setResultsAreSold(next.showOnlySold === true);
    void run(next);
  }, [run]);

  const search = (next: SearchQuery = query, page = 1) => {
    const q = { ...next, page };
    setQuery(q);
    setRecency(undefined); // a new result set has its own date span
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
    setRecency(undefined);
    clear();
    syncUrl(DEFAULT_QUERY, view);
  };

  // Recency is filtered client-side over the listings already loaded — Reverb
  // has no verified date-range param, and the histogram can only describe the
  // sample anyway. `undefined` means "whole span", so it tracks appended pages.
  const [recency, setRecency] = useState<RecencyRange>();
  const buckets = result ? recencyBuckets(result.listings) : [];
  const span = fullRange(buckets.length);
  const recencyRange: RecencyRange = recency
    ? [Math.min(recency[0], span[1] - BUCKET_MONTHS), Math.min(recency[1], span[1])]
    : span;
  const visible = result ? result.listings.filter((l) => inRecencyRange(l, recencyRange)) : [];
  const filtered = result ? result.listings.length - visible.length : 0;

  const sold = query.showOnlySold === true;
  const totalPages = result ? Math.min(result.totalPages, 50) : 0;
  const currentPage = result?.currentPage ?? 1;
  const hasMore = currentPage < totalPages;

  // Appends the next page to the results already on screen.
  const loadMore = () => void run({ ...query, page: currentPage + 1 }, true);

  const choosePaging = (p: Paging) => {
    setPaging(p);
    try {
      localStorage.setItem(PAGING_KEY, p);
    } catch {
      // Non-persistent is still better than not switching at all.
    }
    // Switching to pages with several pages appended would leave a page number
    // that doesn't describe what's shown — refetch the current page alone.
    if (p === "pages" && result && result.listings.length > (query.perPage ?? 24))
      search(query, currentPage);
  };

  // Load-all: walk the remaining pages one at a time. Each fetch flips `loading`,
  // which re-runs this effect and schedules the next one — no loop to abort, and
  // the timer is cleared if the mode changes or a new search resets the results.
  useEffect(() => {
    if (paging !== "all" || loading || !hasMore || error) return;
    const t = setTimeout(
      () => void run({ ...query, page: currentPage + 1 }, true),
      ALL_PAGES_DELAY_MS,
    );
    return () => clearTimeout(t);
  }, [run, query, currentPage, hasMore, loading, paging, error]);

  // Infinite scroll: fetch the next page when the sentinel nears the viewport.
  // The observer is torn down while loading, so a page can't be fetched twice.
  const sentinel = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = sentinel.current;
    if (!el || loading || !hasMore || paging !== "scroll") return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) void run({ ...query, page: currentPage + 1 }, true);
      },
      { rootMargin: "400px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [run, query, currentPage, hasMore, loading, paging]);

  return (
    <main className="mx-auto max-w-7xl space-y-6 p-6">
      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">Better Reverb Search</h1>
        <div className="flex items-center gap-2">
          <Toggle active={sold} onClick={() => search({ ...query, showOnlySold: !sold })}>
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
          <select
            value={paging}
            onChange={(e) => choosePaging(e.target.value as Paging)}
            aria-label="How to load more results"
            className="rounded-full border border-[var(--color-line)] px-3 py-1.5 text-sm text-[var(--color-muted)]"
          >
            {Object.entries(PAGING_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
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
            {totalPages > 1 &&
              (paging === "pages" ? (
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
              ) : (
                <span className="tnum">
                  showing {visible.length.toLocaleString()}
                  {filtered > 0 && ` (${filtered.toLocaleString()} outside date range)`}
                </span>
              ))}
          </div>

          {result.listings.length > 0 && (
            <RecencyFilter listings={result.listings} range={recencyRange} onChange={setRecency} />
          )}

          <StatsBar listings={visible} total={result.total} sold={resultsAreSold} />

          {visible.length === 0 ? (
            <p className="py-12 text-center text-[var(--color-muted)]">No listings matched.</p>
          ) : view === "table" ? (
            <ResultsTable listings={visible} sold={resultsAreSold} />
          ) : (
            <ResultsGrid listings={visible} sold={resultsAreSold} />
          )}

          {hasMore && paging !== "pages" && (
            <div ref={sentinel} className="py-8 text-center text-sm text-[var(--color-muted)]">
              {paging === "more" ? (
                <button
                  type="button"
                  disabled={loading}
                  onClick={loadMore}
                  className="rounded-full border border-[var(--color-line)] px-4 py-1.5 disabled:opacity-40"
                >
                  {loading ? "Loading…" : "Load more"}
                </button>
              ) : paging === "all" ? (
                <span className="tnum">
                  Loading page {currentPage + 1} of {totalPages}…
                </span>
              ) : loading ? (
                "Loading…"
              ) : null}
            </div>
          )}
        </>
      )}

      {!result && !loading && !error && (
        <p className="py-16 text-center text-[var(--color-muted)]">
          Search active listings, or flip to sold comps to see what gear actually clears for.
        </p>
      )}
    </main>
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
