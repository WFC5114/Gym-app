# GYM design language: the Laboratory Measuring Deck

Wei's binding design spec (revised 2026-10-12, replacing the earlier collection of separate "toys"). Every screen, widget, mockup and PR follows it. If something conflicts with convenience, this wins.

Revision 3 (2026-10-12): `docs/ART_DIRECTION.md` (Wei's Revision 2 art direction and implementation prompt) is the working implementation contract, and Wei's decisions at the end of it override both documents. `docs/DESIGN_REVIEW.md` records how the team applied it, the adopted proposals and the acceptance checklist.

Revision 7 (2026-10-14): **Blender is the source of the look and the layout** (Wei: "I want it to be exactly like the render"; "none of the objects should be created from code, all straight from blender; coding controls the reactions, feel and functionalities"). On a rendered face (DIET and TRAIN; BODY's tray next) every object, key and gauge is a picture rendered in Cycles from the fitted Night scene (`design/render/night_diet.py` and `night_train.py` on the shared studio in `night_kit.py`, 3 px per point, soft shadows of still objects baked into the backdrop, moving objects carry their own feathered shadow), and `night-diet.json` / `night-train.json` give every picture's rect and the anchors for changing text. The app (`App/Machine/RenderedArt.swift`, `RenderedParts.swift`, `DietFaceRendered.swift`, `TrainFaceRendered.swift`) places the pictures, sets text in the render's own Inter Display at the render's sizes, and keeps all behaviour: taps, drags, springs, physics, sound, haptics, data. The jar's physics walls, the TARGET line and the rail come from the same layout. The hourglass is 21 renders by sand level, upright and turned over (true lighting both ways), crossfaded as the rest runs and switched at the half-turn of the flip; it scales about its base with the rest length. The in-face inset (food search, serving, today's log, set) is rendered too (`design/render/night_inset.py`): a recessed graphite well, blank glass keys at 40, 44 and 56 pt, the ivory primary key and the text-field slot. Their size follows the content, keyboard and phone, so `night-inset.json` gives each picture's slice insets and the app keeps the corners and stretches the middle (`SlicedSprite`); labels and rows are set in Inter Display over them. To change how something looks, change the Blender script and re-render; never draw it in code. BODY's mannequin moves too much to pre-render and stays live 3D in matched materials.

Revision 6 (2026-10-14): Wei found the app read as "just minimalism" next to the clay renders and asked for "3D-ish claymorphism with some glassish stuff resembling clay, not too childish but mature" across the whole app. Of three whole-screen mockups (`design/mockups/clay/screen.py`) Wei picked **NIGHT**, now the default skin: every face sits on a thick graphite clay tray (albedo #121115, which renders near the mockup's #211F24; rounded 26 pt, rolled edges); objects, hero numerals and primary keys are ivory clay (#F1ECE4 / #EDE5D8); secondary keys are smoked glass; macro gauges are clear glass tubes filled with clay (protein #C9744A, carbs #E3B57A, fat #EFE6D6); the accent is terracotta (#D9774E); labels are set in the system sans with tabular digits, raised off the clay. Keys, gauges, the coach plate and the BODY ruler bed and slider are real lit objects in the scene; SwiftUI only lays them out and prints their labels (`App/Machine/ClayParts.swift`). FLARE and MONO stay available.

Revision 4 (2026-10-13): Wei said the build still felt "very off" next to the Not Boring apps and chose **colour**: the default skin is now **FLARE** (saturated colour plate per face, lit, satin and clearcoat objects); matte black lives on as the MONO skin. Not Boring is the feel benchmark, learned only from their public write-ups and screenshots (no decompiling): juice stacked on every commit (windup, hit rays, camera kick, number punch, layered sound and matched haptic), lit 3D numerals, layered recorded plus synthesised sound. The gap analysis lives in the project files (`notes/not-boring-gap.md`).

Revision 6 (2026-10-14): **claymorphism across the whole app** (Wei). Realistic objects read as uncanny next to Not Boring, so every object becomes stylised clay: solid colours, a soft satin sheen and a fine pressed surface, chunky volumes. It is never simple or smooth for its own sake: objects are complex and tactile ("complex with tactile 3d object", "highly detailed not just smooth"), with real hardware detail (hinges, screws, socket rings, seams, knurled grips, raised lettering) and idle life (breathing, small shifts, reactions to touch). Hard objects stay hard: the look is clay, the motion is rigid on springs. BODY is the first face done this way; the hourglass and the jar follow.

## Core thesis
The whole app is **one machine**: a heavy calibration rig floating in black space (#000000), its faces skinned (NIGHT clay by default, FLARE colour, MONO matte black). Every user action is filtered through that machine. No fragmented widgets, no tab bars, no hamburger menus, no pushed view controllers.

## 1. Spatial architecture
- The machine is an **equilateral triangular prism** centred in negative space.
- Its three faces are **DIET**, **TRAIN** and **BODY**.
- **Navigation:** horizontal edge-to-edge swipe rotates the prism exactly **120°** about its vertical Y-axis on a rigid spring, with **8% overshoot** and a snapping settle.
- **Camera:** fixed **orthographic** projection. Faces look perfectly flat head-on and reveal their massive depth only during rotation.

## 2. Faces

### Face A: DIET, the Measuring Jar (Wei, 13 Oct; replaces the deck and slabs)
Nutrition is a tall glass jar fed by **real food logging** (Wei, 12 Oct): every food is weighed, confirmed and dropped in as a chunky block. Wei called the scale with slabs "very very ugly and goofy" and picked the Jar from three mockups (Plate, Gauge, Jar).
- **Layout:** the upper 30% shows one number, kcal left (or over target, with the exact negative value), in Unbounded Black sized so "8,888" spans 62% of the screen width (Wei picked Bigger, 13 Oct). Below it, exact grams eaten against target. The middle 50% is the jar, centred: thick candy glass (Wei, 14 Oct: thicker glass, same inside) with a raised butter TARGET bar and raised quarter marks on the front, a cream collar round the mouth with a rust seam, corner screws and a DIET plaque, on an indigo plinth with a knurled butter band (clay round 2, `design/mockups/clay/objects.py jar`). The lower 20% is the loading rail and the LOG FOOD / UNDO controls.
- **Blocks:** each logged food is one rounded block whose area follows its energy, so bigger meals are bigger blocks; proportions vary per food. Colour says what the food mostly is: golden carbs, roasted protein, pale fat, cream for mixed, amber for quick-adds (MONO uses greys). Name and kcal are printed on the block.
- **Logging food:** LOG FOOD opens the intake inset (search, barcode, serving, FORM BLOCK). The food waits on the rail; drag it over the jar, where it swells to its jar size, and let go, or tap LOAD. **Tapping a block in the jar opens that food** to change grams, delete or undo. Tapping the hero opens the whole day.
- **Quick add:** **50, 100, 250, 500 kcal** log energy only; macros are recorded as unknown, never estimated.
- **Interaction:** touch lifts the block at once and it trails the finger; the landing region shows while dragging; releasing outside springs it home and logs nothing; a falling block can be caught again; contact commits exactly once (the entry id is fixed before the drop).
- **Physics:** the released block falls with gravity, keeps some of its throw and spins. At contact it hands over to its place in the pile on the tumble spring (**mass 1.0, stiffness 220, damping 15**: one clear bounce), knocks nearby blocks, and the jar sinks under the weight on the heavy spring (**3.5 / 450 / 22**, three bounces). Holding a block over the jar winds it up: the jar pre-sinks and a low hum rises.
- **The pile:** built in logging order on a height map. Each block settles on the highest point under it and tips toward its centre of mass (up to 15°) until a second contact holds it; an unsupported block slides downhill, and a block that finds a much lower spot close by rolls into it. The same day always piles the same way. Deleting a block lets the ones above settle; undo drops it back in.
- **Target and overflow:** block areas are scaled so a day at target fills the jar to about the TARGET line. That is approximate because tipped blocks leave gaps; **the number is the exact value**. Past the target the pile rises out of the mouth; if it would leave the mechanism region, every block shrinks together and the face says BLOCKS SHRUNK TO FIT.

### Face B: TRAIN, the Hourglass (Wei, 12 Oct; replaces the draining fluid)
- **Layout:** load × reps, set number and exercise on top (tap to change exercise, load and reps). The middle is a **desk hourglass** (Wei's reference photos, 13 Oct), in clay since 14 Oct (Wei approved round 2 of `design/mockups/clay/objects.py hourglass`): layered indigo and cream plates top and bottom, turned orange cups at the bulb ends, four grooved orange posts in butter sleeves, butter dome nuts, and round, smooth, thick glass (the wall follows the surface normal, 0.022 of the mockup's height) with a heavy butter neck ring, holding pale clay sand. Each base slab carries raised minute ticks, a knurled knob for the rest and raised REST lettering, which shows on whichever slab is lower. Elegant and minimal: no beads, gimbals or ornament. It stands turned 28° and tipped 10° toward the camera so all four posts and the plate tops read. The coach's rest advice sits beside it. The lower part holds the rest controls and a large SET DONE.
- **Choosing rest:** before the set, −0:15 / +0:15 sets the rest (30 s to 5 min). **The glass grows and shrinks with the rest length** (smallest at 30 s, largest at 6 min).
- **Set done:** SET DONE logs the set and **flips the hourglass** on the piston spring (**mass 1.0, stiffness 800, damping 35**). The rack sound, the max haptic transient and a brief camera shake fire when the glass first seats. Each set flips it the other way.
- **Rest:** sand runs from the top bulb as the rest elapses. Wall-clock time is the source of truth; the exact clock is printed above. Rest survives the app being closed. **+0:30 REST** adds time mid-rest (the glass grows) and each addition is logged on its own. END REST stops early. When the time is up the face shows GO, with a glass tap and the rest-done haptic.
- **Rest log:** every rest is stored with exercise, body part, planned length, coach advice, each addition, how it ended and the actual rest until the next set. The AI coach reads it.
- **Coach:** recommends rest **per body part** (legs longer than chest or back, arms and core shorter, compound longer than isolation) and **adapts each day** from the rests Wei extended or cut short, today's HRV and resting heart rate, and last night's sleep. Missing Health data is said plainly. The reasons are printed under the advice; USE applies it.
- **Heart rate and cardio** (planned, not built): heart-rate zones will influence the glass and recoil; cardio will reuse the same glass and face.

### Face C: BODY, the clay mannequin
Wei picked the Figurine on 13 Oct 2026; on 14 Oct it became a tall, jointed **artist's mannequin in clay** (IKEA-style wooden mannequin as the reference, hard joints, not soft), approved from the Blender mockups in `design/mockups/body/` (`mannequin.py clay`).
- **Layout:** current mass on top (78.4 KG, −0.4 / WK). Centre: the mannequin on a dial turntable, labelled **SCHEMATIC · NOT A BODY SCAN** with a second line naming what the shape comes from (INBODY + HEALTH, or SAMPLE DATA; FAT FROM SCALE TREND (EST.) and TRAINING TILT (EST.) when they apply). Bottom: an expansive horizontal **vernier scale** (ruler scrubber), with taller marks on InBody scan days. Missing values say NO DATA, never zero.
- **The object:** cream clay body, orange joints, dark rust socket rings. Egg head with a small nose ridge and ears, no face. Seamed chest and hip blocks, a belly ball between socket cups, shoulder blades and a bead spine, hinge forks with screws at elbows and knees, jointed fingers on a knuckle bar, hinged toes. The dial is violet with a knurled butter-yellow rim, dots, raised week numbers 0 to 8 and a stand rod into the hips; the indigo plinth has bun feet, an index pointer, a crank and a BODY plaque with two screws. The stand leans its top 0.16 rad toward the camera so the dial reads.
- **Shape:** **body fat %** fills out the waist, belly ball, hips and limbs; **lean mass** broadens the shoulders and limbs. Lengths never change, only widths. Between InBody scans the **scale's smoothed trend** moves fat (lean held at the last scan, the change counted as fat), shown as FAT · EST with "≈"; estimates stop 90 days after a scan. A **training tilt** leans the shape at most ±5% toward the regions trained most (share of the last 28 days' lifted volume against an even programme; needs 12 sets), labelled an estimate. InBody's per-limb readings are not in Apple Health, so they are not used. Values are clamped (fat 5–45 %, lean 35–100 kg) and the arms swing out to clear the hips and belly. Shape values spring with **mass 1.2, stiffness 180, damping 28**.
- **Idle life:** while BODY is showing it breathes (4.2 s), shifts its weight between hips (9 s) and glances to its right now and then (glance spring 1.2/60/10). **Tap the figure** and it flexes its right arm (flex spring 1.0/140/13) for 1.3 s while the turntable gives a little swing, with a hollow wooden clack and a firm tick. Reduce Motion: no breathing, glances or swing; the flex is critically damped. Fixtures hold still.
- **Comparison:** a dashed outline of the chest and hips 8 weeks before the scrubbed day (or the earliest day there is, labelled with the real gap), hidden when that is under a week back or nothing changed.
- **Time travel:** dragging across the ruler scrubs through Apple Health and InBody dates; the figure morphs to each day and the turntable swings with the drag (up to 0.6 rad), then springs back to its three-quarter rest (tumble spring 1.0/220/15). Reduce Motion: no swing.

## 3. Sensory engine
Visual frame, audio and haptic are designed together and timed to the millisecond.

| Event | Motion | Sound (AVAudioEngine) | Haptic (Core Haptics) |
| --- | --- | --- | --- |
| Drop weight (food log) | Block hits the pile and tumbles into place; neighbours knock; the jar sinks; hit rays fly up | Low organic impact (mallet on granite plus recorded plate layers) with a glass tap, and a rising chime per food logged today | Dense train of low events, intensity 0.85, sharpness 0.20, scaled to meal weight |
| Set done | Hourglass flips and seats; brief camera shake | Sharp metallic ring of a barbell slamming a steel rack (compressed air + titanium snap) | One max shock transient, intensity 1.0, sharpness 0.95 |
| Scrub ruler | Vernier steps; figurine morphs and the turntable swings | High-res rotary encoder clicks; pitch rises linearly with thumb speed | Rapid light ticks, intensity 0.25, sharpness 0.80; hard spike on InBody days |
| Rotate prism | 120° yaw, 8% overshoot (9.6°), snap; one face per swipe at most | Low grind of a vault door or monolith sliding on concrete | Continuous pattern swelling at 60°, crisp seating pulse at 120° |

| Rest done | Sand runs out; GO | Glass tap | Two soft transients |
| Tap the mannequin | Right arm flexes, turntable swings a little | Hollow wooden clack (provisional: the seat sample pitched up) | One firm tick, intensity 0.7, sharpness 0.55 |

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
| NIGHT (default) | Available from the start | Graphite clay trays (albedo #121115); ivory clay objects and numerals #F1ECE4; terracotta accent #D9774E; void #000000 | Clay with grain, satin coat and (iOS 27) subsurface; clear and smoked glass; brass hardware | Anvil plus recorded CC0 impact layers |
| FLARE | Available from the start | Face plates DIET #E8461E, TRAIN #2340E0, BODY #7B3FE4; objects #FFF4E0; void #000000 | Satin plates (roughness 0.62), cream objects with clearcoat, chrome springs, amber sand | Anvil plus recorded CC0 impact layers |
| MONO | Available from the start | #000000 / #FFFFFF / #333333 | Matte graphite: roughness 0.9, metalness 0.0, no highlights | Anvil: dry mechanical hits, vault gears, dead sub-bass |
| CONCRETE | 7-day continuous logging streak | #4A4A4A / #F5F5F7 / #8E8E93 | Porous cement, procedural micro-pitting noise, roughness 0.95 | Quarry: stone grinding, gravel scrapes, seismic cracks |
| SIGNAL | 100% protein target 14 days in a row | #0F0F11 / #FF3B30 / #FF9500 | Coated zinc enamel: roughness 0.15, metalness 0.85 | Synth-Volt: relays, analog synth clicks, filter sweeps |

## 6. Data drives the machine
| Input (HealthKit) | Machine mutation |
| --- | --- |
| Dietary energy consumed vs target | How full the jar is (blocks sized by energy) |
| Dietary protein / carbs / fat | Block colour by the dominant macro |
| Lean body mass (InBody via Health) | Mannequin shoulders and limbs broaden |
| Body fat % (InBody via Health) | Mannequin waist, belly, hips and limbs fill out |
| Body mass trend between scans | Estimated fat moves with the smoothed scale trend (labelled EST.) |
| Logged sets, last 28 days | Training tilt toward the most-trained regions, ±5% at most (labelled EST.) |
| Active energy burned | Planned: adjusts the kcal target (the TARGET etch) |
| Heart rate (in a workout, when the Watch supplies it) | Planned: hourglass and recoil response |
| HRV, resting heart rate, sleep | Coach rest advice per body part |

Rest periods (planned, coach advice, each added block of time, actual rest, how it ended) and cardio sessions (duration, intervals, zones) are stored and feed the AI review.

## 7. Technical stack
- **RealityKit + Metal, not SceneKit.** The spec names SceneKit, but Apple deprecated it in iOS 26. RealityKit gives the same model: one 3D view, entities with PBR materials, custom Metal surface/geometry shaders, 3D text meshes (`MeshResource.generateText`) and an orthographic camera (`OrthographicCameraComponent`).
- One root view hosts the RealityKit scene. Text and controls are native SwiftUI layers placed in each face's coordinates and projected with the same orthographic maths, so they turn with the prism and keep VoiceOver, Dynamic Type and keyboard input (proposal P6 in `docs/DESIGN_REVIEW.md`).
- **No animation curves.** Positions are integrated every frame with damped spring formulas (our own `Spring` solver), never `withAnimation` easing.
- **Core Haptics** custom patterns (`CHHapticEngine`), **AVAudioEngine** synthesis layered with recorded CC0 impact samples (`App/Sounds`, provenance in `LICENSE-SOUNDS.txt`), five variants per sound, synced to spring peaks.
- **Hero numerals** are extruded RealityKit text meshes standing on the face (DIET so far); the SwiftUI text stays invisible for layout, hit testing and VoiceOver.
- **Up to 120 Hz** on ProMotion while something moves; slower while only sand runs; paused when idle. ProMotion is adaptive, so no fixed rate is promised. Frame pacing must be measured on the phone.
- **InBody** data arrives through Apple Health, since the InBody app syncs scans there and there is no public InBody cloud API.

## Settled questions
- Real foods: settled by Wei on 12 Oct. The intake inset inside DIET (search, barcode, serving) forms a custom mass block; the kcal weights are quick-add.
- The AI coach: rest advice is printed on TRAIN today; the weekly review is still planned.
