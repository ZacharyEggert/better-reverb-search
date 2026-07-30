"use client";

import {
  RevError,
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

  const run = useCallback(async (query: SearchQuery) => {
    inFlight.current?.abort();
    const controller = new AbortController();
    inFlight.current = controller;

    setState((s) => ({ ...s, loading: true, error: undefined }));
    try {
      const result = await searchListings(query, { signal: controller.signal });
      if (controller.signal.aborted) return;
      setState({ result, loading: false });
    } catch (e) {
      if (controller.signal.aborted) return;
      // RevError already carries a human-readable message and a type.
      const message =
        e instanceof RevError ? e.message : `Unexpected error: ${String(e)}`;
      setState({ error: message, loading: false });
    }
  }, []);

  return { ...state, run };
}
