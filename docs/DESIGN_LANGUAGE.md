# GYM design language: the Laboratory Measuring Deck

Wei's binding design spec (revised 2026-10-12, replacing the earlier collection of separate "toys"). Every screen, widget, mockup and PR follows it. If something conflicts with convenience, this wins.

## Core thesis
The whole app is **one machine**: a heavy, brutalist, matte-black calibration rig floating in black space (#000000). Every user action is filtered through that machine. No fragmented widgets, no tab bars, no hamburger menus, no pushed view controllers.

## 1. Spatial architecture
- The machine is an **equilateral triangular prism** centred in negative space.
- Its three faces are **DIET**, **TRAIN** and **BODY**.
- **Navigation:** horizontal edge-to-edge swipe rotates the prism exactly **120°** about its vertical Y-axis on a rigid spring, with **8% overshoot** and a snapping settle.
- **Camera:** fixed **orthographic** projection. Faces look perfectly flat head-on and reveal their massive depth only during rotation.

## 2. Faces

### Face A: DIET, the Hydraulic Counterweight Deck
Nutrition is a balance-scale machine, not logs or forms.
- **Layout:** top half shows one number, kcal left, in a hyper-bold geometric sans about 40% of screen width, with a macro tag below it (e.g. 40% PROTEIN). Under it, a massive horizontal metal plate (the Deck) sits on two visible hydraulic springs.
- **Input:** four raw geometric blocks at the bottom are calibrated weights: **50, 100, 250, 500 kcal**. Drag one up and drop it on the Deck.
- **Physics:** on contact the kcal number "destroys" its value and springs down to the new one. The Deck drops on the Z-axis with an ultra-heavy underdamped spring (**mass 3.5, stiffness 450, damping 22**): 3 decaying bounces, then settle.
- **Resting height:** the Deck's rest position = (calories eaten ÷ daily target) × max compression, so it sits lower as the day fills.
- **Macros:** dietary protein, carbs and fat set the extrusion depth of the mass blocks.

### Face B: TRAIN, the Hydraulic Piston Core
- **Layout:** exercise and set config on top (e.g. BENCH PRESS · 80 KG × 8 · SET 2/4). The lower half is a heavy piston chamber. During an active set the piston head is compressed deep down the screen.
- **Set done:** an enormous brutalist SET DONE button. Tapping it fires a camera-shake matrix; the piston slams up to its concrete limit (**mass 1.0, stiffness 800, damping 35**); numbers flash inverted.
- **Rest:** no digital clock as the hero. An ultra-matte procedural fluid (Metal shader) **drains out of the bottom** of the chamber as rest time runs down, exposing the void.
- **Heart rate:** during a Watch workout, heart rate is read every 5 s. In zones 3–5 the fluid gets more viscous and darker, and the SET DONE recoil spring stiffens.
- **Cardio** lives on this face too (steady, intervals, zone 2), using the same chamber.

### Face C: BODY, the Deforming Geometric Mesh
- **Layout:** current mass on top (78.4 KG, −0.4 / WK). Centre: an abstract low-poly wireframe mesh of your physical volume, matte grey. Bottom: an expansive horizontal **vernier scale** (ruler scrubber).
- **Time travel:** dragging across the ruler scrubs through Apple Health and InBody dates.
- **Deformation:** vertices morph in real time. **Body fat %** inflates the shell on X and Z (heavily damped). **Lean / skeletal muscle mass** pushes upper-torso vertices (shoulders, back, chest) out along their normals and contracts the midsection. Numbers spring with **mass 1.2, stiffness 180, damping 28**.

## 3. Sensory engine
Visual frame, audio and haptic are designed together and timed to the millisecond.

| Event | Motion | Sound (AVAudioEngine) | Haptic (Core Haptics) |
| --- | --- | --- | --- |
| Drop weight (food log) | Block hits Deck; Deck collapses down Z; dust particles scatter | Low organic impact: rubber mallet on granite | Dense train of low events, intensity 0.85, sharpness 0.20, scaled to meal weight |
| Set done | Full-viewport shake; piston hits upper limit; numbers flash inverted | Sharp metallic ring of a barbell slamming a steel rack (compressed air + titanium snap) | One max shock transient, intensity 1.0, sharpness 0.95 |
| Scrub ruler | Vernier steps; mesh morph targets | High-res rotary encoder clicks; pitch rises linearly with thumb speed | Rapid light ticks, intensity 0.25, sharpness 0.80; hard spike on InBody days |
| Rotate prism | 120° yaw, 8% overshoot, snap | Low grind of a vault door or monolith sliding on concrete | Continuous pattern swelling at 60°, crisp seating pulse at 120° |

Always honour Reduce Motion, the silent switch and an in-app sound toggle.

## 4. Widgets, Live Activities, Dynamic Island
Extensions can't run game loops or Metal, so they switch to **typographic brutalism**:
- **Widgets:** pure text on black fields. A changed number "strikes": it goes from ultra-light to massive bold weight. (The spec's one-frame white flash isn't possible in WidgetKit; we use a fast weight transition instead.)
- **Lock screen / Live Activity:** the same light-to-heavy strike when data or time updates.
- **Dynamic Island:** a flat mechanical gauge. Rest: `◔ REST 01:12`, a ring segment that fills step by step. Cardio: `▲ ZONE 4 14:02`, a pulsing zone and percentage tag. Expanded rest: a flat 2D Piston Core with heavy, wide-tracked digits that rescale each step.

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
| Heart rate (every 5 s in a workout) | Piston fluid viscosity and colour; recoil stiffness |

Rest periods (planned vs actual, sets before and after) and cardio sessions (duration, intervals, zones) are stored and feed the weekly AI review.

## 7. Technical stack
- **RealityKit + Metal, not SceneKit.** The spec names SceneKit, but Apple deprecated it in iOS 26. RealityKit gives the same model: one 3D view, entities with PBR materials, custom Metal surface/geometry shaders, 3D text meshes (`MeshResource.generateText`) and an orthographic camera (`OrthographicCameraComponent`).
- One root view hosts the RealityKit scene. Text, indicators and buttons are 3D entities or flat vector planes inside it. They still expose **VoiceOver accessibility** elements.
- **No animation curves.** Positions are integrated every frame with damped spring formulas (our own `Spring` solver), never `withAnimation` easing.
- **Core Haptics** custom patterns (`CHHapticEngine`), **AVAudioEngine** synthesis and sample banks per skin, synced to spring peaks.
- **Locked 120 Hz** on ProMotion; profile every face in Instruments.
- **InBody** data arrives through Apple Health, since the InBody app syncs scans there and there is no public InBody cloud API.

## Open questions for Wei
- The four kcal weights handle quick logging. Real foods (barcode, search, saved meals) need an input path that fits the machine. The proposal is to long-press the Deck to open an intake slot that scans a barcode and produces a custom-weight block.
- The AI coach has no face. The proposal is engraved readout lines on each face, plus a weekly review that prints from the machine on Sundays.
