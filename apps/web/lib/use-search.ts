"use client";

import {
  RevError,
  resolveApiKeyOptional,
  searchListings,
  type SearchQuery,
  type SearchResult,
} from "@better-reverb-search/reverb-api";
import { useCallback, useRef, useState } from "react";

export interface SearchState {
  result?: SearchResult;
  error?: string;
  loading: boolean;
}

/**
 * Runs a search on demand. Deliberately not a useEffect-on-query hook: searches
 * fire from an explicit submit, so there is no dependency-array race to lose.
 * The in-flight request is aborted when a newer one starts.
 */
export function useSearch() {
  const [state, setState] = useState<SearchState>({ loading: false });
  const inFlight = useRef<AbortController>(null);

  /** `append` keeps the previous listings and tacks the new page onto them. */
  const run = useCallback(async (query: SearchQuery, append = false) => {
    inFlight.current?.abort();
    const controller = new AbortController();
    inFlight.current = controller;

    setState((s) => ({ ...s, loading: true, error: undefined }));
    try {
      // Read per-search, not once at mount: the key can be added mid-session.
      const result = await searchListings(query, {
        signal: controller.signal,
        apiKey: resolveApiKeyOptional(),
      });
      if (controller.signal.aborted) return;
      setState((s) => ({
        result:
          append && s.result
            ? { ...result, listings: [...s.result.listings, ...result.listings] }
            : result,
        loading: false,
      }));
    } catch (e) {
      if (controller.signal.aborted) return;
      // RevError already carries a human-readable message and a type.
      const message = e instanceof RevError ? e.message : `Unexpected error: ${String(e)}`;
      setState({ error: message, loading: false });
    }
  }, []);

  const clear = useCallback(() => {
    inFlight.current?.abort();
    setState({ loading: false });
  }, []);

  return { ...state, run, clear };
}
