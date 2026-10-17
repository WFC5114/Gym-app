# Desk objects prototype

Published as the "GYM Desk Objects" artifact (private to Wei). Sample data
throughout.

**v1 (17 Oct 2026, db3aa77).** Wei: keep claymorphism, the jar and the
hourglass, handle them in 3D (turn, shake), drop the mannequin, an identity of
our own. Wei on v1: "close", but it looked less good than the Blender renders
(lit live, meshes cut to 30%), the blocks misbehaved, not claymorphic enough,
not intuitive enough, and the AI coach should be easy to reach.

**v2 (f2e5f57).** What never moves comes from Cycles; what moves is lit by
Blender's own studio:
- `desk-backdrop-*.jpg`, `desk-env-*.hdr` (one per tab since v3): `design/render/desk_studio.py`. The
  desk is a picture from the live camera; the panorama is the studio seen
  from the object (key light left out: the live key casts the shadows).
- `jar.glb`, `hourglass.glb`: `design/render/export_objects.py` (Cycles AO
  baked per vertex into COLOR_0, used on ambient light only), then
  `gltfpack -kn -km -si 0.5`.
- `ui/`: `design/render/desk_ui.py`, clay pills, coach puck, tab well;
  the hero number uses the Night clay numerals (App/Resources/Rendered).
- `reference/`: Cycles renders from the live camera
  (`DESK_REF=1 python3 export_objects.py ...`) and the live view beside them.
- `desk.html`: three.js (AgX, like Blender) + cannon-es. The jar's blocks are
  simulated in the jar's own frame (gravity turned with the jar plus the
  forces of the hand's swing), so a hard twist can't push them through the
  glass: 0 escapes in a 90 s violent-shake test at 240 Hz. Rest time is the
  clock; the sand follows it. Coach: asks Claude through the artifact's
  `sample` capability about the sample day (the app will use Wei's own key).
- `pack_site.py <out>`: builds the artifact's files from this folder.

**v3 (this folder).** Wei on v2: "alright", but "slightly ugly since it's all
gray and black and white. I want some color but mature and some glassish jelly
like buttons and there should be a bar for macros that fills up".
- Each tab has its own clay desk that curves up into a wall behind the object
  (pine for Food, ink indigo for Rest, aubergine for Body; `desk_studio.py
  TABS`), and its own studio panorama, so the glass picks up the desk's colour.
  The pictures cross-fade on a spring when the tab changes.
- Controls are thick glass from Blender (`desk_ui.py`): clear glass that takes
  the desk's colour (chips, the tab rim), glass with a clay core (honey for the
  main action, ivory for the open tab), a ruby jelly coach puck. They stretch
  with a CSS border image, so the glass shows no seams.
- Macro gauges: a glass tube per macro over a clay fill that the page stretches
  to the day's share on a spring (protein terracotta, carbs honey, fat sage;
  the food blocks use the same clays). Targets 160 / 250 / 75 g are sample.
- The jar's base and the hourglass's dial plate are colour clays
  (`DESK_COLOURS=1 python3 export_objects.py ...`). `reference/` still shows v2.
