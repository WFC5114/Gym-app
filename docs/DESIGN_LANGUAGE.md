# GYM design language: the Laboratory Measuring Deck

Wei's binding design spec (revised 2026-10-12, replacing the earlier collection of separate "toys"). Every screen, widget, mockup and PR follows it. If something conflicts with convenience, this wins.

Revision 3 (2026-10-12): `docs/ART_DIRECTION.md` (Wei's Revision 2 art direction and implementation prompt) is the working implementation contract, and Wei's decisions at the end of it override both documents. `docs/DESIGN_REVIEW.md` records how the team applied it, the adopted proposals and the acceptance checklist.

## Core thesis
The whole app is **one machine**: a heavy, brutalist, matte-black calibration rig floating in black space (#000000). Every user action is filtered through that machine. No fragmented widgets, no tab bars, no hamburger menus, no pushed view controllers.

## 1. Spatial architecture
- The machine is an **equilateral triangular prism** centred in negative space.
- Its three faces are **DIET**, **TRAIN** and **BODY**.
- **Navigation:** horizontal edge-to-edge swipe rotates the prism exactly **120°** about its vertical Y-axis on a rigid spring, with **8% overshoot** and a snapping settle.
- **Camera:** fixed **orthographic** projection. Faces look perfectly flat head-on and reveal their massive depth only during rotation.

## 2. Faces

### Face A: DIET, the Hydraulic Counterweight Deck
Nutrition is a balance-scale machine fed by **real food logging** (Wei, 12 Oct): every food is weighed, confirmed and loaded onto the deck as a mass block.
- **Layout:** the upper 30% shows one number, kcal left (or over target, with the exact negative value), in a heavy geometric display face (Unbounded Black) sized so "8,888" spans about 40% of screen width. Below it, exact grams eaten against target: `PROTEIN 118 / 180 G`, carbs, fat. The middle 50% is a horizontal metal plate (the Deck) on two visible springs, with the day's food stacked on it as slabs. The lower 20% is the loading rail and the LOG FOOD / UNDO controls.
- **Logging food:** LOG FOOD opens an intake inset inside the face (search recent, built-in and Open Food Facts foods; scan or type a barcode; choose grams or a serving; FORM BLOCK). The confirmed food appears on the rail as a block sized by its energy; drag it onto the deck, or tap LOAD. Tapping the hero opens the day's ledger: change grams, delete, undo. Every inset has an obvious close.
- **Quick add:** the rail's four calibrated weights, **50, 100, 250, 500 kcal**, log energy only. Their protein, carbs and fat are recorded as unknown, never estimated.
- **Interaction:** touch lifts the block at once and it follows the finger with a slight tilt from its speed; the landing region shows while dragging; releasing outside springs it home and logs nothing; a falling block can be caught again; contact commits exactly once (the entry id is fixed before the drop), compresses the deck, plays the impact and morphs the block into its slab. A second drop can interrupt the settle.
- **Physics:** the deck compresses **in the face plane** (down the screen), not along the camera's Z axis, which is invisible head-on with an orthographic camera. Deck spring **mass 3.5, stiffness 450, damping 22**; momentum from the block's speed and energy.
- **Resting height:** compression = (kcal eaten ÷ target) × travel, bounded at 120% of target. The number always shows the exact value. If the stack would leave the mechanism, all slabs scale down together and the face says STACK SCALED.

### Face B: TRAIN, the Hourglass (Wei, 12 Oct; replaces the draining fluid)
- **Layout:** load × reps, set number and exercise on top (tap to change exercise, load and reps). The middle is a matte glass hourglass in a machined frame, with the coach's rest advice beside it. The lower part holds the rest controls and a large SET DONE.
- **Choosing rest:** before the set, −0:15 / +0:15 sets the rest (30 s to 5 min). **The glass grows and shrinks with the rest length** (smallest at 30 s, largest at 6 min).
- **Set done:** SET DONE logs the set and **flips the hourglass** on the piston spring (**mass 1.0, stiffness 800, damping 35**). The rack sound, the max haptic transient and a brief camera shake fire when the glass first seats. Each set flips it the other way.
- **Rest:** sand runs from the top bulb as the rest elapses. Wall-clock time is the source of truth; the exact clock is printed above. Rest survives the app being closed. **+0:30 REST** adds time mid-rest (the glass grows) and each addition is logged on its own. END REST stops early. When the time is up the face shows GO, with a glass tap and the rest-done haptic.
- **Rest log:** every rest is stored with exercise, body part, planned length, coach advice, each addition, how it ended and the actual rest until the next set. The AI coach reads it.
- **Coach:** recommends rest **per body part** (legs longer than chest or back, arms and core shorter, compound longer than isolation) and **adapts each day** from the rests Wei extended or cut short, today's HRV and resting heart rate, and last night's sleep. Missing Health data is said plainly. The reasons are printed under the advice; USE applies it.
- **Heart rate and cardio** (planned, not built): heart-rate zones will influence the glass and recoil; cardio will reuse the same glass and face.

### Face C: BODY, the Deforming Geometric Mesh
- **Layout:** current mass on top (78.4 KG, −0.4 / WK). Centre: an abstract low-poly mesh of your physical volume, matte grey, labelled **SCHEMATIC · NOT A BODY SCAN**. Bottom: an expansive horizontal **vernier scale** (ruler scrubber), with taller marks on InBody scan days. Missing values say NO DATA, never zero.
- **Time travel:** dragging across the ruler scrubs through Apple Health and InBody dates.
- **Deformation:** vertices morph in real time. **Body fat %** inflates the shell on X and Z (heavily damped). **Lean / skeletal muscle mass** pushes upper-torso vertices (shoulders, back, chest) out along their normals and contracts the midsection. Numbers spring with **mass 1.2, stiffness 180, damping 28**.

## 3. Sensory engine
Visual frame, audio and haptic are designed together and timed to the millisecond.

| Event | Motion | Sound (AVAudioEngine) | Haptic (Core Haptics) |
| --- | --- | --- | --- |
| Drop weight (food log) | Block hits Deck; Deck collapses down Z; dust particles scatter | Low organic impact: rubber mallet on granite | Dense train of low events, intensity 0.85, sharpness 0.20, scaled to meal weight |
| Set done | Hourglass flips and seats; brief camera shake | Sharp metallic ring of a barbell slamming a steel rack (compressed air + titanium snap) | One max shock transient, intensity 1.0, sharpness 0.95 |
| Scrub ruler | Vernier steps; mesh morph targets | High-res rotary encoder clicks; pitch rises linearly with thumb speed | Rapid light ticks, intensity 0.25, sharpness 0.80; hard spike on InBody days |
| Rotate prism | 120° yaw, 8% overshoot (9.6°), snap; one face per swipe at most | Low grind of a vault door or monolith sliding on concrete | Continuous pattern swelling at 60°, crisp seating pulse at 120° |

| Rest done | Sand runs out; GO | Glass tap | Two soft transients |

Sound and haptics fire at the modelled contact or seating moment, not at a spring's peak. Always honour Reduce Motion (no shake, critically damped springs, same tasks), the silent switch (`.ambient` audio that mixes with workout music), the in-app sound and haptics toggles, VoiceOver and Dynamic Type.

## 4. Widgets, Live Activities, Dynamic Island
Extensions can't run game loops or Metal, so they switch to **typographic brutalism**:
- **Widgets:** pure text on black fields. A changed number "strikes": it goes from ultra-light to massive bold weight. (The spec's one-frame white flash isn't possible in WidgetKit; we use a fast weight transition instead.)
- **Lock screen / Live Activity:** the same light-to-heavy strike when data or time updates.
- **Dynamic Island:** a flat mechanical gauge. Rest: `◔ REST 01:12`, a ring segment that fills step by step. Cardio: `▲ ZONE 4 14:02`, a pulsing zone and percentage tag. Expanded rest: a flat 2D hourglass outline with heavy, wide-tracked digits that rescale each step.

## 5. Skins
A skin is not an image swap. It is a config: palette, PBR material, physics parameters and a sound kit.

| Skin | Unlock | Palette (base / accent / mid) | Material | Sound kit |
| --- | --- | --- | --- | --- |
| MONO (default) | Available from the start | #000000 / #FFFFFF / #333333 | Matte graphite: roughness 0.9, metalness 0.0, no highlights | Anvil: dry mechanical hits, vault gears, dead sub-bass |
| CONCRETE | 7-day continuous logging streak | #4A4A4A / #F5F5F7 / #8E8E93 | Porous cement, procedural micro-pitting noise, roughness 0.95 | Quarry: stone grinding, gravel scrapes, seismic cracks |
| SIGNAL | 100% protein target 14 days in a row | #0F0F11 / #FF3B30 / #FF9500 | Coated zinc enamel: roughness 0.15, metalness 0.85 | Synth-Volt: relays, analog synth clicks, filter sweeps |

## 6. Data drives the machine
| Input (HealthKit) | Machine mutation |
| --- | --- |
| Dietary energy consumed vs target | Deck resting height |
| Dietary protein / carbs / fat | Mass block extrusion depth |
| Lean body mass / skeletal muscle | Mesh vertex displacement (upper torso out, waist in) |
| Body fat % | Mesh volume inflation on X/Z |
| Active energy burned | Deck target weight (adjusts kcal target) |
| Heart rate (in a workout, when the Watch supplies it) | Planned: hourglass and recoil response |
| HRV, resting heart rate, sleep | Coach rest advice per body part |

Rest periods (planned, coach advice, each added block of time, actual rest, how it ended) and cardio sessions (duration, intervals, zones) are stored and feed the AI review.

## 7. Technical stack
- **RealityKit + Metal, not SceneKit.** The spec names SceneKit, but Apple deprecated it in iOS 26. RealityKit gives the same model: one 3D view, entities with PBR materials, custom Metal surface/geometry shaders, 3D text meshes (`MeshResource.generateText`) and an orthographic camera (`OrthographicCameraComponent`).
- One root view hosts the RealityKit scene. Text and controls are native SwiftUI layers placed in each face's coordinates and projected with the same orthographic maths, so they turn with the prism and keep VoiceOver, Dynamic Type and keyboard input (proposal P6 in `docs/DESIGN_REVIEW.md`).
- **No animation curves.** Positions are integrated every frame with damped spring formulas (our own `Spring` solver), never `withAnimation` easing.
- **Core Haptics** custom patterns (`CHHapticEngine`), **AVAudioEngine** synthesis and sample banks per skin, synced to spring peaks.
- **Up to 120 Hz** on ProMotion while something moves; slower while only sand runs; paused when idle. ProMotion is adaptive, so no fixed rate is promised. Frame pacing must be measured on the phone.
- **InBody** data arrives through Apple Health, since the InBody app syncs scans there and there is no public InBody cloud API.

## Settled questions
- Real foods: settled by Wei on 12 Oct. The intake inset inside DIET (search, barcode, serving) forms a custom mass block; the kcal weights are quick-add.
- The AI coach: rest advice is printed on TRAIN today; the weekly review is still planned.
