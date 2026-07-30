export type Theme = "light" | "dark";

export const THEME_KEY = "brs.theme";

/**
 * Runs before first paint via a blocking inline script in layout.tsx, so the
 * page never flashes the wrong theme. Kept as a string because it has to
 * execute ahead of React hydration — a component can't do this job.
 *
 * Stringified rather than imported so there is exactly one copy of the logic;
 * `resolveTheme` below must stay in sync with it.
 */
export const THEME_INIT_SCRIPT = `
(function () {
  try {
    var stored = localStorage.getItem('${THEME_KEY}');
    var theme = stored === 'light' || stored === 'dark'
      ? stored
      : (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    document.documentElement.dataset.theme = theme;
  } catch (e) {
    document.documentElement.dataset.theme = 'light';
  }
})();
`;

/** Stored preference if set, otherwise the OS setting. */
export function resolveTheme(): Theme {
  try {
    const stored = localStorage.getItem(THEME_KEY);
    if (stored === "light" || stored === "dark") return stored;
  } catch {
    // localStorage can throw in sandboxed contexts; fall through to the OS.
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

export function applyTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(THEME_KEY, theme);
  } catch {
    // Non-persistent is still better than not switching at all.
  }
}
