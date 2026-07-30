/**
 * Port of `reverb-api/src/services.rs`.
 *
 * Registry entry mapping a short resource name to its API path prefix.
 * The commented-out entries are commented out in the Rust source too — kept
 * here so the two registries stay diffable.
 */
export interface ServiceEntry {
  name: string;
  pathPrefix: string;
  description: string;
}

/** All known Reverb API resources. */
export const SERVICES: readonly ServiceEntry[] = [
  {
    name: "listings",
    pathPrefix: "listings",
    description: "Search and manage Reverb listings",
  },
  // { name: "orders", pathPrefix: "orders", description: "View and manage orders" },
  // { name: "conversations", pathPrefix: "conversations", description: "Buyer/seller messaging" },
  // { name: "shop", pathPrefix: "shop", description: "Shop profile and settings" },
  // { name: "categories", pathPrefix: "categories", description: "Browse Reverb categories" },
  // { name: "handpicked", pathPrefix: "handpicked", description: "Curated handpicked collections" },
  // { name: "priceguide", pathPrefix: "priceguide", description: "Price guide for instruments" },
  //   NOTE: /api/priceguide now returns 403 "no longer publicly available".
  // { name: "shipping", pathPrefix: "shipping", description: "Shipping profiles and rates" },
  // { name: "feedback", pathPrefix: "feedback", description: "Seller and buyer feedback" },
  // { name: "webhooks", pathPrefix: "webhooks", description: "Manage webhook subscriptions" },
];

export function findService(name: string): ServiceEntry | undefined {
  return SERVICES.find((s) => s.name === name);
}
