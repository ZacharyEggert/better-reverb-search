"use client";

import type { Listing } from "@better-reverb-search/reverb-api";
import { Drawer } from "./drawer";

/** Comma-separated terms typed into either box. */
export interface Terms {
  /** Titles matching any of these are dropped. */
  blacklist: string;
  /** Titles matching none of these are dropped. Empty means "no restriction". */
  whitelist: string;
}

export const NO_TERMS: Terms = { blacklist: "", whitelist: "" };

/**
 * Split on commas, trim, drop blanks. Each term is a case-insensitive regex;
 * one that doesn't compile is dropped rather than thrown — the user is typing,
 * and a half-written `(fender` shouldn't blank the results.
 */
export function parseTerms(input: string): RegExp[] {
  return input
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .flatMap((t) => {
      try {
        return [new RegExp(t, "i")];
      } catch {
        return [];
      }
    });
}

/** Terms that were typed but don't compile — surfaced so a typo isn't silent. */
export function invalidTerms(input: string): string[] {
  return input
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .filter((t) => {
      try {
        new RegExp(t, "i");
        return false;
      } catch {
        return true;
      }
    });
}

/** Blacklist wins over whitelist: an explicitly excluded title stays excluded. */
export function matchesTerms(listing: Listing, terms: Terms): boolean {
  const title = listing.title ?? "";
  const black = parseTerms(terms.blacklist);
  const white = parseTerms(terms.whitelist);
  if (black.some((re) => re.test(title))) return false;
  return white.length === 0 || white.some((re) => re.test(title));
}

export function TermFilter({
  terms,
  onChange,
  hidden,
}: {
  terms: Terms;
  onChange: (terms: Terms) => void;
  /** How many loaded listings these terms are currently removing. */
  hidden: number;
}) {
  const bad = [...invalidTerms(terms.blacklist), ...invalidTerms(terms.whitelist)];

  return (
    <Drawer
      label="Blacklist / Whitelist"
      summary={hidden > 0 ? `${hidden.toLocaleString()} hidden` : "off"}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Box
          label="Blacklist — hide titles matching"
          value={terms.blacklist}
          placeholder="relic, mini, copy"
          onChange={(blacklist) => onChange({ ...terms, blacklist })}
        />
        <Box
          label="Whitelist — keep only titles matching"
          value={terms.whitelist}
          placeholder="strat(ocaster)?, tele"
          onChange={(whitelist) => onChange({ ...terms, whitelist })}
        />
      </div>
      <p className="text-xs text-[var(--color-muted)]">
        Comma-separated, matched against the listing title as case-insensitive regexes.
      </p>
      {bad.length > 0 && (
        <p className="text-xs text-[var(--color-sale)]">
          Ignored (invalid regex): {bad.join(", ")}
        </p>
      )}
    </Drawer>
  );
}

function Box({
  label,
  value,
  placeholder,
  onChange,
}: {
  label: string;
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="block text-xs text-[var(--color-muted)]">
      {label}
      <textarea
        rows={2}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-[var(--radius-module)] border border-[var(--color-line-input)] bg-[var(--color-input-bg)] p-2 text-sm text-[var(--color-ink)]"
      />
    </label>
  );
}
