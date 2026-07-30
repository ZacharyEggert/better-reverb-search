import { RevError } from "./error.js";

/**
 * Reject strings containing dangerous Unicode or control characters.
 * Call this on any untrusted input before processing.
 *
 * Port of `reverb-api/src/validate.rs`.
 */
export function checkSafeString(s: string): void {
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    // Control characters
    if (cp < 0x20 || (cp >= 0x7f && cp <= 0x9f)) {
      throw RevError.validation(`input contains control character ${fmtCp(cp)}`);
    }
    // Bidirectional overrides
    if (
      (cp >= 0x202a && cp <= 0x202e) ||
      (cp >= 0x2066 && cp <= 0x2069) ||
      cp === 0x200f ||
      cp === 0x200e
    ) {
      throw RevError.validation(
        `input contains bidirectional override character ${fmtCp(cp)}`,
      );
    }
    // Zero-width characters
    if (cp === 0x200b || cp === 0xfeff) {
      throw RevError.validation(
        `input contains zero-width character ${fmtCp(cp)}`,
      );
    }
  }
}

/**
 * Validate a resource identifier (listing ID, shop slug, etc.) for safe URL embedding.
 * Rejects path traversal sequences and URL-breaking characters.
 */
export function validateResourceName(s: string): string {
  checkSafeString(s);
  if (s.includes("..")) {
    throw RevError.validation("resource name contains path traversal sequence");
  }
  for (const ch of ["?", "#", "/", "\\"]) {
    if (s.includes(ch)) {
      throw RevError.validation(
        `resource name contains invalid character '${ch}'`,
      );
    }
  }
  return s;
}

/** Validate a relative file path for safe output (no traversal, no absolute paths). */
export function validateSafeOutputPath(path: string): void {
  checkSafeString(path);
  // Absolute on POSIX (`/x`), Windows drive (`C:\x`), or UNC (`\\host`).
  if (/^([/\\]|[A-Za-z]:[/\\])/.test(path)) {
    throw RevError.validation("output path must be relative");
  }
  if (path.includes("..")) {
    throw RevError.validation("output path contains path traversal sequence");
  }
}

function fmtCp(cp: number): string {
  return `U+${cp.toString(16).toUpperCase().padStart(4, "0")}`;
}
