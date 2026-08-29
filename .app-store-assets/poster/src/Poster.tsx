import { AbsoluteFill, Img, staticFile } from "remotion";
import { Backdrop } from "./components/Backdrop";
import { ScreenshotCard } from "./components/ScreenshotCard";

export const Poster: React.FC = () => {
  return (
    <AbsoluteFill>
      <Backdrop />

      <div
        style={{
          position: "absolute",
          left: 90,
          right: 90,
          top: 58,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 20,
        }}
      >
        <Img
          src={staticFile("brand/app-icon.png")}
          style={{
            width: 78,
            height: 78,
            borderRadius: 22,
            boxShadow: "0 16px 42px rgba(73, 57, 115, 0.22)",
          }}
        />
        <div
          style={{
            color: "#2c263b",
            fontSize: 60,
            fontWeight: 780,
            letterSpacing: -3,
          }}
        >
          AniShelf
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          left: 90,
          right: 90,
          top: 162,
          textAlign: "center",
          color: "#241f33",
          fontSize: 88,
          fontWeight: 780,
          letterSpacing: -5,
        }}
      >
        收藏、追踪、整理动画
      </div>

      <div
        style={{
          position: "absolute",
          left: 150,
          right: 150,
          top: 315,
          height: 765,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: 20,
            top: 62,
            rotate: "-5deg",
          }}
        >
          <ScreenshotCard
            src="screenshots/library-list-view.jpeg"
            label="浏览与收藏"
            width={540}
            height={650}
            objectPosition="center top"
            accent="#6653d9"
          />
        </div>

        <div
          style={{
            position: "absolute",
            left: 560,
            top: 0,
            zIndex: 3,
          }}
        >
          <ScreenshotCard
            src="screenshots/anime-detail-overview.jpeg"
            label="详情与进度"
            width={500}
            height={740}
            objectPosition="center 20%"
            accent="#d86f30"
          />
        </div>

        <div
          style={{
            position: "absolute",
            right: 20,
            top: 62,
            rotate: "5deg",
          }}
        >
          <ScreenshotCard
            src="screenshots/library-stats-overview.jpeg"
            label="资料库统计"
            width={510}
            height={650}
            objectPosition="center top"
            accent="#2f8f7e"
            labelPosition="right"
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};
