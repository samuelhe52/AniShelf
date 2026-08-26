import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { Backdrop } from "../components/Backdrop";
import { FeatureCopy } from "../components/FeatureCopy";
import { ScreenshotCard } from "../components/ScreenshotCard";

export const ReminderScene: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill>
      <Backdrop warm />
      <AbsoluteFill
        style={{
          opacity: interpolate(frame, [159, 174], [1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.7, 0, 0.84, 0),
          }),
        }}
      >
        <div style={{ position: "absolute", left: 100, top: 214 }}>
          <FeatureCopy
            eyebrow="下一集通知"
            title={"下一集播出前\n及时收到通知"}
            body="在下一集播出前收到通知，并集中管理所有订阅。"
            accent="#d86f30"
          />
        </div>
        <div
          style={{
            position: "absolute",
            left: 800,
            top: 135,
            rotate: "-3deg",
            opacity: interpolate(frame, [0, 26], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            translate: interpolate(frame, [0, 38], ["70px 70px", "0px 0px"], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
          }}
        >
          <ScreenshotCard
            src="screenshots/next-episode-notification-enabled.jpg"
            label="订阅通知"
            width={480}
            height={735}
            objectPosition="center top"
            accent="#d86f30"
          />
        </div>
        <div
          style={{
            position: "absolute",
            left: 1180,
            top: 155,
            zIndex: 3,
            opacity: interpolate(frame, [12, 40], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            translate: interpolate(frame, [12, 48], ["80px 60px", "0px 0px"], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
          }}
        >
          <ScreenshotCard
            src="screenshots/next-episode-notification-management.jpg"
            label="集中管理"
            width={520}
            height={760}
            objectPosition="center top"
            accent="#d86f30"
          />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
