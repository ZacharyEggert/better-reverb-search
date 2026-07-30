"use client";

import {
  removeApiKey,
  resolveApiKeyOptional,
  storeApiKey,
} from "@better-reverb-search/reverb-api";
import { useEffect, useState } from "react";

/**
 * Optional personal API key. Search answers unauthenticated, but Reverb's
 * anonymous rate limit is far tighter — a key mostly buys headroom.
 *
 * Persistence is `auth.ts`'s localStorage slot, the same one the CLI mirrors to
 * `~/.config/revcli/api_key`, so nothing new is invented here. Read in an
 * effect rather than during render: localStorage doesn't exist during SSR and
 * a render-time read would hydrate mismatched.
 */
export function ApiKeyField() {
  const [saved, setSaved] = useState(false);
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState("");

  useEffect(() => setSaved(!!resolveApiKeyOptional()), []);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-full border border-[var(--color-line)] px-4 py-1.5 text-sm text-[var(--color-muted)]"
      >
        {saved ? "API key ✓" : "Add API key"}
      </button>
    );
  }

  return (
    <span className="flex items-center gap-2">
      <input
        type="password"
        autoFocus
        placeholder={saved ? "Stored — enter to replace" : "Reverb API token"}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        aria-label="Reverb API key"
        className="h-9 w-56 rounded-[var(--radius-input)] border border-[var(--color-line-input)] bg-[var(--color-input-bg)] px-3 text-sm outline-none"
      />
      <button
        type="button"
        disabled={!draft.trim()}
        onClick={() => {
          storeApiKey(draft);
          setDraft("");
          setSaved(true);
          setOpen(false);
        }}
        className="rounded-full border border-[var(--color-line-strong)] px-3 py-1 text-sm disabled:opacity-40"
      >
        Save
      </button>
      {saved && (
        <button
          type="button"
          onClick={() => {
            removeApiKey();
            setSaved(false);
            setOpen(false);
          }}
          className="rounded-full border border-[var(--color-line)] px-3 py-1 text-sm text-[var(--color-muted)]"
        >
          Clear
        </button>
      )}
    </span>
  );
}
