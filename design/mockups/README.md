# Design mockups

Direction mockups shown to Wei before building a face. They are not the app:
numbers are sample data and every sheet is labelled MOCKUP.

| Folder | What | Wei's pick |
|---|---|---|
| `diet/` | DIET options: Plate, Gauge, Jar (HTML) | Jar (13 Oct 2026) |
| `jar/` | `pile.py`: prototype of the deterministic block pile (Pillow) | — |
| `body/` | BODY options: Figurine, Stacks, Dial (HTML from `make.py`) | Figurine (13 Oct 2026) |
| `train/` | TRAIN round 1 in Blender: Lab glass, Candy capsule, Gimbal (`options.jpg`, concepts A–C) | none (Wei: "elegant but minimal") |
| `train/` | TRAIN round 2, minimal: Teardrop, Orbit, Column (`options-minimal.jpg`, concepts D–F, `make_minimal.py`) | open |

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
