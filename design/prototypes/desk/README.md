# Desk objects prototype

Published as the "GYM Desk Objects" artifact (private to Wei). Sample data
throughout.

**v1 (17 Oct 2026, db3aa77).** Wei: keep claymorphism, the jar and the
hourglass, handle them in 3D (turn, shake), drop the mannequin, an identity of
our own. Wei on v1: "close", but it looked less good than the Blender renders
(lit live, meshes cut to 30%), the blocks misbehaved, not claymorphic enough,
not intuitive enough, and the AI coach should be easy to reach.

**v2 (this folder).** What never moves comes from Cycles; what moves is lit by
Blender's own studio:
- `desk-backdrop.jpg`, `desk-env.hdr`: `design/render/desk_studio.py`. The
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
