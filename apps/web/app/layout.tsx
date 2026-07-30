import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Better Reverb Search",
  description: "Search Reverb listings and sold comps with real price stats.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
