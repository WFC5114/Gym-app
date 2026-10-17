# Desk objects prototype (17 Oct 2026)

Wei: keep claymorphism, the jar and the hourglass, handle them in 3D (turn,
shake), drop the mannequin, and make an identity of our own instead of
following Not Boring.

- `desk.html`: three.js + cannon-es page (published as the "GYM Desk Objects"
  artifact). Food = the jar (rigid-body clay blocks, sized by kcal, coloured
  by main macro), Rest = the hourglass (sand level under any tilt, flows the
  way the glass is held, turn it over to start a rest), Body = weight trend.
  Sample data.
- `jar.glb`, `hourglass.glb`: exported from the Night Blender scenes with
  `design/render/export_objects.py`, then `gltfpack -kn -km -si 0.3`
  (about 30% of the triangles). The artifact ships them as base64 inside JSON.
