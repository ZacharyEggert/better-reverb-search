import type { ExecuteOptions } from "../executor.js";
import { ListingsHelper } from "./listings.js";

/**
 * Port of `reverb-api-cli/src/helpers/mod.rs`.
 *
 * Helpers add custom operations (prefixed with `+`) that go beyond what the
 * schema-driven executor can provide — e.g. multi-step workflows or format
 * translation. `injectCommands` in Rust mutates a clap `Command`; here it
 * declares the operations so a host (CLI or UI) can render them.
 */
export interface HelperCommandArg {
  name: string;
  help: string;
  required: boolean;
  /** Closed set of accepted values, if any. */
  choices?: readonly string[];
}

export interface HelperCommand {
  name: string;
  about: string;
  args: readonly HelperCommandArg[];
}

export interface Helper {
  /** Custom operations this helper contributes for its resource. */
  injectCommands(): readonly HelperCommand[];

  /**
   * Handle a matched operation. Resolves `true` if handled, `false` to fall
   * through to the schema-driven executor.
   */
  handle(options: ExecuteOptions, apiKey?: string): Promise<boolean>;
}

/** Return the helper for a given resource name, if one exists. */
export function getHelper(resource: string): Helper | undefined {
  switch (resource) {
    case "listings":
      return new ListingsHelper();
    default:
      return undefined;
  }
}

/** Percent-encode a string for safe embedding in a URL path segment. */
export function encodePathSegment(s: string): string {
  // encodeURIComponent leaves !'()* alone; NON_ALPHANUMERIC in Rust does not.
  return encodeURIComponent(s).replace(
    /[!'()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

export { ListingsHelper };
