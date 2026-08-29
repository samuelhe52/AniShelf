import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";

type BackdropProps = {
  warm?: boolean;
};

export const Backdrop: React.FC<BackdropProps> = ({ warm = false }) => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        background: warm
          ? "linear-gradient(135deg, #fff9f2 0%, #fbf3ff 48%, #eef8ff 100%)"
          : "linear-gradient(135deg, #f8f5ff 0%, #f4f8ff 52%, #fff9f2 100%)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          width: 720,
          height: 720,
          borderRadius: 999,
          left: -190,
          top: -250,
          background: warm ? "#ffbd88" : "#b9a7ff",
          filter: "blur(120px)",
          opacity: 0.28,
          translate: interpolate(frame, [0, 240], ["0px 0px", "90px 55px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 680,
          height: 680,
          borderRadius: 999,
          right: -120,
          bottom: -280,
          background: warm ? "#ff9f75" : "#72d6ff",
          filter: "blur(130px)",
          opacity: 0.22,
          translate: interpolate(frame, [0, 240], ["0px 0px", "-110px -70px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "radial-gradient(rgba(86, 75, 120, 0.08) 0.8px, transparent 0.8px)",
          backgroundSize: "24px 24px",
          opacity: 0.32,
        }}
      />
    </AbsoluteFill>
  );
};
