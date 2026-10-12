# GYM design language

Wei's binding design brief, adapted from the "(Not Boring)" design language for a personal gym app. Every screen, widget, mockup and PR follows it. If something here conflicts with speed or simplicity, this wins.

## 1. Software as a toy
- Every control feels like a physical object with **mass, friction and elasticity**. Buttons are extruded keys that plunge into the Z-axis; sliders and lists fling with inertia and bounce off their edges.
- **Juicy feedback:** mundane actions get disproportionate feedback. Logging a meal is a 3D motion plus a sound plus a haptic, never a silent row insert.
- **Discovery over efficiency:** the app stays fast to use, but may slow a moment down to make it delightful.

## 2. Visual and spatial
- **Monochrome canvas.** The default skin is strictly black, white and neutral grey. Colour comes only from skins, 3D materials and moments of reward.
- **Editorial type.** Oversized, bold, expressive faces with tight kerning. Numbers (kcal left, weight, rest seconds) are hero graphics that take over the screen, not data in a table.
- **Spatial skeuomorphism.** Abstract, modernist 3D, not glossy photorealism. Cards are physical slabs on a real Z-axis that spin, flip and slide over each other. No flat cards with drop shadows.
- **Skins are collectibles.** The visual layer is a swappable skin (palette, pattern, 3D materials). Skins unlock through streaks and milestones.

## 3. Motion and physics
- **Springs everywhere.** All motion uses damped harmonic springs defined by mass, stiffness and damping. No linear or ease-in-out curves. Released elements overshoot and settle.
- **Procedural, real-time animation.** Liquids, particles and materials are simulated live, not pre-rendered loops.
- **3D morphing navigation.** Moving between sections rotates a monolith to show the next face, or flies the camera through space. No plain push or fade transitions.

## 4. Sound and haptics
- **Custom sounds**, no system beeps: a mechanical click wheel when scrubbing, a heavy gear click per rest second, a resonant chord on a goal. Synthesised live with `AVAudioEngine`, so pitch and volume follow the speed of your thumb.
- **Custom Core Haptics** patterns, not presets. Intensity and sharpness follow drag velocity: slow drag means micro-ticks, a fast fling means a heavy thud at the edge. The haptic peak lands on the same frame as the spring's peak.
- Everything respects the silent switch, a sound toggle, and Reduce Motion.

## 5. Gamified data
- **The scrubber is the main way to explore data.** Drag horizontally to travel through time; the 3D scene, lighting and numbers morph with your finger.
- **Rewards:** streaks and milestones earn brutalist badges, pop animations and unlockable skins.

## The core toys of GYM
Each area of the app turns a chore into a physical ritual.

| Area | Core toy | Ritual |
| --- | --- | --- |
| Today / diet | **The Vessel**: a glass block that fills with liquid as you eat | Logging food drops it in; the liquid sloshes with a spring and tilts with the phone. Over target, it overflows. |
| Food log | **The Tape**: a paper receipt ledger | Meals print onto the tape; fling it to scroll back through days with inertia. |
| Body / InBody | **The Monolith**: a stone slab whose layers are fat, muscle and water | Scrub the timeline and the slab morphs scan by scan. Streaks polish it; missed weeks weather it. |
| Training | **The Bar**: a barbell you load plate by plate | Finishing a set slams a plate on with a clank and a heavy haptic. PRs make the bar bend. |
| Rest timer | **The Dial**: a heavy mechanical dial | Every second clicks like a gear. It lives in the Dynamic Island. The last 3 seconds hit harder. |
| Cardio timer | **The Hourglass**: a vessel that drains | Intervals drain and refill it; heart-rate zones change the material. |
| Progress | **Badges and skins** | Unlocked skins and badges sit on a shelf you can spin. |

## Tech stack for this language
- **SwiftUI** for layout, with `.rotation3DEffect`, `.visualEffect`, `PhaseAnimator`/`KeyframeAnimator` and custom spring values (`Spring(mass:stiffness:damping:)`).
- **RealityKit** for true 3D objects (Monolith, Vessel, Bar). SceneKit is deprecated as of iOS 26, so it is not used.
- **Metal shaders** through SwiftUI `layerEffect`/`colorEffect` and RealityKit custom materials for liquids, stone and particles, kept on the GPU.
- **Core Haptics** (`CHHapticEngine`) for custom patterns driven by gesture velocity.
- **AVAudioEngine** for synthesised, velocity-reactive sound.
- Target a locked 120 Hz on ProMotion. Profile with Instruments before shipping any 3D screen.

## Timers feed the AI
Rest and cardio timers are data sources, not just clocks. Every rest period (planned versus actual seconds, the set before and after) and every cardio session (duration, intervals, heart-rate zones from Health) is stored and goes into the weekly AI review. For example: "Your bench reps drop when rest is under 100 seconds."
