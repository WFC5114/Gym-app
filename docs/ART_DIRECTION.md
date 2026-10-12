<!-- Stored verbatim from Wei's message in the project thread, 12 October 2026.
     Only formatting was added (headings, lists, tables). This is the working
     implementation contract for design work. Where it conflicts with
     "Wei's decisions" at the end, the decisions win. -->

# GYM — art direction and implementation prompt

_Prepared for Wei · 12 October 2026 · Revision 2_

This is a proposed clarification of the current design brief, not an approved replacement for docs/DESIGN_LANGUAGE.md. The one-machine concept remains binding. New layout measurements are starting targets for visual review, not measurements taken from Not Boring. Items explicitly marked “proposal” need Wei's design decision before becoming project requirements.

Revision 2 incorporates Wei's requirements for entirely code-produced art direction, richer personalized interaction, extensibility, and strict layout containment. Sections 12–17 turn those requirements into a proposed implementation and acceptance contract. Quantitative thresholds are project targets, not measured properties of Not Boring. No prompt can certify equivalent feel or eliminate every future bug; the deliverable must include evidence from the implemented app.

---

## The prompt

You are designing Wei's personal native iPhone gym and nutrition app in https://github.com/WFC5114/Gym-app. Your task is to achieve a distinctive, polished interaction design informed by the whole Not Boring product family. Deliver a concrete visual prototype before expanding the feature implementation.

### 1. Read the project and references first

Read the current CLAUDE.md, any applicable AGENTS.md, docs/DESIGN_LANGUAGE.md, and the current UI code. Inspect the actual working branch. Do not assume that documentation describes implemented behavior. At the time this prompt was prepared, PR #1 was open on m0-foundation; its description still mentioned the superseded separate-toys concept, and its diff contained a conventional DashboardView built from ScrollView and VStack.

Study these primary references:

- Product family: https://notbor.ing/
- Weather: https://notbor.ing/product/weather
- Game feel breakdown: https://notbor.ing/words/the-most-satisfying-checkbox
- Sound design: https://notbor.ing/words/the-sound-of-software
- Apple's interview with the creators: https://developer.apple.com/news/?id=9ab1g4r3

Inspect available product imagery and interaction videos, not only marketing text. Clearly distinguish what you actually observed from your interpretation. If video playback is unavailable, say so; do not invent interaction details.

The useful principle is expressive utility with game feel: everyday input becomes a satisfying, comprehensible event through composition, material response, motion, sound, and touch. Not Boring is a reference for craft and interaction quality. Our monochrome laboratory and triangular prism are Wei's own design decisions, not universal rules of their products.

Do not repeat unsupported claims from older notes that every Not Boring control is 3D, every animation is procedural, every transition is a spring, or that UIKit and SwiftUI are entirely bypassed. Apple's 2022 account describes a mixed stack; the creators' checkbox breakdown includes authored 2D animation as well as 3D. Build our chosen architecture honestly rather than attributing it to them.

### 2. The intended emotional and visual result

Create a precision instrument that feels unusually satisfying under a thumb. Its visual identity should combine monumental editorial typography, sculptural depth, deliberate negative space, and restrained industrial materials. It feels dense, responsive, and carefully manufactured.

Quiet at rest. Immediately responsive to touch. Expressive at the exact moment an action commits. Quickly readable throughout.

The machine is the interface. Nutrition changes its load, training changes its pressure, and body history changes its measured form. A decorative render placed above an ordinary dashboard fails this direction.

Avoid turning “brutalist” into arbitrary clutter, illegible labels, aggressive sci-fi decoration, or gratuitous destruction. Avoid turning “playful” into constant wobbling, cartoon softness, confetti, or unrelated gimmicks. The spectacle belongs to meaningful interactions.

### 3. One object and three faces

Retain the Laboratory Measuring Deck: one equilateral triangular prism in pure black space, with DIET, TRAIN, and BODY faces. The three mechanisms share a chassis, geometry vocabulary, typography, lighting, and manufacturing logic.

Use a fixed orthographic camera. At rest the active face is square to the viewer. Edge swipes rotate the same object 120 degrees around its vertical axis. Preserve spatial continuity; the other face must become visible because the object turns, not because one screen crossfades into another.

