"use client";

import { useEffect, useState } from "react";
import { applyTheme, resolveTheme, type Theme } from "@/lib/theme";

export function ThemeToggle() {
  // The real theme is already on <html> from the inline script; this is only
  // mirroring it so the button can render the right label. Starts undefined so
  // SSR and first client render agree — no hydration mismatch.
  const [theme, setTheme] = useState<Theme>();

  useEffect(() => {
    setTheme(resolveTheme());
  }, []);

  const next = theme === "dark" ? "light" : "dark";

  return (
    <button
      type="button"
      onClick={() => {
        applyTheme(next);
        setTheme(next);
      }}
      aria-label={`Switch to ${next} theme`}
      title={`Switch to ${next} theme`}
      className="flex h-9 w-9 items-center justify-center rounded-full border border-[var(--color-line)] text-[var(--color-muted)] hover:bg-[var(--color-card)] hover:text-[var(--color-ink)]"
    >
      {/* Render nothing until the effect resolves, so the icon can't contradict
          the theme the inline script already applied. */}
      <span aria-hidden className="text-base leading-none">
        {theme === undefined ? "" : theme === "dark" ? "☀" : "☾"}
      </span>
    </button>
  );
}
