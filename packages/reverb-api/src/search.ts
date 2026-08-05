import { execute, type ParamValue } from "./executor.js";
import { RevError } from "./error.js";
import { checkSafeString } from "./validate.js";

/**
 * Typed search layer over `executor.execute("listings", "list", ...)`.
 *
 * Every param below was verified against the live API. This matters: Reverb
 * silently ignores unknown params rather than erroring (`condition=bogusvalue`
 * returns the unfiltered set), and worse, misroutes some of them —
 * `item_state=sold` is parsed as a *location* and returns 0 results. A typo in
 * an untyped param bag therefore looks like a legitimate empty result.
 */

export const CONDITIONS = [
  "mint",
  "excellent",
  "very-good",
  "good",
  "fair",
  "poor",
  "non-functioning",
] as const;
/**
 * Coarse buckets, a different axis from the seven grades above rather than more
 * members of it — `used` (25.8k) and `new` (51.6k) split the whole result set
 * between them, while `excellent` (9.8k) is a slice of `used`. Valid as a
 * search filter only; a listing's own `condition.slug` is always a grade.
 */
export const CONDITION_BUCKETS = ["used", "new", "b-stock"] as const;

export type Condition =
  | (typeof CONDITIONS)[number]
  | (typeof CONDITION_BUCKETS)[number];

export const PRODUCT_TYPES = [
  "electric-guitars",
  "effects-and-pedals",
  "acoustic-guitars",
  "bass-guitars",
  "pro-audio",
  "amps",
] as const;
export type ProductType = (typeof PRODUCT_TYPES)[number];

export const SORTS = [
  "price|asc",
  "price|desc",
  "published_at|desc",
  "published_at|asc",
] as const;
export type Sort = (typeof SORTS)[number];

export interface SearchQuery {
  /** Free-text search, e.g. "1963 Stratocaster". */
  query?: string;
  make?: string;
  model?: string;
  /** Category slug, e.g. "electric-guitars". */
  category?: string;
  /** Top-level product type slug. */
  productType?: ProductType;
  priceMin?: number;
  priceMax?: number;
  condition?: Condition;
  yearMin?: number;
  yearMax?: number;
  /** Defaults to "published_at|desc" (newest first). */
  sort?: Sort;
  /** ISO country code, e.g. "US". */
  shipsTo?: string;
  /** Return completed sales instead of live listings. */
  showOnlySold?: boolean;
  page?: number;
  perPage?: number;
  /**
   * Escape hatch for params Reverb supports that aren't modelled above.
   * Passed through verbatim — you own the correctness of these.
   */
  extra?: Record<string, ParamValue>;
}

/** snake_case wire names for the modelled fields. */
const WIRE_NAMES: Record<string, string> = {
  make: "make",
  model: "model",
  category: "category",
  productType: "product_type",
  priceMin: "price_min",
  priceMax: "price_max",
  condition: "condition",
  yearMin: "year_min",
  yearMax: "year_max",
  sort: "sort",
  shipsTo: "ships_to",
  showOnlySold: "show_only_sold",
  page: "page",
  perPage: "per_page",
};

export interface Money {
  amount: string;
  amount_cents: number;
  currency: string;
  symbol: string;
  display: string;
  tax_included?: boolean;
}

export interface Listing {
  id: number;
  title: string;
  make: string | null;
  model: string | null;
  year: string | null;
  finish: string | null;
  description?: string;
  condition: { uuid: string; display_name: string; slug: string } | null;
  price: Money;
  /** Present on sold listings — the pre-discount ask. */
  original_price?: Money | null;
  buyer_price?: Money | null;
  inventory: number;
  has_inventory: boolean;
  offers_enabled: boolean;
  auction: boolean;
  state: { slug: string; description: string };
  shop_id: number;
  shop_name: string;
  created_at: string;
  published_at: string | null;
  photos?: { _links?: { full?: { href?: string }; thumbnail?: { href?: string } } }[];
  _links?: Record<string, { href?: string }>;
}

export interface SearchResult {
  total: number;
  currentPage: number;
  perPage: number;
  totalPages: number;
  /** Reverb's own echo of how it parsed the filters — useful to surface in UI. */
  humanizedParams: string;
  listings: Listing[];
}

export interface SearchOptions {
  apiKey?: string;
  signal?: AbortSignal;
  /** Fetch every page up to `pageLimit` and concatenate the listings. */
  pageAll?: boolean;
  pageLimit?: number;
}

