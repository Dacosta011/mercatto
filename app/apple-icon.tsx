import { ImageResponse } from "next/og";
import { MERCATTO_LOGO_DATA_URI } from "@/lib/logo";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
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
          borderRadius: "38px",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={MERCATTO_LOGO_DATA_URI} alt="" width={120} height={100} />
      </div>
    ),
    { ...size },
  );
}
