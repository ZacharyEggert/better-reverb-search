// ponytail: in-process sliding window, so limits are per server instance.
// Move to Redis/Upstash if this ever runs on more than one.
const hits = new Map<string, number[]>();

/**
 * Records a hit for `id`; returns retry-after seconds when it's over `limit`
 * requests per `windowMs`, otherwise undefined.
 */
export function rateLimit(id: string, limit: number, windowMs: number): number | undefined {
  const now = Date.now();
  const cutoff = now - windowMs;

  for (const [k, times] of hits) {
    const kept = times.filter((t) => t > cutoff);
    if (kept.length) hits.set(k, kept);
    else hits.delete(k);
  }

  const recent = hits.get(id) ?? [];
  if (recent.length >= limit) {
    return Math.max(1, Math.ceil((recent[0]! + windowMs - now) / 1000));
  }
  hits.set(id, [...recent, now]);
  return undefined;
}
