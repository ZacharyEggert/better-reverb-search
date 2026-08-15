"use client";

/**
 * Collapsible panel built on <details> — open/close, keyboard and screen-reader
 * semantics for free. Closed it is pinned to exactly 2rem; `summary` stays
 * visible at that height so a collapsed filter still says what it's doing.
 */
export function Drawer({
  label,
  summary,
  children,
  defaultOpen = true,
}: {
  label: string;
  summary?: React.ReactNode;
  children: React.ReactNode;
  defaultOpen?: boolean;
}) {
  return (
    <details
      open={defaultOpen}
      className="group h-8 overflow-hidden rounded-[var(--radius-module)] border border-[var(--color-line)] px-3 py-1 open:h-auto open:space-y-3 open:overflow-visible open:p-4"
    >
      {/* list-none + the webkit rule kill the default disclosure triangle in
          every engine; the caret below is ours so it can flip on open. */}
      <summary className="flex cursor-pointer list-none items-baseline justify-between gap-2 text-sm [&::-webkit-details-marker]:hidden">
        <span className="text-[var(--color-muted)]">
          {label}{" "}
          <span aria-hidden className="inline-block group-open:rotate-180">
            ▾
          </span>
        </span>
        {summary !== undefined && <span className="tnum text-[var(--color-ink)]">{summary}</span>}
      </summary>
      {children}
    </details>
  );
}
