import type { Listing } from "@better-reverb-search/reverb-api";
import { describe, expect, it } from "vitest";
import { fullRange, inRecencyRange, monthsAgo, recencyBuckets } from "./recency-filter";

const NOW = Date.parse("2026-08-15T00:00:00Z");
const MONTH = 30.44 * 24 * 60 * 60 * 1000;

/** Only the date fields matter here; the rest of Listing is irrelevant. */
const at = (monthsBack: number, published = true): Listing =>
  ({
    published_at: published ? new Date(NOW - monthsBack * MONTH).toISOString() : null,
    created_at: new Date(NOW - monthsBack * MONTH).toISOString(),
  }) as Listing;

describe("recency filter", () => {
  it("buckets by 3 months, oldest listing sizing the chart", () => {
    // 0, 4, 5 and 10 months back → buckets 0-3, 3-6 (x2), 9-12.
    const counts = recencyBuckets([at(0), at(4), at(5), at(10)], NOW);
    expect(counts).toEqual([1, 2, 0, 1]);
  });

  it("falls back to created_at when unpublished", () => {
    expect(monthsAgo(at(6, false), NOW)).toBeCloseTo(6, 1);
  });

  // Half-open [newest, oldest). Probed just inside the edges rather than exactly
  // on them — ms rounding through toISOString makes an exact boundary a coin flip.
  it("keeps listings inside the range and drops those outside", () => {
    expect(inRecencyRange(at(3.1), [3, 6], NOW)).toBe(true);
    expect(inRecencyRange(at(5.9), [3, 6], NOW)).toBe(true);
    expect(inRecencyRange(at(6.1), [3, 6], NOW)).toBe(false);
    expect(inRecencyRange(at(1), [3, 6], NOW)).toBe(false);
  });

  it("keeps undated listings rather than dropping them silently", () => {
    const undated = { published_at: null, created_at: "" } as unknown as Listing;
    expect(inRecencyRange(undated, [0, 3], NOW)).toBe(true);
    expect(recencyBuckets([undated], NOW)).toEqual([0]);
  });

  it("full range covers every bucket", () => {
    const listings = [at(0), at(10)];
    const range = fullRange(recencyBuckets(listings, NOW).length);
    expect(range).toEqual([0, 12]);
    expect(listings.every((l) => inRecencyRange(l, range, NOW))).toBe(true);
  });
});
