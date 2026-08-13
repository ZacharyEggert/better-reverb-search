import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { THEME_INIT_SCRIPT } from "@/lib/theme";
import "./globals.css";

// --rc-font-family-inter — Cadence's page and heading family.
// next/font self-hosts it, so there's no external request at runtime.
const inter = Inter({ subsets: ["latin"], display: "swap" });

export const metadata: Metadata = {
  title: "Better Reverb Search",
  description: "Search Reverb listings and sold comps with real price stats.",
  // ponytail: placeholder mark — swap the SVG and re-run rsvg-convert for the PNG.
  icons: { icon: ["/favicon.svg", "/favicon.png"], apple: "/favicon.png" },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    // suppressHydrationWarning: the inline script sets data-theme on <html>
    // before React hydrates, so the server markup intentionally differs.
    <html lang="en" className={inter.className} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      </head>
      <body className="min-h-screen antialiased">
        {children}
        {/* Nominative use of the Reverb mark — say plainly whose app this isn't. */}
        <footer className="px-6 pb-8 text-center text-xs text-[var(--color-muted)]">
          Created by Ex Nihilo LLC. Not affiliated with Reverb.com LLC.
        </footer>
      </body>
    </html>
  );
}
