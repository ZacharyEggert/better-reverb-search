import { timingSafeEqual } from "node:crypto";
import { rateLimit } from "@/lib/rate-limit";

const LIMIT = 5;
const WINDOW_MS = 60_000;

/**
 * `POST /api/bypass-limit` with `{ "key": "..." }` — returns `{ valid: bool }`
 * telling the iOS app whether the key unlocks the limit bypass.
 *
 * Rate limited per client IP so the key can't be brute forced.
 */
export async function POST(request: Request) {
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "unknown";

  const retryAfter = rateLimit(`bypass:${ip}`, LIMIT, WINDOW_MS);
  if (retryAfter) {
    return Response.json(
      { error: `rate limit exceeded — ${LIMIT} requests per minute` },
      { status: 429, headers: { "retry-after": String(retryAfter) } },
    );
  }

  const key = await request
    .json()
    .then((b: unknown) =>
      typeof b === "object" && b && "key" in b && typeof b.key === "string" ? b.key : "",
    )
    .catch(() => "");

  return Response.json({ valid: matches(key, process.env.LIMIT_BYPASS_KEY) });
}

function matches(given: string, expected: string | undefined) {
  if (!expected) return false; // unset env never validates
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
