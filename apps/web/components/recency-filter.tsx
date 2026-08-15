"use client";

import type { Listing } from "@better-reverb-search/reverb-api";
import { useRef } from "react";

/** Bucket width, in months. The slider steps in the same unit. */
export const BUCKET_MONTHS = 3;

// Average month. Buckets are a coarse visual — calendar-exact edges buy nothing.
const MS_PER_MONTH = 30.44 * 24 * 60 * 60 * 1000;

/** [newest, oldest] bound in months ago; both multiples of BUCKET_MONTHS. */
export type RecencyRange = [number, number];

/**
 * Months since a listing went live. `published_at` is the recency a shopper
 * cares about; `created_at` is the fallback for drafts Reverb never published.
 */
export function monthsAgo(listing: Listing, now = Date.now()): number | undefined {
  const raw = listing.published_at ?? listing.created_at;
  const t = raw ? Date.parse(raw) : Number.NaN;
  if (Number.isNaN(t)) return undefined;
  return Math.max(0, (now - t) / MS_PER_MONTH);
}

/**
 * Counts per 3-month bucket, oldest listing setting the last index. The final
 * bucket is open-ended ("18+ mo"), so nothing falls off the end of the chart.
 */
export function recencyBuckets(listings: Listing[], now = Date.now()): number[] {
  const indices = listings
    .map((l) => monthsAgo(l, now))
    .filter((m): m is number => m !== undefined)
    .map((m) => Math.floor(m / BUCKET_MONTHS));
  const counts: number[] = Array.from({ length: Math.max(...indices, 0) + 1 }, () => 0);
  for (const i of indices) counts[i] = (counts[i] ?? 0) + 1;
  return counts;
}

/**
 * Undated listings pass: dropping a listing because Reverb omitted a timestamp
 * would be a silent data loss the user can't see or undo.
 */
export function inRecencyRange(
  listing: Listing,
  [newest, oldest]: RecencyRange,
  now = Date.now(),
): boolean {
  const m = monthsAgo(listing, now);
  if (m === undefined) return true;
  return m >= newest && m < oldest;
}

/** What a pointer/key interaction is moving: one edge, or the whole window. */
type Mode = "newest" | "oldest" | "window";

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), Math.max(lo, hi));

/** Full span covering every bucket — the "no filter" range. */
export function fullRange(bucketCount: number): RecencyRange {
  return [0, Math.max(bucketCount, 1) * BUCKET_MONTHS];
}

