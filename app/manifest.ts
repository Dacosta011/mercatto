import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Mercatto",
    short_name: "Mercatto",
    description:
      "Football draft, transfer market, auctions & tournament management",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#0D0F14",
    theme_color: "#0D0F14",
    orientation: "portrait",
    categories: ["sports", "games"],
    icons: [
      {
        src: "/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
      },
      {
        src: "/api/pwa-icon?size=192",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/api/pwa-icon?size=512",
        sizes: "512x512",
        type: "image/png",
      },
      {
        src: "/api/pwa-icon?size=512&maskable=1",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
