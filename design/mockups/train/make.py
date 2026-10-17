import sys
D = sys.argv[1]

css = '''<!doctype html><html><head><meta charset="utf-8"><title>TRAIN options</title><style>
body{margin:0;background:#0b0b0d;color:#fff;font-family:"DejaVu Sans Mono",monospace;padding:28px 30px 34px}
h1{font:700 22px "DejaVu Sans Mono";letter-spacing:2px;margin:0 0 6px}
.sub{font-size:11px;letter-spacing:1.5px;color:#9a9aa4;margin-bottom:22px}
.row{display:flex;gap:34px}
.col{width:440px}
.phone{position:relative;width:440px;height:956px;border-radius:34px;overflow:hidden;box-shadow:0 0 0 6px #1c1c20}
.phone img{position:absolute;inset:0;width:440px;height:956px}
.t{position:absolute;color:#fff;letter-spacing:1.6px;white-space:nowrap;text-shadow:0 1px 0 rgba(0,0,0,.35)}
.tag{position:absolute;right:16px;top:64px;font-size:9px;letter-spacing:2px;background:#000a;padding:4px 8px;border-radius:6px}
.cap{font:700 15px "DejaVu Sans Mono";letter-spacing:2px;margin:18px 0 6px}
.desc{font-size:12px;line-height:1.55;color:#c9c9d2}
</style></head><body>
<h1>TRAIN: three options for the hourglass</h1>
<div class="sub">RENDERED IN BLENDER (CYCLES) WITH THE STUDIO LIGHTING THE APP WOULD COPY · MOCKUPS, NOT THE APP · SAMPLE NUMBERS · COLOUR SKIN</div>
<div class="row">
'''


def face(img):
    return f'''<div class="phone"><img src="{img}">
<div class="t" style="left:36px;top:26px;font-size:13px">B · TRAIN</div>
<div class="t" style="left:36px;top:46px;font-size:10px;opacity:.9">SAMPLE DATA</div>
<div class="t" style="right:30px;top:32px;font-size:12px">‹ DIET  BODY ›</div>
<div class="tag">MOCKUP</div>
<div class="t" style="left:36px;top:258px;font-size:11px">REST AFTER SET 1 · BACK SQUAT</div>
<div class="t" style="left:36px;top:278px;font-size:11px;opacity:.9">SET 3:00 · +0:30 ADDED</div>
<div class="t" style="left:36px;top:308px;font-size:9px;opacity:.85">COACH · LEGS 4:00 TODAY</div>
<div class="t" style="left:36px;top:323px;font-size:9px;opacity:.85">YOU ADDED TIME ON 5 OF 5 LEG RESTS</div>
<div class="t" style="left:36px;top:770px;width:178px;text-align:center;font-size:13px;font-weight:700">+0:30 REST</div>
<div class="t" style="left:226px;top:770px;width:178px;text-align:center;font-size:13px;font-weight:700">END REST</div>
<div class="t" style="left:36px;top:855px;width:368px;text-align:center;font-size:17px;font-weight:700;color:#1a1d33;text-shadow:0 1px 0 #fff8">SET DONE</div>
</div>'''


cols = [
    ('A', 'LAB GLASS', 'finalA.png', 'A classic hourglass made properly: thick clear glass with real refraction, chunky cream turned caps with a dark groove, and three brass posts. Amber sand with a grainy surface pours in a thin stream. SET DONE flips it end over end with a heavy shake; a longer rest means a taller glass.'),
    ('B', 'CANDY CAPSULE', 'finalB.png', 'One pinched glass pill sitting in a glossy orange cup, filled with shiny amber beads instead of sand. The beads click through the neck one at a time and pile up with little bounces, which is where the sound and haptic ticks come from. The most toy-like of the three.'),
    ('C', 'GIMBAL', 'finalC.png', 'The hourglass swings on an axle inside a chrome ring with minute ticks, on a cream stand. SET DONE spins it a half turn on the axle with an overshoot, like a gyroscope. The ring doubles as a dial for the rest length.'),
]
html = css
for letter, name, img, desc in cols:
    html += f'<div class="col">{face(img)}<div class="cap">{letter}. {name}</div><div class="desc">{desc}</div></div>\n'
html += '</div></body></html>'
open(D + '/index.html', 'w').write(html)