export function RecencyFilter({
  listings,
  range,
  onChange,
}: {
  listings: Listing[];
  range: RecencyRange;
  onChange: (range: RecencyRange) => void;
}) {
  const counts = recencyBuckets(listings);
  const max = Math.max(...counts, 1);
  const span = counts.length * BUCKET_MONTHS;
  const [newest, oldest] = range;
  const width = oldest - newest;

  // A single track with two thumbs and a draggable band between them. Native
  // <input type="range"> can't express a window that moves as a unit, so this
  // is hand-rolled on pointer capture — thumbs keep role="slider" and arrow
  // keys so it stays operable without a mouse.
  const trackRef = useRef<HTMLDivElement>(null);
  const drag = useRef<{ mode: Mode; from: number; start: RecencyRange }>(null);

  const monthsAt = (clientX: number) => {
    const rect = trackRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return 0;
    const raw = ((clientX - rect.left) / rect.width) * span;
    return clamp(Math.round(raw / BUCKET_MONTHS) * BUCKET_MONTHS, 0, span);
  };

  const beginDrag = (mode: Mode) => (e: React.PointerEvent) => {
    e.preventDefault();
    e.stopPropagation(); // a thumb press must not also grab the band
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { mode, from: monthsAt(e.clientX), start: range };
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const at = monthsAt(e.clientX);
    const [from, to] = d.start;
    if (d.mode === "newest") onChange([Math.min(at, to - BUCKET_MONTHS), to]);
    else if (d.mode === "oldest") onChange([from, Math.max(at, from + BUCKET_MONTHS)]);
    else {
      // The band keeps its width; the span ends stop it rather than squashing it.
      const w = to - from;
      const start = clamp(from + (at - d.from), 0, span - w);
      onChange([start, start + w]);
    }
  };

  const endDrag = (e: React.PointerEvent) => {
    drag.current = null;
    e.currentTarget.releasePointerCapture(e.pointerId);
  };

  const nudge = (mode: Mode) => (e: React.KeyboardEvent) => {
    const step =
      e.key === "ArrowLeft" ? -BUCKET_MONTHS : e.key === "ArrowRight" ? BUCKET_MONTHS : 0;
    if (step === 0) return;
    e.preventDefault();
    if (mode === "newest") onChange([clamp(newest + step, 0, oldest - BUCKET_MONTHS), oldest]);
    else if (mode === "oldest")
      onChange([newest, clamp(oldest + step, newest + BUCKET_MONTHS, span)]);
    else {
      const start = clamp(newest + step, 0, span - width);
      onChange([start, start + width]);
    }
  };

  const pct = (months: number) => `${(months / span) * 100}%`;
  const dragProps = (mode: Mode) => ({
    onPointerDown: beginDrag(mode),
    onPointerMove,
    onPointerUp: endDrag,
    onPointerCancel: endDrag,
  });

  return (
    // <details> is the drawer: open/close, keyboard and screen-reader semantics
    // for free. The summary keeps the selected range visible while collapsed.
    <details
      open
      // Closed is pinned to exactly 2rem: h-8 with tight padding, and the
      // padding/height only open up when the drawer does.
      className="group h-8 overflow-hidden rounded-[var(--radius-module)] border border-[var(--color-line)] px-3 py-1 open:h-auto open:space-y-3 open:overflow-visible open:p-4"
    >
      {/* list-none + the webkit rule kill the default disclosure triangle in
          every engine; the caret below is ours so it can flip on open. */}
      <summary className="flex cursor-pointer list-none items-baseline justify-between gap-2 text-sm [&::-webkit-details-marker]:hidden">
        <span className="text-[var(--color-muted)]">
          Listed Date Range{" "}
          <span aria-hidden className="inline-block group-open:rotate-180">
            ▾
          </span>
        </span>
        <span className="tnum text-[var(--color-ink)]">
          {newest === 0 ? "now" : `${newest} mo ago`} –{" "}
          {oldest >= span ? "oldest" : `${oldest} mo ago`}
        </span>
      </summary>

      <div className="flex h-24 items-end gap-1" aria-hidden>
        {counts.map((count, i) => {
          const start = i * BUCKET_MONTHS;
          const included = start >= newest && start < oldest;
          return (
            <div
              key={start}
              title={`${start}–${start + BUCKET_MONTHS} mo ago: ${count}`}
              className="flex-1 rounded-t-sm"
              style={{
                // A hair of height on empty buckets keeps the axis readable.
                height: `${Math.max((count / max) * 100, 2)}%`,
                background: included ? "var(--color-accent)" : "var(--color-line-selectable)",
                opacity: included ? 1 : 0.4,
              }}
            />
          );
        })}
      </div>

      {/* Buckets are equal width, so a start-of-range tick under each end works
          as the axis; only the ends are labelled to stay legible when narrow. */}
      <div className="flex justify-between text-xs text-[var(--color-muted)]">
        <span>now</span>
        <span className="tnum">{span}+ mo ago</span>
      </div>

      <div
        ref={trackRef}
        className="relative h-3 touch-none select-none rounded-full bg-[var(--color-surface)]"
      >
        <div
          {...dragProps("window")}
          role="slider"
          tabIndex={0}
          aria-label="Date window"
          aria-valuemin={0}
          aria-valuemax={span - width}
          aria-valuenow={newest}
          aria-valuetext={`${newest} to ${oldest} months ago`}
          onKeyDown={nudge("window")}
          className="absolute inset-y-0 cursor-grab rounded-full bg-[var(--color-accent)] opacity-30 active:cursor-grabbing"
          style={{ left: pct(newest), width: pct(width) }}
        />
        <Thumb
          label="Newest bound"
          value={newest}
          max={oldest - BUCKET_MONTHS}
          left={pct(newest)}
          onKeyDown={nudge("newest")}
          {...dragProps("newest")}
        />
        <Thumb
          label="Oldest bound"
          value={oldest}
          min={newest + BUCKET_MONTHS}
          max={span}
          left={pct(oldest)}
          onKeyDown={nudge("oldest")}
          {...dragProps("oldest")}
        />
      </div>
    </details>
  );
}

function Thumb({
  label,
  value,
  min = 0,
  max,
  left,
  ...handlers
}: {
  label: string;
  value: number;
  min?: number;
  max: number;
  left: string;
  onKeyDown: (e: React.KeyboardEvent) => void;
} & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      {...handlers}
      role="slider"
      tabIndex={0}
      aria-label={label}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuenow={value}
      aria-valuetext={`${value} months ago`}
      // Square box + rounded-full = circle; the translates centre it on its
      // value both ways rather than hanging off the top of the track.
      className="absolute top-1/2 h-5 w-5 -translate-x-1/2 -translate-y-1/2 cursor-ew-resize rounded-full border-2 border-[var(--color-accent)] bg-[var(--color-paper)] focus:outline-2 focus:outline-[var(--color-focus)]"
      style={{ left }}
    />
  );
}
