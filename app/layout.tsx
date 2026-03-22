import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";
import "./globals.css";
import PwaRegistration from "./Components/PwaRegistration";

const geist = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#0D0F14",
};

export const metadata: Metadata = {
  title: "Mercatto",
  description: "La ruleta decide. El mercado juzga.",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Mercatto",
  },
  other: {
    "mobile-web-app-capable": "yes",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body className={`${geist.variable} antialiased`}>
        {children}
        <PwaRegistration />
      </body>
    </html>
  );
}
