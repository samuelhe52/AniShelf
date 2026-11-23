import {
  AbsoluteFill,
  Easing,
  Interactive,
  interpolate,
  useCurrentFrame,
} from "remotion";
import { Backdrop } from "../components/Backdrop";

const updates = [
  { text: "适配 iPad，窗口可调整大小", color: "#6653d9" },
  { text: "更强大的分享功能", color: "#3472d8" },
  { text: "批量添加动画", color: "#d86f30" },
  { text: "更灵活的筛选与分组", color: "#2f8a77" },
  { text: "更丰富的演职员与制作公司信息", color: "#a54d8f" },
  { text: "内置更新日志", color: "#7a5dd8" },
  { text: "深色模式 App 图标", color: "#4d566a" },
  { text: "多选动画并批量操作", color: "#a46a2e" },
];

export const MoreUpdatesScene: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill>
      <Backdrop />
      <Interactive.Div
        name="More updates title"
        style={{
          position: "absolute",
          left: 100,
          top: 105,
          color: "#241f33",
          fontSize: 92,
          fontWeight: 780,
          letterSpacing: -5,
          opacity: interpolate(frame, [0, 24], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        还有更多更新
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          left: 100,
          right: 100,
          top: 300,
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 28,
        }}
      >
        {updates.map((update, index) => (
          <div
            key={update.text}
            style={{
              minHeight: 150,
              display: "flex",
              alignItems: "center",
              padding: "0 42px",
              borderRadius: 38,
              background: "rgba(255, 255, 255, 0.7)",
              border: "1px solid rgba(255, 255, 255, 0.94)",
              boxShadow: "0 18px 55px rgba(64, 53, 93, 0.11)",
              color: update.color,
              fontSize: index === 4 ? 41 : 45,
              fontWeight: 700,
              letterSpacing: -1.8,
              opacity: interpolate(frame, [18 + index * 10, 42 + index * 10], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [18 + index * 10, 42 + index * 10],
                [index % 2 === 0 ? "-45px 20px" : "45px 20px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
            }}
          >
            <span
              style={{
                width: 14,
                height: 14,
                marginRight: 22,
                borderRadius: 999,
                background: update.color,
                boxShadow: `0 0 0 10px ${update.color}18`,
              }}
            />
            {update.text}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