Define rotation overshoot as 8% of 120 degrees, or 9.6 degrees, in a standard zero-velocity test. Actual gesture velocity affects a real spring, so document and test how fast throws are bounded. A partially completed rotation can be reversed without resetting velocity or teleporting.

There are no top-level tabs, hamburger menus, or pushed app screens. Add a subtle first-use edge-swipe hint and accessible face-switch actions. Distinguish edge navigation from interior food dragging and history scrubbing. Once a gesture owns an interaction, it keeps ownership until release or cancellation.

Secondary functions must unfold within the active machine face. They must have an obvious way to close. Do not hide essential food logging or corrections exclusively behind long presses.

### 4. Composition, type, and material

Use this initial composition on a reference portrait canvas, adjusting for safe areas and readable content:

- Shared side alignment: approximately 6% of viewport width.
- Upper 30% of usable height: the hero readout and its immediate context.
- Middle 50%: the face's integrated mechanism, generally spanning 75–90% of usable width.
- Lower 20%: its direct controls, with comfortable thumb reach.

One dominant number group, one mechanism, and one obvious primary action. Secondary information yields to these.

Preserve the current brief's approximately 40%-of-screen-width calorie readout as the starting point. Inspect real strings such as 0, 850, 1,850, and −150; do not claim one fixed type size works for all of them. Propose a larger hero only if comparison demonstrates a better hierarchy, and flag the change.

Use a tightly spaced, heavy geometric sans for display numerals. Choose by the shapes of 0, 1, 4, 7, and 8 rather than merely applying bold to the default font. Keep units smaller and visually attached to values. Use a compact supporting face for legible labels; use monospaced digits when stable alignment helps. Never horizontally distort text to fit. Do not crop meaningful digits. Show the actual chosen font and fallback; verify permission to bundle it.

MONO uses the existing #000000 / #FFFFFF / #333333 palette and matte graphite roughness 0.9. Black background does not mean invisible geometry. Use broad, soft directional illumination to reveal planes, restrained edge separation, contact shadows, small chamfers, and subtle surface grain. No glossy chrome, neon rims, decorative fog, lens flares, or fake dashboard drop shadows.

The brief's “no highlights” should mean no conspicuous glossy specular highlights. If interpreted as no tonal modeling at all, it conflicts with readable matte volume; flag that ambiguity. Do not secretly change the camera to perspective to rescue depth.

### 5. DIET — make logging feel like adding calibrated mass

Show remaining kcal as the dominant readout. Make the macro tag unambiguous: identify whether a percentage means target completion or energy share. Expose exact protein/carbohydrate/fat amounts in the face's expanded readout.

The deck is supported by two visible compression mechanisms. The 50/100/250/500 kcal blocks belong to its built-in loading rail. Their width, chamfer, labels, and material match the chassis.

Interaction sequence:

- Touch: immediately show capture and lift; the block follows the finger without a canned waiting animation.
- Drag: preserve its mass through secondary tilt and restrained lag while keeping placement predictable. Reveal the valid landing region.
- Release outside the landing region: spring back without logging anything.
- Contact: commit the food event once, compress the mechanism, trigger the impact sound and haptic, and transform the old readout into the new value.
- Settle: the machine arrives at a new persistent loaded position. A second input can interrupt the animation without losing the first log.

Use the existing deck spring mass 3.5, stiffness 450, damping 22. The three visible decaying rebounds are a visual target to verify under a defined impulse and settling threshold, not something those constants guarantee in every circumstance.

Map consumed/target to compression with a bounded display range. Preserve the exact underlying value, including over-target intake. Never let clamping the mechanism hide the number.

Resolve the coordinate ambiguity before implementation: with a front-facing orthographic camera, travel only along camera Z does not look like a downward drop. Specify world axes and the mechanism's local compression axis. Propose visible in-plane compression with any secondary depth travel, and flag this against the existing “drops on Z” wording.

Proposal for full food logging: a visibly labeled intake control reveals an integrated face inset for search, barcode scanning, serving amount, and confirmation. Confirmation forms a custom mass block and loads the deck. Support edit, delete, and undo. A quick-add calorie block records unknown macros as unknown; never fabricate protein, carbs, or fat from its calorie value. Define labeled, bounded macro-to-depth mappings with common units.

### 6. TRAIN — make completing a set release stored pressure

Keep exercise, load, reps, and set index readable above the piston. SET DONE is a substantial control mechanically connected to the chamber.

