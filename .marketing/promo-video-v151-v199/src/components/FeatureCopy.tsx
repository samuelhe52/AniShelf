import { Easing, Interactive, interpolate, useCurrentFrame } from "remotion";

type FeatureCopyProps = {
  eyebrow: string;
  title: string;
  body: string;
  bodyMaxWidth?: number;
  accent?: string;
};

export const FeatureCopy: React.FC<FeatureCopyProps> = ({
  eyebrow,
  title,
  body,
  bodyMaxWidth = 500,
  accent = "#6653d9",
}) => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        width: 560,
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
      }}
    >
      <Interactive.Div
        name="Feature label"
        style={{
          padding: "13px 22px",
          borderRadius: 999,
          color: accent,
          background: "rgba(255, 255, 255, 0.68)",
          border: "1px solid rgba(255, 255, 255, 0.9)",
          fontSize: 30,
          fontWeight: 720,
          letterSpacing: 1,
          opacity: interpolate(frame, [0, 18], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          translate: interpolate(frame, [0, 18], ["0px 18px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        {eyebrow}
      </Interactive.Div>
      <Interactive.Div
        name="Feature title"
        style={{
          marginTop: 28,
          color: "#241f33",
          fontSize: 92,
          lineHeight: 1.08,
          fontWeight: 780,
          letterSpacing: -5,
          whiteSpace: "pre-line",
          opacity: interpolate(frame, [6, 26], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          translate: interpolate(frame, [6, 26], ["0px 34px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        {title}
      </Interactive.Div>
      <Interactive.Div
        name="Feature description"
        style={{
          marginTop: 28,
          maxWidth: bodyMaxWidth,
          color: "rgba(36, 31, 51, 0.68)",
          fontSize: 42,
          lineHeight: 1.45,
          fontWeight: 520,
          letterSpacing: -1.5,
          whiteSpace: "pre-line",
          opacity: interpolate(frame, [14, 34], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        {body}
      </Interactive.Div>
    </div>
  );
};
