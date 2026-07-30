# better-reverb-search

pnpm monorepo. A TypeScript port of the [`reverb-cli`](../reverb-cli) Rust crates,
plus a Next.js app that searches Reverb listings and sold comps.

```
packages/reverb-api   port of the reverb-api + reverb-api-cli crates
apps/web              Next.js 15 search UI
```

## Quick start

```sh
pnpm install
pnpm dev          # library in watch mode + next dev on :3000
pnpm test         # vitest, in packages/reverb-api
pnpm build
```

No API key is required — every endpoint the app uses (`GET /api/listings`)
answers unauthenticated. Set one to raise your rate limit:

```sh
export REVERB_API_KEY=...   # or storeApiKey() → localStorage in the browser
```

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
- `humanized_params` in every response is Reverb's own echo of how it parsed
  your filters. The UI surfaces it; it's the cheapest check that a filter did
  something.
- Results cap at **50 pages** regardless of `total`.
- `/api/priceguide` now returns 403 "no longer publicly available".