During a set, the chamber looks compressed and loaded. On activation, accept input immediately, release the piston, and produce one distinct hard-stop impact. Use the existing spring 1.0 / 800 / 35. Camera shake is brief, localized in intensity, and does not impair the next interaction. Number inversion is momentary; the result remains readable.

Rest is the same chamber transitioning to a draining state. Keep an exact secondary time readout for use in the gym. Use elapsed time as the source of truth; the fluid is a visualization and cannot change the actual countdown. Rest survives app suspension and relaunch.

Use available heart-rate samples to influence the fluid and recoil. Treat “every five seconds” as a desired UI refresh cadence, not a promise that the watch or HealthKit supplies a fresh reading on demand. Show unavailable/stale data honestly. Increased viscosity must not delay the real timer or make the primary control hard to activate. Cardio reuses this chamber rather than introducing another metaphor.

### 7. BODY — make historical comparison tangible

Keep weight and weekly delta above a sculptural low-poly mesh. The mesh is an abstract measurement visualization, not a photorealistic avatar or an anatomical prediction. A Vernier ruler occupies the lower control area.

Scrubbing synchronizes date, source, exact values, and mesh state. Mark real scan dates distinctly. Distinguish interpolated visual transitions from actual observations; missing data is not zero. Use the existing number spring 1.2 / 180 / 28.

Preserve the proposed fat and lean-mass deformation directions as an expressive mapping, but label the representation schematic. Global lean mass cannot establish a person's actual shoulder or waist shape. Do not manufacture segmental measurements. Keep trustworthy numeric history available within this face; do not introduce a default line-chart dashboard.

### 8. Motion, sound, and haptics form one interaction

For every action define touch-down, tracking, release/cancel, commitment, impact, and settle states. Driven movement follows the user. Released movement preserves velocity and uses our damped springs. Do not restart an animation from its initial state on repeated input.

Keep these sensory profiles:

| Event | Sound | Haptic intensity / sharpness |
|---|---|---|
| Block contact | Rubber mallet against granite | 0.85 / 0.20, dense low pattern |
| Piston stop | Barbell against steel rack | 1.0 / 0.95, one transient |
| Ruler detent | Rotary encoder | 0.25 / 0.80, stronger on scan dates |
| Prism movement | Vault-door grinding and seating | Swell near 60°, seating pulse at 120° |

Trigger contact feedback at the modeled contact/stop event. A spring's maximum displacement is not automatically the moment of collision. Derive audio, haptic, and animation timing from shared event timestamps; verify synchronization on hardware rather than promising perfect millisecond alignment from a simulator.

Use subtle sample or parameter variation to avoid identical repetitive clicks. Gesture velocity may influence pitch within a bounded range. Primary actions are stronger than navigation, which is stronger than micro-adjustments. Keep AVAudioEngine and custom Core Haptics as the chosen implementation direction. Respect silent mode, the app's sound toggle, and haptic preferences; do not interrupt workout music unnecessarily.

Reduce Motion preserves the task, state changes, and tactile confirmation while removing camera shake and large spatial travel. VoiceOver must expose names, values, adjustable controls, and alternatives to dragging. Verify Dynamic Type and usable touch targets.

### 9. Platform and engineering honesty

Use RealityKit + Metal for the spatial machine. Apple marks SceneKit deprecated and recommends RealityKit. Retain native infrastructure for accessibility, permissions, keyboard input, and supported system integrations. Any visible native input inset that conflicts with the existing all-geometry requirement must be raised as a specific proposal, not introduced silently.

The user names iPhone 18 Pro Max / iOS 27 as the target. Verify the installed SDK, deployment target, API availability, and actual device before claiming compatibility. Target up to 120 fps during interaction on supported hardware; do not promise a permanent refresh-rate lock. Measure frame pacing and energy use. Stop unnecessary work while idle or backgrounded.

Integrate physics using elapsed time with a stable solver or bounded fixed substeps. Keep persistence independent of rendering. Never derive nutrition values, set counts, or timers from animation completion callbacks.

Widgets and Live Activities keep the typography and identity within platform capabilities. Do not promise one-frame flashes, continuous custom physics, or unrestricted per-second refresh. Document supported update behavior and still-frame fallbacks. Keep the existing MONO, CONCRETE, and SIGNAL skin definitions and unlock rules; build MONO fidelity first. Skin changes must never alter stored health data or timing semantics.

