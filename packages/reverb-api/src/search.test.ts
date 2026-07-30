import { describe, expect, it } from "vitest";
import { buildUrl, resolveMethod } from "./executor.js";
import {
  discountPercent,
  listingUrl,
  priceStats,
  toParams,
  type Listing,
} from "./search.js";

const money = (cents: number) => ({
  amount: (cents / 100).toFixed(2),
  amount_cents: cents,
  currency: "USD",
  symbol: "$",
  display: `$${cents / 100}`,
});

const listing = (cents: number, askCents?: number) =>
  ({ price: money(cents), original_price: askCents ? money(askCents) : null }) as Listing;

describe("toParams", () => {
  it("maps camelCase to Reverb's snake_case wire names", () => {
    expect(toParams({ priceMin: 500, priceMax: 900, showOnlySold: true })).toEqual({
      price_min: 500,
      price_max: 900,
      show_only_sold: true,
    });
  });

  it("omits false and undefined rather than sending them", () => {
    expect(toParams({ showOnlySold: false, make: undefined })).toEqual({});
  });

  it("rejects a bad condition instead of letting Reverb silently ignore it", () => {
    // Live API returns the *unfiltered* set for condition=bogusvalue.
    expect(() => toParams({ condition: "bogus" as never })).toThrow(/unknown condition/);
  });

  it("rejects an inverted price range", () => {
    expect(() => toParams({ priceMin: 900, priceMax: 500 })).toThrow(/priceMin/);
  });

  it("passes `extra` through verbatim", () => {
    expect(toParams({ extra: { not_modelled: "x" } })).toEqual({ not_modelled: "x" });
  });
});

describe("priceStats", () => {
  it("computes min/median/max in currency units", () => {
    expect(priceStats([listing(10_000), listing(30_000), listing(20_000)])).toEqual({
      count: 3,
      min: 100,
      median: 200,
      max: 300,
      currency: "USD",
    });
  });

  it("averages the two middle values for an even count", () => {
    expect(priceStats([listing(10_000), listing(20_000)])?.median).toBe(150);
  });

  it("returns undefined for an empty set", () => {
    expect(priceStats([])).toBeUndefined();
  });
});

describe("discountPercent", () => {
  it("reports how far below the ask a sold listing cleared", () => {
    expect(discountPercent(listing(80_000, 100_000))).toBe(20);
  });

  it("is undefined without an original price", () => {
    expect(discountPercent(listing(80_000))).toBeUndefined();
  });
});

describe("listingUrl", () => {
  const withState = (slug: string, href?: string) =>
    ({
      state: { slug, description: slug },
      _links: href ? { web: { href } } : {},
    }) as Listing;

  it("appends show_sold=true for sold listings", () => {
    expect(listingUrl(withState("sold", "https://reverb.com/item/123-strat"))).toBe(
      "https://reverb.com/item/123-strat?show_sold=true",
    );
  });

  it("leaves live listings untouched", () => {
    expect(listingUrl(withState("live", "https://reverb.com/item/123-strat"))).toBe(
      "https://reverb.com/item/123-strat",
    );
  });

  it("merges with an existing query string rather than clobbering it", () => {
    expect(listingUrl(withState("sold", "https://reverb.com/item/1?a=b"))).toBe(
      "https://reverb.com/item/1?a=b&show_sold=true",
    );
  });

  it("does not duplicate the param if already present", () => {
    expect(
      listingUrl(withState("sold", "https://reverb.com/item/1?show_sold=true")),
    ).toBe("https://reverb.com/item/1?show_sold=true");
  });

  it("is undefined when the listing has no web link", () => {
    expect(listingUrl(withState("sold"))).toBeUndefined();
  });
});

describe("executor url building", () => {
  it("substitutes path placeholders and leaves the rest as query params", () => {
    const { path } = resolveMethod("listings", "get");
    expect(buildUrl(path, { id: "123", foo: "bar" })).toEqual({
      url: "https://api.reverb.com/api/listings/123",
      extraQuery: [["foo", "bar"]],
    });
  });

  it("rejects path traversal in a path param", () => {
    const { path } = resolveMethod("listings", "get");
    expect(() => buildUrl(path, { id: "../../etc/passwd" })).toThrow();
  });

  it("throws rather than requesting a URL with an unfilled placeholder", () => {
    const { path } = resolveMethod("listings", "get");
    expect(() => buildUrl(path, {})).toThrow(/missing required path parameter/);
  });

  it("rejects an unknown method", () => {
    expect(() => resolveMethod("listings", "frobnicate")).toThrow(/unknown method/);
  });
});
