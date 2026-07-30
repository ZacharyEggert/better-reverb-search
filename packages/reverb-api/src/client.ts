import { RevError, toRevError } from "./error.js";
import { warn } from "./logging.js";

/**
 * Port of `reverb-api/src/client.rs`.
 *
 * The Rust version memoizes a `reqwest::Client` with a user-agent and 30s timeout.
 * `fetch` has no client object, so the equivalent config lives in `requestInit`
 * and a per-request AbortSignal timeout.
 */
export const USER_AGENT = "revcli-web/0.1.0";
export const REQUEST_TIMEOUT_MS = 30_000;

export interface RetryOptions {
  maxAttempts?: number;
  /** Initial backoff, doubled each attempt up to `maxDelayMs`. */
  initialDelayMs?: number;
  maxDelayMs?: number;
  signal?: AbortSignal;
}

/** Execute a request with exponential-backoff retry on 429. */
export async function executeWithRetry(
  buildRequest: () => Promise<Response>,
  options: RetryOptions = {},
): Promise<Response> {
  const maxAttempts = options.maxAttempts ?? 5;
  const maxDelayMs = options.maxDelayMs ?? 60_000;
  let delayMs = options.initialDelayMs ?? 1_000;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let resp: Response;
    try {
      resp = await buildRequest();
    } catch (e) {
      throw toRevError(e);
    }

    if (resp.status === 429) {
      const header = resp.headers.get("retry-after");
      const parsed = header === null ? NaN : Number.parseInt(header, 10);
      const retryAfterMs =
        Number.isFinite(parsed) && parsed >= 0 ? parsed * 1_000 : delayMs;

      if (attempt < maxAttempts) {
        warn(`rate limited, retrying (attempt=${attempt} in ${retryAfterMs}ms)`);
        await sleep(retryAfterMs, options.signal);
        delayMs = Math.min(delayMs * 2, maxDelayMs);
        continue;
      }
    }

    return resp;
  }

  throw RevError.api(429, "rate limit exceeded after retries");
}

export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(toRevError(signal.reason));
      return;
    }
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    function onAbort() {
      clearTimeout(timer);
      reject(toRevError(signal!.reason));
    }
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

/** Merge a caller signal with a timeout, so requests can't hang past REQUEST_TIMEOUT_MS. */
export function withTimeout(signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  return signal ? AbortSignal.any([signal, timeout]) : timeout;
}