Keep the approved feature roadmap. The visual prototype does not authorize feature removal, account changes, releases, or merging.

### 10. Useful repositories — scoped references, not automatic dependencies

| Repository | Inspect it for | Boundary |
|---|---|---|
| https://github.com/jtrivedi/Wave | Interruptible, velocity-preserving, retargetable spring animation; property-based animator examples | A motion reference, not a 3D machine framework. Keep one authoritative motion driver; do not run competing solvers. Check current Apple guidance for frame-rate configuration rather than copying old README settings blindly. |
| https://github.com/EmergeTools/Pow | Event-driven SwiftUI change effects, particles, shake, and example organization | Selective reference only. Its built-in haptic presets do not fulfill our custom Core Haptics requirement; its effect catalogue is not our visual design system. |
| https://github.com/twostraws/Inferno | Readable Metal fragment-shader examples, noise, distortion, and SwiftUI shader integration | These are SwiftUI shaders, not drop-in RealityKit materials, vertex deformation, or a physical fluid solver. Adapt only the relevant mathematics and interfaces. |

Verify licenses, version compatibility, and maintenance before including code. Do not add all three packages. No official open-source Not Boring app implementation was verified for this brief; do not present unrelated weather clones as their code.

### 11. Deliver in an order that proves fidelity

First produce a short comparison between the existing UI and this direction. Cite actual source files. Identify contradictions separately from missing implementation.

Then create a polished DIET vertical slice using clearly labeled fixture data. Show these exact states: idle, block held, contact, loaded settle, and half-rotated prism. Supply a runnable interaction prototype and a short motion capture where tooling allows. A still render alone cannot establish game feel.

Before expanding all faces, demonstrate:

- The idle frame has a clear number/mechanism/action hierarchy.
- The black mechanism is readable without glossy or neon effects.
- The same physical object persists through a 120° rotation.
- A block can be grabbed, canceled, dropped, interrupted, and undone.
- A committed drop changes data exactly once and visibly changes resting state.
- Sound, touch, and contact share a deliberate timing design.
- Reduced-motion and accessible controls complete the same tasks.
- Claimed performance is supported by device measurements; untested behavior is labeled.

Provide a visual acceptance checklist and identify the remaining proposed decisions. Follow Wei's existing design approval gate before broad implementation. Once approved, synchronize docs/DESIGN_LANGUAGE.md, project instructions, agent role notes, and affected PR descriptions so there is one coherent source of design truth.

Do not call a monochrome dashboard with large text a successful implementation. Success is a functional, coherent instrument whose input, state, material response, and feedback feel deliberately designed together.

### 12. The agent owns all visual production

Wei supplies product preferences and feedback, not artistic labor. Choose and implement geometry, layout, lighting, typography, shader materials, microtexture, motion, sound, and haptics. Do not hand over a task list asking Wei to draw icons, sculpt models, paint textures, make Figma screens, or supply final audio.

Produce every custom visual through Swift/RealityKit geometry, Metal shaders, vector paths, or deterministic asset-generation scripts. If offline mesh generation is useful, generate the asset through code and retain its source script. Headless modeling is acceptable; manual editing must not be required to reproduce the result. Existing licensed fonts may be bundled automatically with attribution. Do not depend on an image-generation subscription, opaque mockup, or purchased model to make the app look complete.

Own an asset recipe for each component: dimensions, tessellation, normals, bevel/chamfer, material parameters, light response, bounds, collision shape, and reduced-detail form. Build the prism, deck, springs, piston, fluid surface, ruler, and abstract body mesh as a coherent family. Curved geometry must remain smooth at the actual viewing scale; low-poly faceting on BODY is intentional.

Keep font sizes, spacing, corner treatments, palette, lights, materials, motion, audio, and haptics in named configuration values. Avoid scattered visual constants. Separate procedural detail from readable silhouettes. Use fixed random seeds for visual tests; bounded variation is allowed during normal use.

Generate original sound layers through synthesis and scripted processing where possible. If a physical impact requires a recorded source to meet quality, locate an appropriately licensed sample and automate its processing with provenance. Declare unresolved quality limitations; do not silently replace the intended material sound with a generic beep. Wei does not need to record or edit audio.

