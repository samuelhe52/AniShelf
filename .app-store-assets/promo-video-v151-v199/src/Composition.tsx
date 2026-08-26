import { Composition, Folder } from "remotion";
import { PromoVideo } from "./PromoVideo";
import { EndScene } from "./scenes/EndScene";
import { IntroScene } from "./scenes/IntroScene";
import { MoreUpdatesScene } from "./scenes/MoreUpdatesScene";
import {
  ICloudSyncScene,
  RatingsAndProgressScene,
} from "./scenes/ParallelHighlightsScene";
import { ReminderScene } from "./scenes/ReminderScene";

export const MyComposition: React.FC = () => {
  return (
    <>
      <Folder name="AniShelf-Promo-Scenes">
        <Composition
          id="01-Intro"
          component={IntroScene}
          durationInFrames={120}
          fps={30}
          width={1920}
          height={1080}
        />
        <Composition
          id="02-iCloud-Sync"
          component={ICloudSyncScene}
          durationInFrames={202}
          fps={30}
          width={1920}
          height={1080}
        />
        <Composition
          id="03-Next-Episode-Notifications"
          component={ReminderScene}
          durationInFrames={189}
          fps={30}
          width={1920}
          height={1080}
        />
        <Composition
          id="04-Ratings-And-Episode-Progress"
          component={RatingsAndProgressScene}
          durationInFrames={202}
          fps={30}
          width={1920}
          height={1080}
        />
        <Composition
          id="05-More-Updates"
          component={MoreUpdatesScene}
          durationInFrames={180}
          fps={30}
          width={1920}
          height={1080}
        />
        <Composition
          id="06-End-Card"
          component={EndScene}
          durationInFrames={90}
          fps={30}
          width={1920}
          height={1080}
        />
      </Folder>
      <Composition
        id="AniShelf-Promo-ZH"
        component={PromoVideo}
        durationInFrames={908}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
