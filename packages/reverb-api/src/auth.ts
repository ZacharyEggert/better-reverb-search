import { RevError } from "./error.js";

/**
 * Port of `reverb-api-cli/src/auth.rs`.
 *
 * The Rust version resolves: env var → `~/.config/revcli/api_key` (chmod 600).
 * This build is isomorphic, so the browser's localStorage slots in where the
 * config file goes. Resolution order:
 *   1. `REVERB_API_KEY` env var          (Node)
 *   2. `localStorage["revcli.api_key"]`  (browser)
 *   3. `~/.config/revcli/api_key`        (Node)
 *
 * NOTE: every endpoint this app uses (`GET /api/listings`) also answers
 * unauthenticated, so a missing key is not fatal for search — see `resolveApiKeyOptional`.
 */
const ENV_VAR = "REVERB_API_KEY";
const KEY_FILE_NAME = "api_key";
const STORAGE_KEY = "revcli.api_key";

export function resolveApiKeyOptional(): string | undefined {
  const fromEnv = globalThis.process?.env?.[ENV_VAR]?.trim();
  if (fromEnv) return fromEnv;

  const fromStorage = safeLocalStorage()?.getItem(STORAGE_KEY)?.trim();
  if (fromStorage) return fromStorage;

  const fromFile = readKeyFileSync()?.trim();
  if (fromFile) return fromFile;

  return undefined;
}

/** Throws `RevError.auth` when no key is configured — matches the Rust signature. */
export function resolveApiKey(): string {
  const key = resolveApiKeyOptional();
  if (key) return key;
  throw RevError.auth(
    `no API key found — set ${ENV_VAR} or store one via storeApiKey()`,
  );
}

/** Persist the API key. Browser → localStorage; Node → config file at mode 0600. */
export function storeApiKey(key: string): void {
  const trimmed = key.trim();
  if (!trimmed) throw RevError.validation("API key cannot be empty");

  const storage = safeLocalStorage();
  if (storage) {
    storage.setItem(STORAGE_KEY, trimmed);
    return;
  }
  writeKeyFileSync(trimmed);
}

/** Remove the stored API key. */
export function removeApiKey(): void {
  safeLocalStorage()?.removeItem(STORAGE_KEY);
  removeKeyFileSync();
}

function safeLocalStorage(): Storage | undefined {
  try {
    return globalThis.localStorage ?? undefined;
  } catch {
    // Access throws in some sandboxed/SSR contexts.
    return undefined;
  }
}

// --- Node-only config file, mirroring the Rust `~/.config/revcli/api_key` path ---
// Resolved via `process.getBuiltinModule` rather than an import: it is
// synchronous (so resolveApiKey stays sync), and a bundler never sees a
// `node:fs` specifier to fail on when building for the browser.

function nodeFs(): typeof import("node:fs") | undefined {
  // getBuiltinModule is Node >=22.3; absent in browsers and older runtimes.
  return globalThis.process?.getBuiltinModule?.("node:fs");
}

function configKeyPath(): string | undefined {
  const env = globalThis.process?.env;
  if (!env) return undefined;
  const override = env.REVERB_CLI_CONFIG_DIR;
  const base =
    override ??
    (env.XDG_CONFIG_HOME
      ? `${env.XDG_CONFIG_HOME}/revcli`
      : env.HOME
        ? `${env.HOME}/.config/revcli`
        : undefined);
  return base ? `${base}/${KEY_FILE_NAME}` : undefined;
}

function readKeyFileSync(): string | undefined {
  const fs = nodeFs();
  const path = configKeyPath();
  if (!fs || !path || !fs.existsSync(path)) return undefined;
  try {
    return fs.readFileSync(path, "utf8");
  } catch (e) {
    throw RevError.auth(`failed to read api key file: ${String(e)}`);
  }
}

function writeKeyFileSync(key: string): void {
  const fs = nodeFs();
  const path = configKeyPath();
  if (!fs || !path) {
    throw RevError.auth("could not determine config directory");
  }
  try {
    fs.mkdirSync(path.slice(0, path.lastIndexOf("/")), { recursive: true });
    fs.writeFileSync(path, key, { mode: 0o600 });
    fs.chmodSync(path, 0o600);
  } catch (e) {
    throw RevError.auth(`failed to write api key: ${String(e)}`);
  }
}

function removeKeyFileSync(): void {
  const fs = nodeFs();
  const path = configKeyPath();
  if (!fs || !path || !fs.existsSync(path)) return;
  try {
    fs.rmSync(path);
  } catch (e) {
    throw RevError.auth(`failed to remove api key: ${String(e)}`);
  }
}
