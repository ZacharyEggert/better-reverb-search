# better-reverb-search

pnpm monorepo. A TypeScript port of the [`reverb-cli`](../reverb-cli) Rust crates,
plus a Next.js app that searches Reverb listings and sold comps.

```
packages/reverb-api   port of the reverb-api + reverb-api-cli crates (tsup → ESM + .d.ts)
apps/web              Next.js 15 search UI, Tailwind 4, Cadence-themed
apps/ios              SwiftUI iPhone/iPad app, same search — outside the pnpm workspace
```

## Quick start

```sh
pnpm install
pnpm dev          # library in watch mode + next dev on :3000
```

No API key is required — every endpoint the app uses (`GET /api/listings`)
answers unauthenticated. Set one to raise your rate limit:

```sh
export REVERB_API_KEY=...   # or storeApiKey() → localStorage in the browser
```

| Script           | What it does                                    |
| ---------------- | ----------------------------------------------- |
| `pnpm dev`       | library watch + `next dev`                       |
| `pnpm build`     | tsup, then `next build` (turbo orders them)      |
| `pnpm test`      | vitest, in `packages/reverb-api`                 |
| `pnpm typecheck` | `tsc --noEmit` across both packages              |
| `pnpm lint`      | oxlint                                           |

## What the app does

- Search active listings, or flip to **sold comps** (`show_only_sold`) to see
  what gear actually cleared for rather than what sellers are asking.
- Filter by make, model, condition, price range, year range, and sort.
- **Price stats** over the loaded result set — min / median / max. Labelled as
  covering only the listings fetched, never the full match count, because the
  API caps at 50 pages.
- **Dense sortable table** or card grid. Table sorting is client-side over the
  loaded page; Reverb's own `sort` param reorders the whole result set
  server-side. Both are available and they answer different questions.
- In sold mode the table gains **Ask** and **discount %** columns, computed
  from `original_price` vs `price`.
- Light/dark theme toggle, defaulting to your OS setting.
- **Search state lives in the URL** — query, filters, page, sold mode, and
  table/grid view. Reloading re-runs the search; the link is shareable.
  `replaceState`, so the back button isn't buried under every filter tweak.
- **Clear** resets the filters and results but keeps your table/grid choice —
  that's a display preference, not part of the search.

## JSON endpoint

`GET /api/search` exposes the same search to outside consumers. It takes the
query params the UI puts in its URL bar (`query`, `make`, `model`, `condition`,
`priceMin`/`priceMax`, `yearMin`/`yearMax`, `sort`, `showOnlySold=1`, `page`,
`perPage`, …) — so any shareable app URL works as an API URL.

The caller supplies their own Reverb key, via `Authorization: Bearer <key>` or
`x-api-key`. There is no server-side fallback key: no key → `401`.

```sh
curl -H "Authorization: Bearer $REVERB_API_KEY" \
  "https://reverb-search.diablo.guitars/api/search?query=stratocaster&perPage=2"
```

```jsonc
{
  "total": 77808, "currentPage": 1, "perPage": 2, "totalPages": 50,
  "humanizedParams": "\"stratocaster\" Gear",
  "listings": [{
    "id": 100154665,
    "title": "Genuine 1990 Fender MIM Black Standard Strat",
    "year": "1990",
    "condition": { "slug": "very-good", "display_name": "Very Good" },
    "price": { "display": "$199.99", "amount_cents": 19999, "currency": "USD" },
    "originalPrice": null,      // the ask, on sold listings
    "discountPercent": null,    // how far below it cleared
    "shopName": "More Strats, please",
    "publishedAt": "2026-08-05T17:29:29-05:00",
    "photo": "https://rvb-img.reverb.com/...",
    "url": "https://reverb.com/item/100154665-...",   // ?show_sold=true when sold
    "sold": false
  }]
}
```

Listings are trimmed to the fields the UI renders — not Reverb's full payload.
Rate limited to **5 requests per 5 seconds per key**; over that returns `429`
with `retry-after`. The window is in-process, so it's per server instance.

Errors come back as `{ "error": "...", "type": "api|auth|validation|schema" }`
with `401` for auth, `400` for validation/schema, and Reverb's own status
otherwise.

## iOS app

`open apps/ios/ReverbSearch.xcodeproj` and run. No dependencies, no package
manager, no generated project — the target uses a file-system-synchronized
group, so adding a `.swift` file under `apps/ios/ReverbSearch/` is all it takes.

It re-implements the library's search layer in Swift rather than sharing it —
`Models.swift` (query serialization, `PriceStats`, sold-URL handling, the
`validate.rs` port) and `ReverbAPI.swift` (429 backoff, `retry-after`, 5
attempts, 60s cap). The API gotchas below apply identically.

Self-check for that logic, no test target needed:

```sh
cd apps/ios
swiftc -o /tmp/reverb-tests Tests/main.swift ReverbSearch/Models.swift ReverbSearch/ReverbAPI.swift
/tmp/reverb-tests   # prints "ok"
```

