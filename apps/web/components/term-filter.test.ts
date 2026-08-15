import type { Listing } from "@better-reverb-search/reverb-api";
import { describe, expect, it } from "vitest";
import { invalidTerms, matchesTerms, NO_TERMS, parseTerms } from "./term-filter";

const listing = (title: string) => ({ title }) as Listing;

describe("term filter", () => {
  it("splits on commas and trims whitespace", () => {
    expect(parseTerms("  strat , tele ,, ").map((r) => r.source)).toEqual(["strat", "tele"]);
  });

  it("drops terms that aren't valid regexes, and reports them", () => {
    expect(parseTerms("strat, (fender").map((r) => r.source)).toEqual(["strat"]);
    expect(invalidTerms("strat, (fender")).toEqual(["(fender"]);
  });

  it("passes everything when both boxes are empty", () => {
    expect(matchesTerms(listing("Fender Stratocaster"), NO_TERMS)).toBe(true);
  });

  it("hides blacklist matches, case-insensitively", () => {
    const terms = { ...NO_TERMS, blacklist: "relic" };
    expect(matchesTerms(listing("Fender Relic Strat"), terms)).toBe(false);
    expect(matchesTerms(listing("Fender Strat"), terms)).toBe(true);
  });

  it("keeps only whitelist matches when the whitelist is non-empty", () => {
    const terms = { ...NO_TERMS, whitelist: "strat(ocaster)?, tele" };
    expect(matchesTerms(listing("1962 Stratocaster"), terms)).toBe(true);
    expect(matchesTerms(listing("Gibson Les Paul"), terms)).toBe(false);
  });

  it("lets the blacklist win over the whitelist", () => {
    expect(matchesTerms(listing("Squier Strat"), { blacklist: "squier", whitelist: "strat" })).toBe(
      false,
    );
  });
});