export async function searchListings(
  query: SearchQuery,
  options: SearchOptions = {},
): Promise<SearchResult> {
  const params = toParams(query);

  const result = await execute({
    resource: "listings",
    method: "list",
    query: query.query,
    params,
    perPage: query.perPage,
    pageAll: options.pageAll,
    pageLimit: options.pageLimit,
    apiKey: options.apiKey,
    signal: options.signal,
  });

  const pages = result.pages as RawPage[];
  const first = pages[0];
  if (!first) throw RevError.other(new Error("search returned no pages"));

  return {
    total: first.total ?? 0,
    currentPage: first.current_page ?? 1,
    perPage: first.per_page ?? 0,
    totalPages: first.total_pages ?? 0,
    humanizedParams: first.humanized_params ?? "",
    listings: pages.flatMap((p) => p.listings ?? []),
  };
}

interface RawPage {
  total?: number;
  current_page?: number;
  per_page?: number;
  total_pages?: number;
  humanized_params?: string;
  listings?: Listing[];
}

/** Serialize a SearchQuery into Reverb's snake_case wire params. */
export function toParams(query: SearchQuery): Record<string, ParamValue> {
  const params: Record<string, ParamValue> = {};

  for (const [key, wire] of Object.entries(WIRE_NAMES)) {
    const value = query[key as keyof SearchQuery];
    if (value === undefined || value === "" || value === false) continue;
    params[wire] = value as ParamValue;
  }

  if (
    query.condition &&
    !CONDITIONS.includes(query.condition as never) &&
    !CONDITION_BUCKETS.includes(query.condition as never)
  ) {
    throw RevError.validation(
      `unknown condition '${query.condition}' — Reverb silently ignores it rather than erroring`,
    );
  }
  if (query.productType && !PRODUCT_TYPES.includes(query.productType)) {
    throw RevError.validation(
      `unknown productType '${query.productType}' — Reverb silently ignores it rather than erroring`,
    );
  }
  if (query.sort && !SORTS.includes(query.sort)) {
    throw RevError.validation(`unknown sort '${query.sort}'`);
  }
  if (
    query.priceMin !== undefined &&
    query.priceMax !== undefined &&
    query.priceMin > query.priceMax
  ) {
    throw RevError.validation("priceMin cannot exceed priceMax");
  }

  for (const s of [query.query, query.make, query.model, query.category]) {
    if (s !== undefined) checkSafeString(s);
  }

  params.sort ??= "published_at|desc";

  return { ...params, ...query.extra };
}

/** Price distribution over a result set. Only ever describes the listings loaded. */
export interface PriceStats {
  count: number;
  min: number;
  median: number;
  max: number;
  currency: string;
}

export function priceStats(listings: Listing[]): PriceStats | undefined {
  const cents = listings
    .map((l) => l.price?.amount_cents)
    .filter((c): c is number => typeof c === "number" && c > 0)
    .sort((a, b) => a - b);
  if (cents.length === 0) return undefined;

  const mid = Math.floor(cents.length / 2);
  const median =
    cents.length % 2 === 0 ? (cents[mid - 1]! + cents[mid]!) / 2 : cents[mid]!;

  return {
    count: cents.length,
    min: cents[0]! / 100,
    median: median / 100,
    max: cents[cents.length - 1]! / 100,
    currency: listings.find((l) => l.price?.currency)?.price.currency ?? "USD",
  };
}

/**
 * Public reverb.com URL for a listing.
 *
 * Sold listings 404 on their bare URL — reverb.com only renders a completed
 * sale when `?show_sold=true` is present — so it is appended for anything whose
 * state is `sold`. Keyed off the listing's own state rather than the caller's
 * view mode, so a sold listing in a mixed result set still links correctly.
 */
export function listingUrl(listing: Listing): string | undefined {
  const href = listing._links?.web?.href;
  if (!href) return undefined;
  if (listing.state?.slug !== "sold") return href;

  try {
    const url = new URL(href);
    url.searchParams.set("show_sold", "true");
    return url.toString();
  } catch {
    // Relative or malformed href — fall back to naive appending.
    return href.includes("show_sold=")
      ? href
      : `${href}${href.includes("?") ? "&" : "?"}show_sold=true`;
  }
}

/** Discount depth on a sold listing: how far below the ask it actually cleared. */
export function discountPercent(listing: Listing): number | undefined {
  const ask = listing.original_price?.amount_cents;
  const sold = listing.price?.amount_cents;
  if (!ask || !sold || ask <= 0 || sold > ask) return undefined;
  return Math.round(((ask - sold) / ask) * 100);
}
