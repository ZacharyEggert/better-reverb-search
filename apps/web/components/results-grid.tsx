"use client";

import {
  discountPercent,
  listingUrl,
  type Listing,
} from "@better-reverb-search/reverb-api";

export function ResultsGrid({
  listings,
  sold,
}: {
  listings: Listing[];
  sold: boolean;
}) {
  return (
    <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {listings.map((l) => {
        const off = discountPercent(l);
        const photo =
          l.photos?.[0]?._links?.thumbnail?.href ?? l._links?.photo?.href;
        return (
          <li
            key={l.id}
            className="overflow-hidden rounded-lg border border-[var(--color-line)]"
          >
            <a
              href={listingUrl(l) ?? "#"}
              target="_blank"
              rel="noreferrer noopener"
              className="block"
            >
              {photo ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={photo}
                  alt={l.title}
                  loading="lazy"
                  className="aspect-4/3 w-full bg-black/5 object-cover"
                />
              ) : (
                <div className="aspect-4/3 w-full bg-black/5" />
              )}
              <div className="space-y-1 p-3">
                <div className="line-clamp-2 text-sm leading-snug">{l.title}</div>
                <div className="flex items-baseline gap-2">
                  <span className="tnum font-semibold">{l.price?.display}</span>
                  {sold && l.original_price && (
                    <span className="tnum text-xs text-[var(--color-muted)] line-through">
                      {l.original_price.display}
                    </span>
                  )}
                  {off !== undefined && (
                    <span className="tnum text-xs text-[var(--color-accent)]">
                      −{off}%
                    </span>
                  )}
                </div>
                <div className="text-xs text-[var(--color-muted)]">
                  {[l.year, l.condition?.display_name, l.shop_name]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
              </div>
            </a>
          </li>
        );
      })}
    </ul>
  );
}