### 13. Fluidity and game feel: measurable behavior

Use these initial acceptance targets on the named test device. Record device, OS, build mode, refresh mode, thermal state, and accessibility settings with results.

| Property | Required behavior / proposed gate |
|---|---|
| Initial response | Apply the visual pressed/grabbed state in the next render update after receiving input. Introduce no artificial delay before acknowledgment. Report hardware response separately; do not claim this implies 8 ms touch-to-photon latency. |
| Direct manipulation | The grabbed point tracks the touch. Use secondary rotation/deformation to suggest mass; do not make the primary touch anchor swim behind the finger. Document any intentional resistance and its bounds. |
| Interruption | Re-grab, reverse, or retarget from the current presentation state, retaining applicable velocity. No reset, teleport, or animation queue. |
| Repeated input | Animation does not disable input. One completed user action produces one domain event. Decorative particles and audio may be bounded/coalesced under load; actual logs may not be silently dropped. |
| 120 Hz rendering | Target the 8.33 ms frame cadence on supported hardware under normal conditions. Report CPU/GPU timings, p95/p99 frame intervals, missed frames, and hitch duration. A screenshot or average FPS alone is insufficient. |
| Benchmark | After warm-up, run a repeatable 60-second mixed gesture sequence. Proposed gate: fewer than 1% missed presentation deadlines at the supported test cadence and no app-attributable stall over 50 ms. Include a cold first-use run separately. These are targets to measure, not claims of current performance. |
| Constrained operation | Preserve correct behavior and continuous motion when the OS lowers refresh rate or thermal headroom falls. Reduce particle count, mesh detail, and shader work before sacrificing input response or readability. |
| State coherence | Repeated input, backgrounding, interruptions, and frame-rate changes cannot duplicate logs, lose undo state, or change elapsed rest time. |

Distinguish gesture feel from settling time. Existing deck constants produce a much slower settling envelope than the piston; that is allowed. The user must not wait for all rebounds before acting again. Define visible settling with both displacement and velocity thresholds in consistent units, rather than counting frames.

Preserve the existing spring profiles until a comparison justifies a change. Record the displacement/velocity response for a standard input, including overshoot and settling. Do not normalize away the different personalities of loading, firing, scrubbing, and seating.

Make optional exploration pleasurable without corrupting data: dragging and canceling, scrubbing existing history, and nudging a control can provide tactile response; food or set records require a deliberate commit. Keep a stable grammar of press, resistance, release, contact, and recovery. Add richness to these interactions before adding more decorative effects.

### 14. No unintended clipping, overlap, or visible framing

Treat layout correctness as a release requirement, including intermediate animation frames. “No borders” means no decorative card outlines, phone-like frames, accidental strokes, rectangular render-surface edges, or seams from mismatched black backgrounds. Functional ruler marks, the piston housing, and deliberate machined edges remain part of the instrument.

All essential text, values, controls, and accessible hit regions stay inside the usable safe area. The backdrop alone may extend edge to edge. Account for the Dynamic Island, device corners, home indicator, keyboard, and presented system UI through platform layout information, not hard-coded assumptions about a phone model.

Define three explicit regions per face: readable content, interaction targets, and permitted visual motion. Use at least 44 × 44 pt hit regions for buttons without making adjacent actions ambiguous. Reserve a proposed minimum 8 pt clearance between each mechanism's maximum projected motion envelope and the usable viewport boundary; default resting margins remain larger. Do not shrink every control to solve crowding.

Compute the full projected envelope of geometry across the allowed rotation, overshoot, compression, dragging, mesh deformation, and camera shake. Include font overhang, bevels, and visible effects. Choose a stable camera scale and scene allocation that fits this envelope; do not dynamically zoom on every bounce to hide collisions with the viewport. Sweep the full transition and use conservative analytical bounds where possible. Sampled screenshots alone cannot prove continuous containment.

Check camera near/far planes, thin-surface depth ordering, back-face behavior, and z-fighting. Keep labels attached to their mechanism and prevent unintended penetration into neighboring geometry. Intentional physical contact and occlusion inside a chamber are allowed and documented. Essential text must not disappear behind a moving block or piston.

