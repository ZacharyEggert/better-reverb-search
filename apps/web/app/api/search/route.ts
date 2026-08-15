import {
  RevError,
  discountPercent,
  listingUrl,
  searchListings,
  type Listing,
} from "@better-reverb-search/reverb-api";
import { fromSearchParams } from "@/lib/query-url";
import { rateLimit } from "@/lib/rate-limit";

/**
 * `GET /api/search?query=...` — same params the UI puts in the URL bar.
 *
 * The consumer supplies their own Reverb key (`Authorization: Bearer <key>` or
 * `x-api-key`); this route never falls back to a server-side key, so it can't
 * be used to spend someone else's quota. Response carries only the fields the
 * UI actually renders.
 */
export async function GET(request: Request) {
  const apiKey =
    request.headers
      .get("authorization")
      ?.replace(/^Bearer\s+/i, "")
      .trim() || request.headers.get("x-api-key")?.trim();
  if (!apiKey) {
    return Response.json(
      { error: "missing API key — send Authorization: Bearer <key>" },
      { status: 401 },
    );
  }

  const retryAfter = rateLimit(`search:${apiKey}`, LIMIT, WINDOW_MS);
  if (retryAfter) {
    return Response.json(
      { error: `rate limit exceeded — ${LIMIT} requests per 5s` },
      { status: 429, headers: { "retry-after": String(retryAfter) } },
    );
  }

  const { query } = fromSearchParams(new URL(request.url).search);

  try {
    const result = await searchListings(query, {
      apiKey,
      signal: request.signal,
    });
    return Response.json({
      total: result.total,
      currentPage: result.currentPage,
      perPage: result.perPage,
      totalPages: result.totalPages,
      humanizedParams: result.humanizedParams,
      listings: result.listings.map(slim),
    });
  } catch (e) {
    if (e instanceof RevError) {
      return Response.json(
        { error: e.message, type: e.type },
        { status: STATUS[e.type] ?? e.code ?? 500 },
      );
    }
    return Response.json({ error: "unexpected error" }, { status: 500 });
  }
}

const LIMIT = 5;
const WINDOW_MS = 5_000;

const STATUS: Partial<Record<RevError["type"], number>> = {
  auth: 401,
  validation: 400,
  schema: 400,
};

/** Exactly what results-table / results-grid / stats-bar read off a listing. */
function slim(l: Listing) {
  return {
    id: l.id,
    title: l.title,
    year: l.year,
    condition: l.condition && {
      slug: l.condition.slug,
      display_name: l.condition.display_name,
    },
    price: l.price && {
      display: l.price.display,
      amount_cents: l.price.amount_cents,
      currency: l.price.currency,
    },
    originalPrice: l.original_price?.display ?? null,
    discountPercent: discountPercent(l) ?? null,
    shopName: l.shop_name,
    publishedAt: l.published_at,
    photo: l.photos?.[0]?._links?.thumbnail?.href ?? l._links?.photo?.href ?? null,
    url: listingUrl(l) ?? null,
    sold: l.state?.slug === "sold",
  };
}
