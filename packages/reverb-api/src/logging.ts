/**
 * Port of `reverb-api-cli/src/logging.rs`.
 *
 * The Rust version wires `tracing_subscriber` with an `EnvFilter` from
 * `REVERB_CLI_LOG` (off by default), writing to stderr. There is no tracing
 * runtime in the browser, so this is a level-filtered console shim with the
 * same env var and the same default: off.
 */
export type LogLevel = "off" | "error" | "warn" | "info" | "debug" | "trace";

const ORDER: Record<LogLevel, number> = {
  off: 0,
  error: 1,
  warn: 2,
  info: 3,
  debug: 4,
  trace: 5,
};

let level: LogLevel = "off";

/** Read `REVERB_CLI_LOG` where a process env exists; otherwise stay off. */
export function init(explicit?: LogLevel): void {
  if (explicit) {
    level = explicit;
    return;
  }
  const raw = globalThis.process?.env?.REVERB_CLI_LOG;
  // The Rust EnvFilter accepts "revcli=debug"; take the level after the last '='.
  const candidate = raw?.split("=").pop()?.trim().toLowerCase();
  if (candidate && candidate in ORDER) level = candidate as LogLevel;
}

export function setLevel(next: LogLevel): void {
  level = next;
}

function log(at: LogLevel, message: string): void {
  if (ORDER[level] >= ORDER[at] && level !== "off") {
    console.error(`[${at}] ${message}`);
  }
}

export const error = (m: string) => log("error", m);
export const warn = (m: string) => log("warn", m);
export const info = (m: string) => log("info", m);
export const debug = (m: string) => log("debug", m);
export const trace = (m: string) => log("trace", m);
