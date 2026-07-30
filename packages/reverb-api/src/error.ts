/**
 * Structured error type for all Reverb operations.
 *
 * Port of `reverb-api/src/error.rs`.
 *
 * Exit codes:
 *   0 — success
 *   1 — API error (4xx/5xx from Reverb)
 *   2 — authentication error (missing/invalid API key)
 *   3 — validation error (bad user input)
 *   4 — schema error (unknown resource or method)
 *   5 — unexpected error
 */
export type RevErrorKind = "api" | "auth" | "validation" | "schema" | "other";

const EXIT_CODES: Record<RevErrorKind, number> = {
  api: 1,
  auth: 2,
  validation: 3,
  schema: 4,
  other: 5,
};

export class RevError extends Error {
  readonly type: RevErrorKind;
  /** HTTP status, present only on `type: "api"`. */
  readonly code?: number;

  private constructor(type: RevErrorKind, message: string, code?: number) {
    super(message);
    this.name = "RevError";
    this.type = type;
    this.code = code;
  }

  static api(code: number, message: string): RevError {
    return new RevError("api", `API error ${code}: ${message}`, code);
  }

  static auth(message: string): RevError {
    return new RevError("auth", `Authentication error: ${message}`);
  }

  static validation(message: string): RevError {
    return new RevError("validation", `Validation error: ${message}`);
  }

  static schema(message: string): RevError {
    return new RevError("schema", `Schema error: ${message}`);
  }

  /** Wraps an arbitrary thrown value — the `RevError::Other(anyhow::Error)` arm. */
  static other(cause: unknown): RevError {
    const message = cause instanceof Error ? cause.message : String(cause);
    const err = new RevError("other", message);
    err.cause = cause;
    return err;
  }

  get exitCode(): number {
    return EXIT_CODES[this.type];
  }

  /** Matches the Rust `#[serde(tag = "type", rename_all = "snake_case")]` shape. */
  toJSON(): Record<string, unknown> {
    return this.type === "api"
      ? { type: "api", code: this.code, message: this.message }
      : { type: this.type, message: this.message };
  }
}

/** Port of the CLI's `error::print_error` — returns the payload instead of writing to stdout. */
export function errorPayload(e: RevError): { error: string; exit_code: number } {
  return { error: e.message, exit_code: e.exitCode };
}

/** Normalize an unknown thrown value into a RevError. */
export function toRevError(e: unknown): RevError {
  return e instanceof RevError ? e : RevError.other(e);
}
