# Design mockups

Direction mockups shown to Wei before building a face. They are not the app:
numbers are sample data and every sheet is labelled MOCKUP.

| Folder | What | Wei's pick |
|---|---|---|
| `diet/` | DIET options: Plate, Gauge, Jar (HTML) | Jar (13 Oct 2026) |
| `jar/` | `pile.py`: prototype of the deterministic block pile (Pillow) | — |
| `body/` | BODY options: Figurine, Stacks, Dial (HTML from `make.py`) | Figurine (13 Oct 2026) |
| `body/motion.py` | BODY motion test 1: short, soft beech mannequin with a squash-and-spring touch (`motion.mp4`) | rejected (Wei: "mannequins are hard", "why so short", "looks fake") |
| `body/mannequin.py` | BODY mannequin round 2: hard, tall artist mannequin, stylised, beech vs graphite (`mannequin-looks.jpg`) | **Beech** (Wei, 14 Oct 2026) |
| `body/mannequin.py clay` | BODY mannequin round 3: claymorphism (Wei: realism reads uncanny; "highly detailed not just smooth"). One-colour clay, egg head, turned grooves, socket rings, pins, fingers, dotted dial; touch makes it flex (`mannequin-clay.jpg`, `mannequin-clay.mp4`) | waiting on Wei |
| `train/` | TRAIN round 1 in Blender: Lab glass, Candy capsule, Gimbal (`options.jpg`, concepts A–C) | none (Wei: "elegant but minimal") |
| `train/` | TRAIN round 2, minimal: Teardrop, Orbit, Column (`options-minimal.jpg`, concepts D–F, `make_minimal.py`) | none |
| `train/` | TRAIN desk hourglass from Wei's reference photos: wood plates, four black posts, brass collars (`desk.jpg`, concept G, `make_desk.py`) | **picked** (Wei, 13 Oct 2026: "I like this one") |

## Re-rendering

HTML sheets: open `index.html` in a browser, or screenshot it with
`node shot.mjs <abs path to index.html> <out.png>` (Playwright; the import path
in `shot.mjs` points at this container's global install, change it for yours).

BODY: `python3 body/make.py body` writes `body/index.html`.

TRAIN (Blender 5.2 as a Python module, `python3 -m pip install bpy`):

```sh
cd design/mockups/train
for c in A B C; do python3 scene.py $c "$PWD/final$c.png" 2 160; done   # 880x1912, Cycles CPU
python3 make.py "$PWD"                                                  # overlays the type layer
node ../shot.mjs "$PWD/index.html" "$PWD/options.png"
```

`scene.py` works in app units (1 = 100 pt) with an orthographic camera in
front of the face, the same as the app's `World`. The studio lighting (one soft
key, fill, two rim strips, top light) and materials are what the app's
RealityKit scene is meant to copy. Renders are offline path-traced, so the live
app will look somewhat less polished than these stills.

BODY motion test: `python3 body/motion.py <out dir> 120 24 0.8`, then
`ffmpeg -framerate 30 -i <out dir>/f%04d.png -c:v libx264 -pix_fmt yuv420p body/motion.mp4`.

Clay motion test: `python3 body/mannequin.py clay <out dir> 24 0.75 motion`, then the same ffmpeg line into `body/mannequin-clay.mp4`. `FLEX=1` renders a still with the arm flexed.
