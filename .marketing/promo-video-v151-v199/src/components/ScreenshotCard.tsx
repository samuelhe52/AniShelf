import { Img, staticFile } from "remotion";

type ScreenshotCardProps = {
  src: string;
  label?: string;
  width: number;
  height: number;
  objectPosition?: string;
  accent?: string;
  labelPosition?: "left" | "right";
};

export const ScreenshotCard: React.FC<ScreenshotCardProps> = ({
  src,
  label,
  width,
  height,
  objectPosition = "center",
  accent = "#6c5ce7",
  labelPosition = "left",
}) => {
  return (
    <div
      style={{
        position: "relative",
        width,
        height,
        borderRadius: 48,
        padding: 10,
        background: "rgba(255, 255, 255, 0.82)",
        border: "1px solid rgba(255, 255, 255, 0.9)",
        boxShadow:
          "0 36px 90px rgba(70, 58, 105, 0.2), 0 8px 24px rgba(70, 58, 105, 0.12)",
        overflow: "hidden",
        boxSizing: "border-box",
      }}
    >
      <Img
        src={staticFile(src)}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition,
          borderRadius: 38,
        }}
      />
      {label ? (
        <div
          style={{
            position: "absolute",
            left: labelPosition === "left" ? 28 : undefined,
            right: labelPosition === "right" ? 28 : undefined,
            bottom: 26,
            padding: "12px 20px",
            borderRadius: 999,
            background: "rgba(255, 255, 255, 0.9)",
            backdropFilter: "blur(20px)",
            color: accent,
            fontSize: 28,
            fontWeight: 720,
            letterSpacing: -0.5,
            boxShadow: "0 8px 24px rgba(45, 38, 67, 0.12)",
          }}
        >
          {label}
        </div>
      ) : null}
    </div>
  );
};
