import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { EndScene } from "./scenes/EndScene";
import { IntroScene } from "./scenes/IntroScene";
import { MoreUpdatesScene } from "./scenes/MoreUpdatesScene";
import {
  ICloudSyncScene,
  RatingsAndProgressScene,
} from "./scenes/ParallelHighlightsScene";
import { ReminderScene } from "./scenes/ReminderScene";

export const PromoVideo: React.FC = () => {
  return (
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={120} name="Intro">
        <IntroScene />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 15 })}
      />
      <TransitionSeries.Sequence durationInFrames={202} name="iCloud sync">
        <ICloudSyncScene />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 15 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={189}
        name="Next episode notifications"
      >
        <ReminderScene />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 15 })}
      />
      <TransitionSeries.Sequence
        durationInFrames={202}
        name="Ratings and episode progress"
      >
        <RatingsAndProgressScene />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 15 })}
      />
      <TransitionSeries.Sequence durationInFrames={180} name="More updates">
        <MoreUpdatesScene />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({ durationInFrames: 15 })}
      />
      <TransitionSeries.Sequence durationInFrames={90} name="End card">
        <EndScene />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  );
};
