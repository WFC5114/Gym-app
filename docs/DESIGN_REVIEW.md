# Design review: Revision 2 art direction against the code

How the team applied `docs/ART_DIRECTION.md` (Revision 2) and Wei's decisions of 12 October 2026. Section numbers (§) refer to that file.

Status words follow §17: **PASS** (checked, with evidence), **FAIL** (checked, does not meet the gate), **NOT TESTED** (not yet checked, or cannot be checked without the phone). Nothing in this file is PASS until the evidence column links to a CI run, a capture or a device measurement.

## 1. Comparison: the existing UI against the direction (§11)

Reviewed at commit `56a316c` on `m0-foundation`, before branch `2-deck-slice`.

### Contradictions (the code or docs do the opposite of the direction)

| # | Where | What it does | What the direction says | Resolution in `2-deck-slice` |
|---|---|---|---|---|
| C1 | `App/DashboardView.swift` | A `ScrollView` of stacked cards (kcal, protein, body, buttons) | §2: a render above an ordinary dashboard fails; §11: a monochrome dashboard with large text is not success; §3: no pushed screens | Deleted. The app root is `App/Machine/MachineView.swift`: one prism with three faces |
| C2 | `Shared/Brutal.swift` `BrutalCard` | 3 pt outline plus a solid 6 pt offset "shadow" block | §4: no fake dashboard drop shadows; §14: no decorative card outlines | Removed (it was only used by the dashboard) |
| C3 | `Shared/Brutal.swift` `Brutal.display` | System font at `.black`, `.expanded` | §4: choose a heavy geometric display face by the shapes of 0 1 4 7 8; show the font and fallback; check the licence | `App/Fonts/Unbounded-Black.ttf` (SIL OFL 1.1, `App/Fonts/OFL.txt`) via `TypeKit.display` in `App/Machine/Typography.swift`; SF Black Expanded is the fallback. Widgets still use `Brutal.display` (see M8) |
| C4 | `docs/DESIGN_LANGUAGE.md` §2 Face A | "The Deck drops on the Z-axis" | §5: with a front orthographic camera, Z travel does not read as a drop | Proposal P2: compression is in the face plane (see section 2) |
| C5 | `docs/DESIGN_LANGUAGE.md` §2 Face B | Rest is fluid draining from the chamber | Wei, 12 Oct: rest is an hourglass that flips after each set | Hourglass in `App/Machine/MachineScene.swift` `buildHourglass` and `MachineModel.setDone` |
| C6 | `docs/DESIGN_LANGUAGE.md` §2 Face A | "Nutrition is a balance-scale machine, not logs or forms" | Wei, 12 Oct: real food logging; §5 proposal: intake inset with search, barcode, serving | Proposal P1: intake inset inside DIET (`App/Machine/InsetLayer.swift`) |
| C7 | `docs/DESIGN_LANGUAGE.md` §2 Face A | Macro tag "40% PROTEIN" | §5: say whether a percentage is completion or energy share; show exact grams | DIET hero prints `PROTEIN 118 / 180 G` etc. (`App/Machine/DietFace.swift` `DietHero`) |
| C8 | `docs/DESIGN_LANGUAGE.md` §7 | "Locked 120 Hz" | §9: target up to 120 fps; do not promise a lock | Doc reworded. Display link prefers 120 Hz while moving, drops to 30 Hz when only sand moves, pauses when idle (`MachineModel.tick`) |
| C9 | `docs/DESIGN_LANGUAGE.md` §7 | "Text, indicators and buttons are 3D entities" | §9: a native input inset that conflicts with all-geometry must be raised as a proposal | Proposal P6 |
| C10 | `Widgets/RestTimerLiveActivity.swift` | White (ink) background with grey text; SF Symbol `timer` in the minimal island; system `ProgressView` | Project rules: widgets and island are text on black; the island is a flat gauge | **Not changed yet.** Widgets come after the DIET gate (M8) |

### Missing implementation (the direction asks for it and nothing existed)

