---
name: reverb-search-api
description: "Search Reverb listings and sold comps via the hosted better-reverb-search JSON API (reverb-search.diablo.guitars). Use for questions about used gear prices, what a guitar/pedal/amp sells for, active listings, or sold comps — anything answerable by a Reverb search. Prefer this over scraping reverb.com."
metadata:
  version: 0.1.0
---

# reverb-search-api

`GET https://reverb-search.diablo.guitars/api/search` — public marketplace
search over Reverb listings and completed sales, trimmed to the fields worth
reading.

> **AUTH:** required. Send the user's own Reverb key (reverb.com/my/api_access)
> as `Authorization: Bearer $REVERB_API_KEY` or `x-api-key`. No key → `401`.
> There is no server-side fallback key — if `$REVERB_API_KEY` isn't set, ask for
> one rather than retrying.

```bash
curl -s -H "Authorization: Bearer $REVERB_API_KEY" \
  "https://reverb-search.diablo.guitars/api/search?query=1963%20Stratocaster&perPage=50"
```

## Query params

| Param                   | Example                 | Notes                                                     |
|-------------------------|-------------------------|-----------------------------------------------------------|
| `query`                 | `1963 Stratocaster`     | Free text. The most reliable filter — see caveats below    |
| `make` / `model`        | `Fender` / `Jazzmaster` | Active listings only                                       |
| `category`              | `electric-guitars`      | Category slug                                              |
| `productType`           | `effects-and-pedals`    | `electric-guitars`, `acoustic-guitars`, `bass-guitars`, `amps`, `effects-and-pedals`, `pro-audio` |
| `priceMin` / `priceMax` | `2000`                  | Whole currency units                                       |
| `yearMin` / `yearMax`   | `1960`                  |                                                            |
| `condition`             | `used`                  | Bucket: `used`, `new`, `b-stock`. Or a grade: `mint`, `excellent`, `very-good`, `good`, `fair`, `poor`, `non-functioning` |
| `sort`                  | `price\|asc`            | also `price\|desc`, `published_at\|desc` (default), `published_at\|asc` |
| `shipsTo`               | `US`                    | ISO country code                                           |
| `showOnlySold`          | `1`                     | **Sold comps** instead of active listings                  |
| `page` / `perPage`      | `1` / `50`              | Results cap at 50 pages total                              |

### Caveats that will silently give you wrong answers

Verified against the live endpoint:

- **`showOnlySold=1` is incompatible with `make`, `model`, and `productType`** —
  those combinations return `API error 500`. For sold comps, put the make and
  model in `query` instead: `query=Fender Jazzmaster&showOnlySold=1`.
- **`category` is ignored on sold searches** — it returns 200, but
  `humanizedParams` shows the filter never applied. Don't trust the result.
- **`model` is frequently ignored even on active searches** —
  `make=Fender&model=Jazzmaster` echoes back just `Fender`.
- **`condition` has two axes.** `used` / `new` / `b-stock` are coarse buckets
  that split the whole set (`used` 25.8k + `new` 51.6k ≈ 77.8k total for
  "Stratocaster"); the seven grades are slices of `used` (`excellent` 9.8k).
  For price research you almost always want `condition=used`. Pass one value,
  not both — there's no way to combine them. `new` and `non-functioning` do
  filter but *don't* appear in `humanizedParams`; compare `total` against the
  unfiltered count to confirm those two landed.
- **Always read `humanizedParams`** before reporting numbers. It's Reverb's own
  description of how it parsed your filters and it's the only cheap way to catch
  a dropped one.

## Response

```jsonc
{
  "total": 77808, "currentPage": 1, "perPage": 2, "totalPages": 50,
  "humanizedParams": "\"stratocaster\" Gear",   // check this — see caveats
  "listings": [{
    "id": 100154665,
    "title": "Genuine 1990 Fender MIM Black Standard Strat",
    "year": "1990",                              // free text: "1963", "2020s", or null
    "condition": { "slug": "very-good", "display_name": "Very Good" },
    "price": { "display": "$199.99", "amount_cents": 19999, "currency": "USD" },
    "originalPrice": null,      // the ask — sold listings only
    "discountPercent": null,    // how far below the ask it cleared
    "shopName": "More Strats, please",
    "publishedAt": "2026-08-05T17:29:29-05:00",
    "photo": "https://rvb-img.reverb.com/...",
    "url": "https://reverb.com/item/100154665-...",
    "sold": false
  }]
}
```

Errors: `{ "error": "...", "type": "api|auth|validation|schema" }` — `401`
missing/bad key, `400` validation or schema, otherwise Reverb's own status.

## Rate limit

**5 requests per 5 seconds per key.** Over that: `429` with a `retry-after`
header — sleep that many seconds, then retry. Get more data by raising `perPage`
(50 works), not by firing more requests. `sleep 2` between calls in a loop.

## Recipes

**What does it actually sell for** — sold comps, then the price spread:

```bash
curl -s -H "Authorization: Bearer $REVERB_API_KEY" \
  "https://reverb-search.diablo.guitars/api/search?query=Fender%20Jazzmaster&showOnlySold=1&yearMin=1960&yearMax=1965&perPage=50" \
  | jq '[.listings[].price.amount_cents] | sort
        | {n: length, min: .[0]/100, median: .[length/2|floor]/100, max: .[-1]/100}'
```

Widen `priceMin` if the spread looks absurd — a bare model name pulls in parts
and pickguards alongside whole instruments.

**Cheapest actives** — compare against the sold median above:

```bash
curl -s -H "Authorization: Bearer $REVERB_API_KEY" \
  "https://reverb-search.diablo.guitars/api/search?query=Jazzmaster&sort=price%7Casc&priceMin=1000&perPage=50" \
  | jq -r '.listings[] | "\(.price.display)\t\(.year // "—")\t\(.title)\t\(.url)"'
```

**Deepest discounts on recent sales** — `discountPercent` is ask vs. clear:

```bash
curl -s -H "Authorization: Bearer $REVERB_API_KEY" \
  "https://reverb-search.diablo.guitars/api/search?query=Stratocaster&showOnlySold=1&priceMin=1500&perPage=50" \
  | jq -r '[.listings[] | select(.discountPercent)] | sort_by(-.discountPercent)[:10][]
           | "-\(.discountPercent)%\t\(.originalPrice) → \(.price.display)\t\(.title)"'
```

## Notes

- Stats describe only the listings you loaded, never all `total` matches. Say so
  when you report a median.
- Sold URLs already carry `?show_sold=true`; without it reverb.com 404s them.
- reverb.com pages sit behind Cloudflare and 403 non-browser clients, so
  `curl`ing a listing URL to verify it proves nothing. This JSON API does not.
- Same search runs in the browser at `https://reverb-search.diablo.guitars` and
  the query params match, so any API URL doubles as a shareable UI link.
