import { ImageResponse } from "next/og";
import { MERCATTO_LOGO_DATA_URI } from "@/lib/logo";

export const size = { width: 32, height: 32 };
export const contentType = "image/png";

export default function Icon() {
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
          borderRadius: "6px",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={MERCATTO_LOGO_DATA_URI} alt="" width={24} height={20} />
      </div>
    ),
    { ...size },
  );
}