For typography, measure actual shaped glyph bounds at the current font, locale, scale, and value. Reserve space for signs, decimal separators, units, and changing digit counts. Use layout variants: reflow supporting labels, expand the face's detail inset, or reduce decorative geometry. Never repair overflow by truncating critical values, scaling readable text below the project's minimum, applying a blanket clipping mask, or hiding the offending element.

At accessibility text sizes or with a keyboard present, the face may use a dedicated in-face accessible layout with internal scrolling and a reduced mechanism. Keep the same face and task. Flag this explicit exception to the old absolute “no lists/forms” wording; it must not become a new top-level dashboard.

Particles stay within a declared effect envelope and cannot obstruct readouts. Fluid is intentionally masked by its chamber. Distinguish those designed masks from accidental clipping; do not report intended masking as a bug or use it to conceal a layout defect.

### 15. Personalization and future features

Define “better” as better for Wei's actual use: fewer repeated setup steps, remembered exercises and meals, preferred units, clear correction/undo, adjustable sensory intensity, and insights with visible supporting data. Rich interaction should make frequent actions rewarding while keeping them practical with one hand in a gym.

Persist visual settings separately from health records. Remember per-exercise load/reps/rest, favorite foods and serving sizes, selected face, and interaction preferences where appropriate to the approved roadmap. Preserve muscle memory: personalization cannot spontaneously rearrange primary actions or change gesture meanings. Do not infer nutritional correctness from visual rewards.

Use separate responsibilities rather than one growing view file:

- Domain models and persistence: food, training, timers, body observations, and settings.
- Feature state and commands: validation, deliberate commit, cancellation, and undo.
- Presentation mapping: domain values into bounded positions, fill levels, text, and shape parameters.
- Shared interaction engine: gesture ownership, state transitions, spring integration, and semantic sensory events.
- Render components: procedural geometry, typography, materials, lighting, and effects.
- Platform adapters: HealthKit, Watch data, keyboard/scanner, widgets, Live Activities, and AI.

This is a separation of responsibilities, not a requirement to build six packages. Prefer the smallest architecture that enforces it. No speculative plug-in marketplace or generic feature engine.

Every new feature must declare: its DIET/TRAIN/BODY owner; entry and exit; state and commands; needed data and missing-data behavior; geometry/text bounds; gesture ownership; sound/haptic profile; accessible alternative; persistence migration if applicable; and relevant regression cases. It must reuse shared visual and interaction components unless a deliberate new pattern is reviewed.

A feature may occupy an integrated detail inset or secondary state of its existing face. Future features must not accumulate as extra dashboard cards or new toys. If a useful feature cannot fit the three-face structure, describe the exact conflict to Wei rather than squeezing it into an unusable layout or silently creating a fourth face.

### 16. Visual and interaction verification

Extend the existing GitHub Actions macOS build with targeted simulator UI/render checks and export reviewable artifacts. A compiler pass is not a visual pass. The current CI workflow establishes builds/tests and IPA artifacts; it does not by itself prove appearance, bounds, or hardware game feel.

Create deterministic fixture states and fixed-time render captures. Cover the selected device plus the smallest supported portrait viewport; test every declared layout class and each skin before shipping it. Declare supported orientations and handle unsupported rotation predictably rather than claiming untested layouts.

| Category | Cases that must be represented |
|---|---|
| Text/data | Zero, long positive values, negative remaining kcal, decimals, long exercise/food names, missing data, long dates, larger text, supported units/locales |
| Geometry | Idle; full compression; spring extremes; both rotation directions and overshoot; maximum body deformation; dragged blocks near edges |
| Input | Slow/fast drags; cancel outside target; reverse midway; re-grab during settle; conflicting interior/edge gestures; repeated distinct actions |
| Platform | Keyboard shown; safe-area changes; Reduce Motion; VoiceOver; muted audio; app background/resume; unavailable or stale live data |
| State | Empty history; loading; failure; first log; over-target intake; undo; active set; resting; completed rest; reopened persisted session |

Use assertions on projected bounds, critical text rectangles, and interaction regions, with debug overlays for diagnosis. Check unintended region intersections; exempt documented physical overlaps. Combine these checks with full-resolution image review for composition and visual defects. Keep snapshot environments stable; perceptual tolerances may cover rendering noise, never missing text or controls.

Snapshot changes require inspection and an explanation. Do not regenerate baselines merely to make a failing test green. Rerun impacted gesture paths after a geometry, type, or motion change. Run deterministic state tests for cancellation, exactly-once logging, undo, and timer restoration because visual tests cannot establish data correctness.

