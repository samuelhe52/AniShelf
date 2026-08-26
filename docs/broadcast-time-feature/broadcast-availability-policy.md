# Broadcast Availability Policy

| Provider data | Availability | Display behavior | Recurring notifications |
|---|---|---|---|
| TMDb says the entry is not currently or future airing | Ineligible | Do not call TVMaze or display airtime. | Not allowed. |
| TVMaze supplies a valid next-episode `airstamp`; its provider-local date agrees with TMDb | TVMaze next airing, consistent | Display the TVMaze `airstamp`. | Subject to notification rules defined during implementation. |
| TVMaze supplies a valid `airstamp`; TMDb has no comparable next-episode date | TVMaze next airing, not comparable | Display the TVMaze `airstamp`. | Subject to notification rules defined during implementation. |
| TVMaze supplies a valid `airstamp`; its provider-local date disagrees with TMDb | TVMaze next airing, potentially unreliable | Display the TVMaze `airstamp` and mark it potentially unreliable. | Subject to notification rules defined during implementation. |
| TVMaze and TMDb season or episode numbers disagree | No availability change | Ignore the numbering discrepancy. | No effect by itself. |
| TVMaze lacks an embedded next episode or valid `airstamp`; TMDb has a usable future date | TMDb expected airing | Display the TMDb date and mark it “Expected.” Ignore the TVMaze recurring schedule. | Not allowed. |
| Neither provider supplies a usable next-airing date | Unavailable | Do not display a next airtime. | Not allowed. |
| TVMaze uses the preceding broadcast day for an after-midnight airing | Normalized TVMaze next airing | Use the absolute `airstamp`; this is not a provider disagreement. | No effect by itself. |
