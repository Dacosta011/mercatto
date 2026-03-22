import { ImageResponse } from "next/og";

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
        <span
          style={{
            color: "#8B5CF6",
            fontSize: "22px",
            fontWeight: 900,
          }}
        >
          M
        </span>
      </div>
    ),
    { ...size },
  );
}
