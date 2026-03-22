import { ImageResponse } from "next/og";
import { type NextRequest } from "next/server";

export async function GET(request: NextRequest) {
  const s = Math.min(1024, Math.max(16, parseInt(request.nextUrl.searchParams.get("size") || "192")));
  const maskable = request.nextUrl.searchParams.get("maskable") === "1";

  const padding = maskable ? Math.round(s * 0.1) : 0;
  const fontSize = Math.round((s - padding * 2) * 0.6);
  const radius = maskable ? Math.round(s * 0.22) : Math.round(s * 0.16);

  return new ImageResponse(
    (
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: "100%",
          height: "100%",
          background: "#0D0F14",
          borderRadius: `${radius}px`,
          padding: `${padding}px`,
        }}
      >
        <span
          style={{
            color: "#8B5CF6",
            fontSize: `${fontSize}px`,
            fontWeight: 900,
          }}
        >
          M
        </span>
      </div>
    ),
    {
      width: s,
      height: s,
      headers: { "Cache-Control": "public, max-age=31536000, immutable" },
    },
  );
}
