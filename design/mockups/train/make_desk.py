import sys
D = sys.argv[1]

css = '''<!doctype html><html><head><meta charset="utf-8"><title>TRAIN minimal options</title><style>
body{margin:0;background:#0b0b0d;color:#fff;font-family:"DejaVu Sans Mono",monospace;padding:28px 30px 34px}
h1{font:700 22px "DejaVu Sans Mono";letter-spacing:2px;margin:0 0 6px}
.sub{font-size:11px;letter-spacing:1.5px;color:#9a9aa4;margin-bottom:22px}
.row{display:flex;gap:34px}
.col{width:440px}body{width:520px}
.phone{position:relative;width:440px;height:956px;border-radius:34px;overflow:hidden;box-shadow:0 0 0 6px #1c1c20}
.phone img{position:absolute;inset:0;width:440px;height:956px}
.t{position:absolute;color:#fff;letter-spacing:1.6px;white-space:nowrap;text-shadow:0 1px 0 rgba(0,0,0,.35)}
.tag{position:absolute;right:16px;top:64px;font-size:9px;letter-spacing:2px;background:#000a;padding:4px 8px;border-radius:6px}
.cap{font:700 15px "DejaVu Sans Mono";letter-spacing:2px;margin:18px 0 6px}
.desc{font-size:12px;line-height:1.55;color:#c9c9d2}
</style></head><body>
<h1>TRAIN: the desk hourglass</h1>
<div class="sub">RENDERED IN BLENDER (CYCLES) WITH THE STUDIO LIGHTING THE APP WOULD COPY · MOCKUPS, NOT THE APP · SAMPLE NUMBERS · COLOUR SKIN</div>
<div class="row">
'''


def face(img):
    return f'''<div class="phone"><img src="{img}">
<div class="t" style="left:36px;top:26px;font-size:13px">B · TRAIN</div>
<div class="t" style="left:36px;top:46px;font-size:10px;opacity:.85">SAMPLE DATA</div>
<div class="t" style="right:30px;top:32px;font-size:12px;opacity:.9">‹ DIET  BODY ›</div>
<div class="tag">MOCKUP</div>
<div class="t" style="left:36px;top:258px;font-size:11px">BACK SQUAT · REST AFTER SET 1</div>
<div class="t" style="left:36px;top:280px;font-size:9.5px;opacity:.75">COACH · LEGS 4:00 TODAY</div>
<div class="t" style="left:36px;top:785px;width:174px;text-align:center;font-size:12px;opacity:.92">+0:30</div>
<div class="t" style="left:230px;top:785px;width:174px;text-align:center;font-size:12px;opacity:.92">END REST</div>
<div class="t" style="left:36px;top:858px;width:368px;text-align:center;font-size:15px;font-weight:700;letter-spacing:3px;color:#1a1d33;text-shadow:none">SET DONE</div>
</div>'''


cols = [('', 'DESK HOURGLASS', 'finalG.png', 'From your photos: square dark-wood plates, four matte black posts with brass collars and dome nuts, round clear bulbs and fine white sand. Turned a little so all four posts show. On SET DONE the whole piece flips end over end on a heavy spring; a longer rest makes it taller.')]
html = css
for letter, name, img, desc in cols:
    html += f'<div class="col">{face(img)}<div class="cap">{name}</div><div class="desc">{desc}</div></div>\n'
html += '</div></body></html>'
open(D + '/index-desk.html', 'w').write(html)
