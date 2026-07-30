import { describe, expect, it } from "vitest";
import {
  checkSafeString,
  validateResourceName,
  validateSafeOutputPath,
} from "./validate.js";

// Ported from the `#[cfg(test)] mod tests` block in reverb-api/src/validate.rs.
describe("validate", () => {
  it("rejects control chars", () => {
    expect(() => checkSafeString("hello\x00world")).toThrow();
  });

  it("rejects traversal in resource", () => {
    expect(() => validateResourceName("../../etc/passwd")).toThrow();
  });

  it("accepts valid resource", () => {
    expect(validateResourceName("12345678")).toBe("12345678");
    expect(validateResourceName("my-shop-slug")).toBe("my-shop-slug");
  });

  it("rejects absolute output path", () => {
    expect(() => validateSafeOutputPath("/etc/hosts")).toThrow();
    expect(() => validateSafeOutputPath("C:\\Windows\\hosts")).toThrow();
  });

  it("rejects bidi and zero-width characters", () => {
    expect(() => checkSafeString("ab\u202Ecd")).toThrow(/bidirectional/);
    expect(() => checkSafeString("ab\uFEFFcd")).toThrow(/zero-width/);
  });
});