Export a contact sheet, representative full-resolution frames, a gesture recording, and a concise pass/fail report. If rendering or recording is blocked, identify the blocked verification instead of replacing evidence with a written claim. Use actual-device profiling for fluidity, heat, haptics, and sound. Simulator speed or a compressed 60 fps video cannot certify 120 Hz behavior.

### 17. Beauty is an iteration requirement

The coding agent must inspect its own rendered output and revise composition, lighting, type, and motion until the following are resolved: hierarchy, silhouettes, tonal separation, optical alignment, whitespace, material consistency, and state-to-state continuity. Passing bounds tests does not excuse an awkward composition.

Choose and defend a coherent visual direction; Wei is not expected to art-direct every bevel or type size. Offer comparison frames only for meaningful unresolved choices. Use the approved best frame as a visual reference, while checking that moving and extreme states remain equally coherent.

Do not promise “better than Not Boring” as an established outcome. Demonstrate comparable craft through a working prototype and direct interaction comparison, then demonstrate improvements through Wei's actual workflows. Completion requires separate evidence for visual quality, fluidity, interaction correctness, containment, accessibility, and personalized usefulness. Mark each gate PASS, FAIL, or NOT TESTED, with the environment and evidence. Do not merge or release a build with known critical text clipping, unreachable controls, unintended mesh penetration, or overflow.

## Research notes outside the prompt
- The manufacturer's site describes game-inspired visuals and sensory interaction alongside quick utility. Its skins show that strict monochrome is not a universal brand requirement: https://notbor.ing/
- Apple's 2022 interview directly supports the mixed Blender/SceneKit/UIKit/SwiftUI workflow; it is historical evidence, not a claim about their current private source: https://developer.apple.com/news/?id=9ab1g4r3
- The creators' checkbox essay documents anticipation, reversal, combined 2D/3D effects, and custom sound/haptics. It does not substantiate the attachment's universal “all procedural, all springs” claims: https://notbor.ing/words/the-most-satisfying-checkbox
- The sound essay supports variation, material identity, related sound families, and testing on actual playback devices: https://notbor.ing/words/the-sound-of-software
- Current Apple documentation directs SceneKit users to RealityKit: https://developer.apple.com/documentation/scenekit
- ProMotion is adaptive; preferred frame rate is not a guarantee: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- Apple documents safe-area-aware layout and adaptation to larger text: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple recommends 44 × 44 pt touch controls: https://developer.apple.com/design/tips/
- Metal performance should be evaluated through frame-time profiling: https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app
- At 120 Hz the display interval is approximately 8.33 ms; application work, presentation cadence, and total input latency are different measurements: https://developer.apple.com/videos/play/tech-talks/10855/

The reviewed project brief was https://github.com/WFC5114/Gym-app/blob/m0-foundation/docs/DESIGN_LANGUAGE.md and the reviewed foundation PR was https://github.com/WFC5114/Gym-app/pull/1. No repository files were changed while preparing this prompt.

---

## Wei's decisions (12 October 2026, override the prompt where they conflict)

Wei's words, verbatim:

> What we have right now is very fake the set done just make an hourglass that flips after each set with possibility to change time and as time changes hourglass size changes log the rest time to ai coach and make sure that if add time to rest then it also logged on top of that make sure that ai coach also gives time for leg rest and other body part rest because each day is different. The food wise not just click of add calories actually log food then do interactive not just press buttons I have to be honest about everything.

What that settles:

1. **TRAIN rest is an hourglass**, inside the TRAIN face of the same prism. It replaces the draining-fluid rest from section 6. SET DONE still commits the set and flips the glass.
2. **Rest time is adjustable, and the hourglass size follows it**: a longer rest is a taller glass.
3. **Every rest is logged for the AI coach**, including each block of time added mid-rest, recorded as its own addition.
4. **The coach recommends rest per body part** (legs separately from other parts), and the recommendation adapts day to day.
5. **DIET is real food logging**: search, barcode, servings and macros, made interactive. The 50/100/250/500 kcal rail stays as quick-add only. This adopts the section 5 "full food logging" proposal.

How the team applied the rest of the prompt is recorded in `docs/DESIGN_REVIEW.md`.
