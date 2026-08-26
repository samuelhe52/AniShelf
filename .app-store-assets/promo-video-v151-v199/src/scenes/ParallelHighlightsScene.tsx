import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { Backdrop } from "../components/Backdrop";
import { FeatureCopy } from "../components/FeatureCopy";
import { ScreenshotCard } from "../components/ScreenshotCard";

const ProgressCluster: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 100, top: 210 }}>
        <FeatureCopy
          eyebrow="评分与按集进度"
          title={"评分 + 进度\n逐集记录"}
          body="评分与观看进度随处可见，每一集也都能单独记录。"
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 700,
          top: 125,
          opacity: interpolate(frame, [0, 24, 172, 187], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: [
              Easing.bezier(0.16, 1, 0.3, 1),
              Easing.linear,
              Easing.bezier(0.7, 0, 0.84, 0),
            ],
          }),
          translate: interpolate(
            frame,
            [0, 80, 172, 187],
            ["80px 24px", "0px 0px", "0px 0px", "-70px -20px"],
            {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: [
                Easing.bezier(0.16, 1, 0.3, 1),
                Easing.linear,
                Easing.bezier(0.7, 0, 0.84, 0),
              ],
            },
          ),
        }}
      >
        <ScreenshotCard
          src="screenshots/library-ratings-and-episode-progress.jpg"
          width={670}
          height={760}
          objectPosition="center top"
        />
      </div>
      <div
        style={{
          position: "absolute",
          right: 90,
          top: 205,
          rotate: "3deg",
          opacity: interpolate(frame, [14, 40, 172, 187], [0, 0.92, 0.92, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          translate: interpolate(frame, [14, 62], ["90px 50px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <ScreenshotCard
          src="screenshots/entry-detail-ratings-and-episode-progress.jpg"
          label="打分、按集记录进度"
          width={430}
          height={720}
          objectPosition="center top"
          accent="#3472d8"
        />
      </div>
    </AbsoluteFill>
  );
};

const SyncCluster: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 100, top: 210 }}>
        <FeatureCopy
          eyebrow="iCloud 同步与多格式导出"
          title={"跨设备同步\n多种格式导出"}
          body={"资料库与设置通过 iCloud\n同步，并可随时备份或导出。"}
          bodyMaxWidth={560}
          accent="#3472d8"
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 700,
          top: 120,
          opacity: interpolate(frame, [0, 24, 172, 187], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          translate: interpolate(frame, [0, 50], ["90px 10px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <ScreenshotCard
          src="screenshots/icloud-sync-backup-and-export.jpg"
          label="iCloud 同步"
          width={650}
          height={780}
          objectPosition="center top"
          accent="#6653d9"
        />
      </div>
      <div
        style={{
          position: "absolute",
          right: 70,
          top: 235,
          rotate: "3deg",
          opacity: interpolate(frame, [18, 44, 172, 187], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          translate: interpolate(frame, [18, 65], ["90px 35px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <ScreenshotCard
          src="screenshots/backup-and-export-formats.jpg"
          label="备份与多格式导出"
          width={570}
          height={620}
          objectPosition="center top"
          accent="#2175c9"
        />
      </div>
      <div
        style={{
          position: "absolute",
          right: 120,
          bottom: 70,
          padding: "22px 30px",
          borderRadius: 28,
          background: "rgba(255, 255, 255, 0.78)",
          boxShadow: "0 24px 70px rgba(58, 64, 110, 0.15)",
          color: "#2c263b",
          fontSize: 32,
          fontWeight: 680,
          letterSpacing: -1,
          opacity: interpolate(frame, [50, 78, 172, 187], [0, 1, 1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      >
        TXT · CSV · TSV · JSON · XLSX
      </div>
    </AbsoluteFill>
  );
};

export const RatingsAndProgressScene: React.FC = () => {
  return (
    <AbsoluteFill>
      <Backdrop />
      <ProgressCluster />
    </AbsoluteFill>
  );
};

export const ICloudSyncScene: React.FC = () => {
  return (
    <AbsoluteFill>
      <Backdrop />
      <SyncCluster />
    </AbsoluteFill>
  );
};
