import {
  executeWithRetry,
  sleep,
  USER_AGENT,
  withTimeout,
} from "./client.js";
import { RevError, toRevError } from "./error.js";
import { format, type Format } from "./formatter.js";
import { getHelper } from "./helpers/index.js";
import { trace } from "./logging.js";
import type { HttpMethod } from "./schema.js";
import { validateResourceName } from "./validate.js";

/** Port of `reverb-api-cli/src/executor.rs`. */
export const BASE_URL = "https://api.reverb.com/api";

export type ParamValue = string | number | boolean;

export interface ExecuteOptions {
  /** Resource name, e.g. "listings". */
  resource: string;
  /** Method name, e.g. "list" | "get" | "create" | "update" | "delete" | "+draft". */
  method: string;
  /** Free-text search string, sent as the `query` param. */
  query?: string;
  /** URL/query parameters. `{key}` placeholders in the path are substituted. */
  params?: Record<string, ParamValue>;
  /** Request body for POST/PUT/PATCH. */
  json?: unknown;
  /** Validate inputs without sending the request. */
  dryRun?: boolean;
  perPage?: number;
  /** Automatically paginate through results. */
  pageAll?: boolean;
  /** Maximum number of pages to fetch. Default 10. */
  pageLimit?: number;
  /** Milliseconds to wait between page requests. Default 100. */
  pageDelay?: number;
  format?: Format;
  apiKey?: string;
  signal?: AbortSignal;
}

export interface ExecuteResult {
  /** One entry per fetched page, in order. */
  pages: unknown[];
  /** The pages run through the requested formatter and concatenated. */
  formatted: string;
}

export async function execute(options: ExecuteOptions): Promise<ExecuteResult> {
  // Check if a helper wants to handle this first.
  const helper = getHelper(options.resource);
  if (helper && (await helper.handle(options, options.apiKey))) {
    return { pages: [], formatted: "" };
  }

  if (!options.method) {
    throw RevError.validation("no method specified");
  }

  const fmt: Format = options.format ?? "json";
  const pageLimit = options.pageLimit ?? 10;
  const pageDelay = options.pageDelay ?? 100;

  if (options.dryRun) {
    const lines = [`dry-run: would call ${options.resource}.${options.method}`];
    if (options.params)
      lines.push(`  params: ${JSON.stringify(options.params, null, 2)}`);
    if (options.json !== undefined)
      lines.push(`  body:   ${JSON.stringify(options.json, null, 2)}`);
    return { pages: [], formatted: `${lines.join("\n")}\n` };
  }

  // Resolve HTTP method and path from the schema map.
  const { httpMethod, path } = resolveMethod(options.resource, options.method);
  const { url, extraQuery } = buildUrl(path, options.params);

  const pages: unknown[] = [];
  const chunks: string[] = [];
  let page = 0;
  let cursor: string | undefined;

  for (;;) {
    const target = new URL(url);
    if (cursor !== undefined) target.searchParams.set("page", cursor);
    if (options.perPage !== undefined)
      target.searchParams.set("per_page", String(options.perPage));
    for (const [k, v] of extraQuery) target.searchParams.append(k, v);
    if (options.query !== undefined)
      target.searchParams.set("query", options.query);

    const headers: Record<string, string> = {
      Accept: "application/hal+json",
      "Accept-Version": "3.0",
    };
    // Browsers forbid setting User-Agent; only send it where it is allowed.
    if (!globalThis.window) headers["User-Agent"] = USER_AGENT;
    if (options.apiKey) headers.Authorization = `Bearer ${options.apiKey}`;
    if (options.json !== undefined) headers["Content-Type"] = "application/json";

    const response = await executeWithRetry(
      () =>
        fetch(target, {
          method: httpMethod,
          headers,
          body: options.json === undefined ? undefined : JSON.stringify(options.json),
          signal: withTimeout(options.signal),
        }),
      { signal: options.signal },
    );

    const status = response.status;
    const bodyText = await response.text().catch((e) => {
      throw toRevError(e);
    });
    trace(`raw API response status=${status}`);

    let body: unknown;
    try {
      body = JSON.parse(bodyText);
    } catch (e) {
      throw RevError.other(
        new Error(
          `failed to parse response as JSON: ${String(e)}\n raw body: ${bodyText}`,
        ),
      );
    }

    if (!response.ok) {
      const message =
        (isObject(body) && typeof body.message === "string" && body.message) ||
        (isObject(body) && typeof body.Error === "string" && body.Error) ||
        "unknown error";
      throw RevError.api(status, message);
    }

    pages.push(body);
    chunks.push(format(body, fmt, page));
    page += 1;

    // Pagination
    if (options.pageAll && page < pageLimit && isObject(body)) {
      const current = Number(body.current_page);
      const total = Number(body.total_pages);
      if (Number.isFinite(current) && Number.isFinite(total) && current < total) {
        cursor = String(current + 1);
        await sleep(pageDelay, options.signal);
        continue;
      }
    }

    break;
  }

  return { pages, formatted: chunks.join("") };
}

export function resolveMethod(
  resource: string,
  method: string,
): { httpMethod: HttpMethod; path: string } {
  // TODO (carried over from Rust): load from schema registry.
  const httpMethod: HttpMethod =
    method === "create"
      ? "POST"
      : method === "update"
        ? "PUT"
        : method === "delete"
          ? "DELETE"
          : "GET";

  switch (method) {
    case "list":
    case "create":
      return { httpMethod, path: `${BASE_URL}/${resource}` };
    case "get":
    case "show":
    case "update":
    case "delete":
      return { httpMethod, path: `${BASE_URL}/${resource}/{id}` };
    default:
      throw RevError.schema(
        `unknown method '${method}' for resource '${resource}'`,
      );
  }
}

/**
 * Returns `{ url, extraQuery }`.
 * Params matching `{key}` placeholders are substituted into the path;
 * all others are returned as query params.
 */
export function buildUrl(
  path: string,
  params?: Record<string, ParamValue>,
): { url: string; extraQuery: [string, string][] } {
  let url = path;
  const extraQuery: [string, string][] = [];

  for (const [k, v] of Object.entries(params ?? {})) {
    const placeholder = `{${k}}`;
    const val = String(v);
    if (url.includes(placeholder)) {
      validateResourceName(val);
      url = url.replaceAll(placeholder, encodeURIComponent(val));
    } else {
      extraQuery.push([k, val]);
    }
  }

  if (url.includes("{")) {
    const missing = url.match(/\{(\w+)\}/)?.[1];
    throw RevError.validation(`missing required path parameter '${missing}'`);
  }

  return { url, extraQuery };
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null;
}
