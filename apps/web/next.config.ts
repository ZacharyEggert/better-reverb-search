import type { NextConfig } from "next";

const config: NextConfig = {
  images: {
    // Reverb serves listing photos from its own CDN.
    remotePatterns: [{ protocol: "https", hostname: "**.reverb.com" }],
  },
};

export default config;