Deliberately not ported, because the platform already answers them: the theme
toggle (iOS follows the system), URL search state (no address bar), and
client-side table sorting (Reverb's `sort` param covers it server-side). The
pager became **Load more**, and the API key lives in the Keychain instead of
localStorage. Pagination still caps at Reverb's 50 pages.

## Using the library directly

```ts
import { searchListings, priceStats, listingUrl } from "@better-reverb-search/reverb-api";

const { total, listings, humanizedParams } = await searchListings({
  query: "1963 Stratocaster",
  priceMin: 2000,
  condition: "excellent",   // typed — a typo throws instead of silently no-oping
  perPage: 50,
});

console.log(total, humanizedParams, priceStats(listings));
console.log(listings.map(listingUrl));
```

`searchListings` also takes `{ apiKey, signal, pageAll, pageLimit }`. Errors are
`RevError`, carrying a `type` (`api` | `auth` | `validation` | `schema` |
`other`) and the CLI's original exit code.

## What maps to what

| Rust                              | TypeScript                    | Notes                                                        |
| --------------------------------- | ----------------------------- | ------------------------------------------------------------ |
| `reverb-api/error.rs`             | `src/error.ts`                | `RevError` + exit codes 1–5, 1:1                              |
| `reverb-api/client.rs`            | `src/client.ts`               | 429 backoff, `retry-after`, 5 attempts, 60s cap               |
| `reverb-api/validate.rs`          | `src/validate.ts`             | 1:1, incl. its unit tests                                     |
| `reverb-api/schema.rs`            | `src/schema.ts`               | `ApiSchema` types (unused in Rust too)                        |
| `reverb-api/services.rs`          | `src/services.ts`             | `SERVICES` registry                                           |
| `reverb-api-cli/executor.rs`      | `src/executor.ts`             | `ArgMatches` → an options object                              |
| `reverb-api-cli/formatter.rs`     | `src/formatter.ts`            | returns a string instead of writing to `dyn Write`            |
| `reverb-api-cli/auth.rs`          | `src/auth.ts`                 | env → localStorage → `~/.config/revcli/api_key`               |
| `reverb-api-cli/helpers/`         | `src/helpers/`                | `Helper` trait; `+draft` is still a skeleton, as in Rust      |
| `reverb-api-cli/logging.rs`       | `src/logging.ts`              | `REVERB_CLI_LOG`, off by default                              |
| —                                 | `src/search.ts`               | new: typed `SearchQuery`, `priceStats`, `discountPercent`     |

Not ported: `main.rs`, `commands.rs`, `auth_commands.rs`, `schema_cmd.rs` — clap
argument parsing and `process::exit`, which have no browser equivalent.

The Node-only config-file branch in `auth.ts` reaches `node:fs` through
`process.getBuiltinModule` rather than an import. That keeps `resolveApiKey`
synchronous and means no bundler ever sees a `node:fs` specifier to fail on in a
browser build. `require()` does not work here — the output is ESM.

## Theming

`apps/web/app/globals.css` maps its palette onto Reverb's Cadence design
tokens — light and dark both fully resolved through the `--rc-color-palette-*`
primitives, with the source token named on every line.

Two things to know before editing it:

- Cadence sets `html { font-size: 62.5% }` so `1rem` = 10px in their sheets.
  We don't, so token rem values are converted to px (`--rc-border-radius-md:
  0.8rem` → `8px`). Pasting a token value in unconverted silently halves it.
- Theme is driven by `data-theme` on `<html>`, stamped by a blocking inline
  script in `layout.tsx` before first paint. Don't use Tailwind's `dark:`
  variant anywhere — it follows `prefers-color-scheme` and will disagree with
  an explicit user choice. Add a token to both blocks instead.

## API notes worth knowing

Verified against the live API while porting:

- **`GET /api/listings` _is_ public marketplace search**, authenticated or not,
  and returns the same results as `/api/listings/all`. Your own shop's listings
  are at `/api/my/listings`.
- **Unknown query params are silently ignored**, not rejected —
  `condition=bogusvalue` returns the *unfiltered* set. Worse, some are
  misrouted: `item_state=sold` is parsed as a *location* and returns 0 results,
  which is indistinguishable from a legitimate empty result. This is why
  `SearchQuery` is typed and validated rather than a plain param bag.
- **Sold comps use `show_only_sold=true`** (not `show_sold`/`state=sold`, which
  do nothing). Sold listings carry `original_price` — the ask — alongside
  `price`, which is what it actually cleared for.
- **Sold listing web URLs need `?show_sold=true`** appended, which is what
  `listingUrl()` does for anything whose `state.slug` is `sold`. Keyed off the
  listing rather than the current view mode, so a sold listing in a mixed set
  still links correctly.
- `humanized_params` in every response is Reverb's own echo of how it parsed
  your filters. The UI surfaces it; it's the cheapest check that a filter did
  something.
- Results cap at **50 pages** regardless of `total`.
- `/api/priceguide` now returns 403 "no longer publicly available".
- reverb.com itself sits behind Cloudflare and 403s non-browser clients, so
  `curl`ing a listing URL to check it proves nothing. The JSON API does not.