| # | Missing at `56a316c` | Now in `2-deck-slice` |
|---|---|---|
| M1 | Any 3D scene, prism or orthographic camera | `App/Machine/MachineScene.swift`, `Geometry.swift`, `Materials.swift` |
| M2 | Food logging of any kind | `App/Domain/Nutrition.swift`, `LogStore.swift`, `App/Food/BuiltInFoods.swift`, `App/Food/OpenFoodFacts.swift`, `App/Platform/BarcodeScanner.swift` |
| M3 | Drag, drop and contact physics for the kcal blocks | `MachineModel` (`grabQuick`, `dragBlock`, `releaseBlock`, `stepDiet`, `land`) |
| M4 | Rest log, rest additions, rest that survives relaunch | `App/Domain/Training.swift` (`RestPeriod`, `RestAddition`), `LogStore.completeSet/addRestTime/settleElapsedRests` |
| M5 | Coach rest advice per body part | `App/Domain/RestCoach.swift` |
| M6 | Synthesised sound | `App/Platform/SoundEngine.swift` (AVAudioEngine source node, `.ambient` session) |
| M7 | Fixture states, render captures, gesture video | `App/Machine/Fixtures.swift`, `UITests/`, `scripts/capture.sh` |
| M8 | Typographic widgets with a light-to-heavy strike; flat island gauge | **Still missing.** Deferred until Wei passes the DIET gate |
| M9 | Heart-rate influence on TRAIN; cardio on TRAIN | **Still missing.** Deferred (§6 asks for it; Wei's hourglass decision changes the visual it would act on) |
| M10 | BODY low-poly mesh and vernier ruler | First pass: `Geometry.body(fatPercent:leanKg:)`, `App/Machine/BodyFace.swift`. Labelled `SCHEMATIC · NOT A BODY SCAN` |

## 2. Proposals adopted (with why)

| # | Proposal | Why | Where |
|---|---|---|---|
| P1 | **Food intake inset inside DIET.** A labelled LOG FOOD control opens a recessed panel in the face: search (recent, built-in, Open Food Facts), barcode (camera, or typed digits), serving (grams, serving chips), FORM BLOCK. The confirmed food becomes a block on the rail that is dragged onto the deck like the kcal weights. The ledger inset lists today with ± grams, delete and undo. An obvious close button on every inset. | Wei's decision 5 adopts §5's proposal. Not behind a long press (§3). | `InsetLayer.swift`, `DietFace.swift`, `MachineModel.formBlock/loadPending` |
| P2 | **In-plane compression.** World axes: X right, Y up, Z toward the camera. The deck compresses along face-local −Y (down the screen); the springs shorten; the slab stack stands on the plate. Depth (Z) is only used for thickness and stacking order, so it shows during rotation. | §5: Z travel is invisible head-on with an orthographic camera. Replaces the "drops on Z" wording (C4). | `Mechanics.swift` `DeckGeometry`, `MachineScene.applyDiet` |
| P3 | **"No highlights" means no glossy specular highlights**, not no shading. MONO graphite stays roughness 0.9, metalness 0. One broad soft key light from upper left, a dim fill, contact shadows, small chamfers and a seeded grain normal map model the planes. | §4 flags the ambiguity. | `Materials.swift`, `MachineScene.make` |
| P4 | **Hero starts at 40% of screen width** for the reference string "8,888", fitted to each real value (0, 850, 1,850, −150) without distortion or cropping. A larger hero is not proposed until comparison frames exist. `-heroFraction 0.62` renders the comparison. | §4 | `TypeKit.heroSize`, `MachineModel.heroFraction`, `Fixtures.fixture` |
| P5 | **In-face accessible layout.** At accessibility text sizes or with the keyboard up, insets scroll internally inside the same face; the mechanism yields. No new top-level screen. | §14 asks for this exception to be flagged. | `InsetLayer.swift` |
| P6 | **Native SwiftUI type and controls over RealityKit geometry.** Text and buttons are SwiftUI views placed in face-local coordinates and projected with the same orthographic maths as the geometry (x offset `apothem·sin φ`, x scale `cos φ`), so they turn with the prism. This keeps VoiceOver, Dynamic Type, keyboard input and system text rendering. | §9: native input that conflicts with the all-geometry wording must be raised as a proposal (C9). | `MachineView.swift` `FaceLayer`, `MachineLayout.screenX` |
| P7 | **Rotation throws are bounded.** Swipe velocity is clamped to ±900°/s and one swipe turns at most one face. A swipe commits past 18° or 250°/s. Zero-velocity overshoot is 9.6° (prism spring 1 / 300 / 21.7, damping ratio 0.626). | §3 asks for documented bounds. | `MachineModel.endRotate`, `Shared/Spring.swift` |
| P8 | **Hourglass replaces the draining fluid** (Wei). SET DONE logs the set and flips the glass with the piston spring 1 / 800 / 35; the rack sound, the max transient and the camera shake fire when the glass first seats, not at peak overshoot. Glass height follows the rest length (30 s smallest, 6 min largest, square-root mapping). Sand is drawn from elapsed wall-clock time; the printed clock is exact. | Wei's decisions 1 and 2; §6 elapsed time is the source of truth. | `MachineModel.setDone/stepTrain`, `HourglassGeometry` |
| P9 | **Every rest is a record.** Planned length, coach recommendation, each mid-rest addition with its time, end reason (elapsed, next set, ended early) and actual rest until the next set. The coach reads the last 14 days. | Wei's decision 3. | `RestPeriod`, `RestCoach.recommend`, `RestDigest` |
| P10 | **Coach rest per body part, adapted daily.** Baselines by body part and compound or isolation (legs compound 3:00, back and chest compound 2:30, arms 1:15, core 1:00). Adjusted by: rests Wei extended or cut short on that body part, today's HRV and resting heart rate against baseline, last night's sleep, heavy leg sets from set 3. Missing Health data is stated ("NO HRV READING TODAY"), never guessed. | Wei's decision 4. Deterministic so it can be tested; the Claude API review can build on `RestDigest` later. | `RestCoach.swift`, `HealthStore.readiness` |
| P11 | **Quick-add records unknown macros.** A 250 kcal weight logs 250 kcal and protein/carbs/fat as unknown; the hero says how many entries have unknown macros. Its slab uses a lighter material so it reads differently from a logged food. | §5 | `FoodEntry.quickAdd`, `DayTotals.entriesWithUnknownMacros`, `MaterialKit.unknownWeight` |

### Not adopted yet

- **Macro-to-depth mapping (§5).** Head-on, depth is invisible with an orthographic camera, so mapping protein to slab depth would only show mid-rotation. Exact grams are printed instead. Revisit with the rotation captures.
- **Third-party packages (§10).** None added. The spring solver is our own (`Shared/Spring.swift`).
- **USDA FoodData Central API.** It needs an api.data.gov key. Whole foods use USDA SR Legacy values bundled in `BuiltInFoods.swift`, so they work offline; packaged foods come from Open Food Facts.

## 3. Visual acceptance checklist (§11, §16, §17)

Environment for simulator rows: GitHub Actions `macos-26`, newest iPhone Pro Max simulator plus a small iPhone simulator, fixture time 12 Oct 2026 13:05, labelled FIXTURE DATA. Device rows need Wei's iPhone 18 Pro Max on iOS 27.

| Gate | Status | Evidence / how it is checked |
|---|---|---|
| Compiles for iOS 26 SDK on CI | NOT TESTED | CI run on the PR |
| Unit tests: exactly-once commit, cancel logs nothing, re-grab logs nothing, undo, deck bounds, stack scaling, rest additions, rest across relaunch, coach per body part, food parsing | NOT TESTED | `Tests/` on CI |
| Idle frame has one number, one mechanism, one primary action | NOT TESTED | `diet-idle.png` |
| Black mechanism readable without gloss or neon | NOT TESTED | `diet-idle.png`, `train-ready.png` |
| Same object persists through a 120° turn | NOT TESTED | `prism-half.png`, `gestures.mp4` |
| Block held: lift, tilt, landing region shown | NOT TESTED | `diet-held.png` |
| Contact: deck compressed, slab morphing, new value shown | NOT TESTED | `diet-contact.png` |
| Loaded settle: resting position lower than before | NOT TESTED | `diet-settled.png` against `diet-idle.png` |
| Drag, cancel, drop, re-grab and undo work by touch | NOT TESTED | `GestureTests`, `gestures.mp4` (drop and cancel are scripted; re-grab is unit-tested only) |
| Food intake inset fits the face and closes obviously | NOT TESTED | `diet-intake.png` |
| Over-target day: exact negative number, mechanism bounded, stack scaled | NOT TESTED | `diet-over-target.png` |
| Empty day | NOT TESTED | `diet-empty.png` |
| Hourglass: ready, resting, time added (taller glass, addition printed) | NOT TESTED | `train-ready.png`, `train-rest.png`, `train-rest-added.png` |
| BODY labelled schematic; ruler and values in sync | NOT TESTED | `body-idle.png` |
| No clipped text or controls at accessibility XXL | NOT TESTED | `a11y-xxl.png` |
| Small iPhone layout | NOT TESTED | `small/contact-sheet.png` |
| Projected-bounds assertions (§14, §16) | NOT TESTED | Not built yet; only frame review |
| Reduce Motion completes the same tasks | NOT TESTED | Code path exists (`reduceMotion` uses critically damped springs, no shake); no capture yet |
| VoiceOver: names, values, adjustable controls, drag alternatives | NOT TESTED | Accessibility actions exist (`loadQuick`, LOAD button, face buttons, adjustable rest and ruler); not audited |
| Sound, haptic and contact share one timestamp | NOT TESTED | Fired from the contact step in `MachineModel.land` and the seat crossing; needs the phone to judge |
| 120 Hz frame pacing, p95/p99, hitches, energy (§13) | NOT TESTED | Needs Instruments on the phone; Wei has no Mac, so this needs another route (see section 4) |
| Haptics and sound quality | NOT TESTED | Phone only |

## 4. Decisions still open for Wei

1. **The DIET gate (§11).** Approve the DIET slice from the captures and video, or say what feels wrong, before the TRAIN and BODY faces get the same polish and the widgets are rebuilt.
2. **Hero size.** Keep 40% of screen width, or the larger comparison frame, once both are rendered.
3. **Frame-rate measurement on the phone.** Without a Mac there is no Instruments. The fallback is an in-app debug overlay that records frame intervals on the phone and exports them as a file. Not built yet.

Technical defaults the team picked (P2, P3, P5, P6, P7) are recorded above and stand unless Wei objects.
