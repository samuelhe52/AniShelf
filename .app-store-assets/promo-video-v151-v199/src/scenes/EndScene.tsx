import {
  AbsoluteFill,
  Easing,
  Img,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { Backdrop } from "../components/Backdrop";

export const EndScene: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Backdrop />
      <Img
        src={staticFile("brand/app-icon.png")}
        style={{
          position: "absolute",
          top: 276,
          width: 180,
          height: 180,
          borderRadius: 48,
          boxShadow: "0 24px 70px rgba(73, 57, 115, 0.25)",
          opacity: interpolate(frame, [0, 20], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          scale: interpolate(frame, [0, 30], [0.72, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.spring({ damping: 160 }),
            output: "perceptual-scale",
          }),
        }}
      />
      <Interactive.Div
        name="End card app name"
        style={{
          position: "absolute",
          top: 520,
          color: "#241f33",
          fontSize: 118,
          lineHeight: 1,
          fontWeight: 800,
          letterSpacing: -6,
          opacity: interpolate(frame, [12, 34], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          translate: interpolate(frame, [12, 34], ["0px 24px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        AniShelf
      </Interactive.Div>
      <Interactive.Div
        name="End card tagline"
        style={{
          position: "absolute",
          top: 686,
          color: "rgba(36, 31, 51, 0.64)",
          fontSize: 46,
          fontWeight: 560,
          letterSpacing: -1.8,
          opacity: interpolate(frame, [22, 44], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        追踪，收藏，整理动画
      </Interactive.Div>
    </AbsoluteFill>
  );
};
