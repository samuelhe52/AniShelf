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
import { ScreenshotCard } from "../components/ScreenshotCard";

export const IntroScene: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill
        style={{
          opacity: interpolate(frame, [90, 105], [1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.7, 0, 0.84, 0),
          }),
        }}
      >
        <div
          style={{
            position: "absolute",
            left: 90,
            right: 90,
            top: 78,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 24,
            zIndex: 10,
          }}
        >
          <Img
            src={staticFile("brand/app-icon.png")}
            style={{
              width: 88,
              height: 88,
              borderRadius: 24,
              boxShadow: "0 16px 42px rgba(73, 57, 115, 0.22)",
              scale: interpolate(frame, [0, 22], [0.78, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.spring({ damping: 180 }),
                output: "perceptual-scale",
              }),
            }}
          />
          <Interactive.Div
            name="App name"
            style={{
              color: "#2c263b",
              fontSize: 68,
              fontWeight: 780,
              letterSpacing: -3,
              opacity: interpolate(frame, [5, 24], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
            }}
          >
            AniShelf
          </Interactive.Div>
        </div>
        <Interactive.Div
          name="Intro headline"
          style={{
            position: "absolute",
            left: 90,
            right: 90,
            top: 188,
            textAlign: "center",
            color: "#241f33",
            fontSize: 94,
            fontWeight: 780,
            letterSpacing: -5,
            opacity: interpolate(frame, [10, 34], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            translate: interpolate(frame, [10, 34], ["0px 28px", "0px 0px"], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
          }}
        >
          从收藏到追番，一切都更顺手
        </Interactive.Div>
        <div
          style={{
            position: "absolute",
            left: 220,
            right: 220,
            top: 350,
            height: 710,
          }}
        >
          <div
            style={{
              position: "absolute",
              left: 60,
              top: 68,
              rotate: "-5deg",
              opacity: interpolate(frame, [24, 48], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [24, 48],
                ["-90px 80px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
            }}
          >
            <ScreenshotCard
              src="screenshots/icloud-sync-backup-and-export.jpg"
              label="iCloud 同步"
              width={540}
              height={650}
              objectPosition="center top"
              accent="#6653d9"
            />
          </div>
          <div
            style={{
              position: "absolute",
              left: 570,
              top: 0,
              zIndex: 3,
              opacity: interpolate(frame, [30, 54], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [30, 54],
                ["0px 100px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
            }}
          >
            <ScreenshotCard
              src="screenshots/next-episode-notification-management.jpg"
              label="下一集通知"
              width={520}
              height={680}
              objectPosition="center top"
              accent="#d86f30"
            />
          </div>
          <div
            style={{
              position: "absolute",
              right: 0,
              top: 68,
              rotate: "5deg",
              opacity: interpolate(frame, [36, 60], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [36, 60],
                ["90px 80px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
            }}
          >
            <ScreenshotCard
              src="screenshots/entry-detail-ratings-and-episode-progress.jpg"
              label="评分 + 按集进度"
              width={410}
              height={620}
              objectPosition="center top"
              accent="#316cd6"
              labelPosition="right"
            />
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
