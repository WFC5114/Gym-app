import sys, math
S = sys.argv[1]
css = open(S + '/../diet/index.html').read()
head = css[:css.index('</style>')]
head = head.replace('--face:#E8461E', '--face:#7B3FE4').replace(
    'linear-gradient(170deg,#F05A2E 0%,var(--face) 45%,#D63E16 100%)',
    'linear-gradient(170deg,#8A52F0 0%,var(--face) 45%,#6630CC 100%)').replace('<title>DIET options</title>', '<title>BODY options</title>')
head += '''.ruler{position:absolute;left:22px;right:22px;bottom:96px;height:58px;border-radius:10px;background:#2b1250;box-shadow:inset 0 5px 8px #0008}
.btn.dark{background:#2b1250}
</style></head><body>
<h1>BODY: three options for the body face</h1>
<div class="sub">MOCKUPS DRAWN IN HTML FOR DIRECTION ONLY · NOT THE APP · SAMPLE NUMBERS (79.8 KG, 15.8% FAT, 67.2 KG LEAN, 8 WEEKS) · COLOUR SKIN</div>
<div class="row">
'''


def ruler():
    t = ''
    for i in range(57):
        x = 10 + i * 5.6
        h = 14 if i % 7 == 0 else 7
        t += f'<line x1="{x:.1f}" y1="6" x2="{x:.1f}" y2="{6+h}" stroke="#fff" stroke-opacity=".55" stroke-width="1"/>'
        if i % 14 == 0:
            t += f'<circle cx="{x:.1f}" cy="32" r="3.5" fill="#FFC94A"/>'
    for k, l in enumerate(['AUG 17', 'AUG 31', 'SEP 14', 'SEP 28', 'OCT 12 ']):
        t += f'<text x="{10+k*14*5.6:.1f}" y="50" text-anchor="{'start' if k==0 else ('end' if k==4 else 'middle')}" font-family="DejaVu Sans Mono" font-size="7.5" fill="#fff" fill-opacity=".8" letter-spacing="1">{l}</text>'
    return f'<div class="ruler"><svg width="326" height="58">{t}<rect x="{10+56*5.6-3:.1f}" y="2" width="6" height="30" rx="3" fill="#fff"/></svg></div>'


hdr = '<div class="hdr"><div>C · BODY<small>SAMPLE DATA</small></div><div>‹ TRAIN  DIET ›</div></div>'
btns = '<div class="btns"><div class="btn" style="flex:2">LOG WEIGHT</div><div class="btn dark" style="flex:1">HEALTH</div></div>'


def col(letter, name, inner, desc):
    return f'''<div class="col"><div class="phone"><div class="face">{hdr}{inner}{ruler()}{btns}</div><div class="tag">MOCKUP</div></div>
<div class="cap"><b>{letter}.</b> {name}</div><div class="desc">{desc}</div></div>
'''


hero = '''<div class="hero" style="font-size:64px">79.8<span style="font-size:20px;letter-spacing:1px;margin-left:10px;text-shadow:none">KG</span></div>
<div class="lbl" style="top:150px;font-size:9.5px;letter-spacing:1.5px">−0.3 KG/WK <span class="dim">· FAT 15.8% · LEAN 67.2 KG</span></div>'''

figA = hero + '''<svg style="position:absolute;left:0;top:176px" width="370" height="420" viewBox="0 0 370 420">
<defs><radialGradient id="vin" cx="38%" cy="30%" r="80%"><stop offset="0" stop-color="#fffdf6"/><stop offset=".6" stop-color="#f4e6c8"/><stop offset="1" stop-color="#cdb68c"/></radialGradient>
<linearGradient id="tt" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#3a1b6b"/><stop offset="1" stop-color="#1c0b38"/></linearGradient>
<filter id="fs"><feDropShadow dx="0" dy="10" stdDeviation="9" flood-opacity=".35"/></filter></defs>
<ellipse cx="185" cy="356" rx="118" ry="24" fill="url(#tt)"/><ellipse cx="185" cy="350" rx="118" ry="24" fill="#4a2486"/>
<g fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="2" stroke-dasharray="4 5"><rect x="142" y="112" width="86" height="120" rx="40"/></g>
<g filter="url(#fs)" fill="url(#vin)">
<circle cx="185" cy="62" r="30"/>
<rect x="148" y="104" width="74" height="122" rx="34"/>
<rect x="112" y="110" width="30" height="96" rx="15" transform="rotate(8 127 110)"/>
<rect x="228" y="110" width="30" height="96" rx="15" transform="rotate(-8 243 110)"/>
<rect x="152" y="222" width="30" height="120" rx="15"/>
<rect x="188" y="222" width="30" height="120" rx="15"/>
</g>
<line x1="262" y1="104" x2="226" y2="122" stroke="#fff" stroke-opacity=".7" stroke-dasharray="3 3"/>
<text x="266" y="104" font-family="DejaVu Sans Mono" font-size="8.5" fill="#fff" letter-spacing="1.5">8 WEEKS AGO</text>
<text x="185" y="404" text-anchor="middle" font-family="DejaVu Sans Mono" font-size="8.5" fill="#fff" letter-spacing="2">SCHEMATIC · NOT A BODY SCAN</text>
</svg>'''

bars = ''
weeks = [(81.6, 17.4), (81.3, 17.2), (81.0, 17.0), (80.9, 16.8), (80.6, 16.5), (80.4, 16.3), (80.1, 16.0), (79.8, 15.8)]
for i, (w, f) in enumerate(weeks):
    x = 22 + i * 41
    lean = w * (1 - f / 100)
    fat = w * f / 100
    base = 330
    hl = (lean - 60) * 12
    hf = (fat - 8) * 14
    yl = base - hl
    yf = yl - hf - 3
    op = '1' if i == 7 else '.8'
    rot = -4 if i % 2 else 3
    bars += f'<g opacity="{op}"><rect x="{x}" y="{yl:.0f}" width="34" height="{hl:.0f}" rx="9" fill="#F6E7C8"/><rect x="{x}" y="{yf:.0f}" width="34" height="{hf:.0f}" rx="9" fill="#FFC94A" transform="rotate({rot} {x+17} {yf+hf/2:.0f})"/></g>'
    bars += f'<text x="{x+17}" y="{base+24}" text-anchor="middle" font-family="DejaVu Sans Mono" font-size="8" fill="#fff" fill-opacity=".9">{w}</text>'

figB = hero + f'''<svg style="position:absolute;left:0;top:176px" width="370" height="420" viewBox="0 0 370 420">
<filter id="bs"><feDropShadow dx="0" dy="6" stdDeviation="4" flood-opacity=".3"/></filter>
<rect x="14" y="330" width="342" height="10" rx="4" fill="#2b1250"/>
<g filter="url(#bs)">{bars}</g>
<g font-family="DejaVu Sans Mono" font-size="8.5" fill="#fff" letter-spacing="1.2">
<rect x="24" y="30" width="12" height="12" rx="3" fill="#F6E7C8"/><text x="42" y="40">LEAN</text>
<rect x="92" y="30" width="12" height="12" rx="3" fill="#FFC94A"/><text x="110" y="40">FAT</text>
<text x="150" y="40">ONE STACK PER WEEK</text>
<text x="185" y="380" text-anchor="middle" font-size="8">BLOCKS START AT 60 KG LEAN, 8 KG FAT</text></g>
</svg>'''

ticks = ''
for v in range(70, 92):
    a = math.radians(-130 + (v - 70) * (260 / 21))
    r1 = 118
    r2 = 104 if v % 5 == 0 else 110
    ticks += f'<line x1="{185+r1*math.sin(a):.1f}" y1="{200-r1*math.cos(a):.1f}" x2="{185+r2*math.sin(a):.1f}" y2="{200-r2*math.cos(a):.1f}" stroke="#4a2a12" stroke-width="{3 if v%5==0 else 1.5}"/>'
    if v % 5 == 0:
        ticks += f'<text x="{185+90*math.sin(a):.1f}" y="{200-90*math.cos(a)+5:.1f}" text-anchor="middle" font-family="UB" font-size="13" fill="#4a2a12">{v}</text>'
an = -130 + (79.8 - 70) * (260 / 21)
ag = -130 + (81.6 - 70) * (260 / 21)
figC = hero + f'''<svg style="position:absolute;left:0;top:150px" width="370" height="520" viewBox="0 0 370 520">
<defs><radialGradient id="dl" cx="42%" cy="35%" r="75%"><stop offset="0" stop-color="#fffdf4"/><stop offset=".75" stop-color="#f2e3c2"/><stop offset="1" stop-color="#d4bd92"/></radialGradient>
<filter id="ds"><feDropShadow dx="0" dy="16" stdDeviation="14" flood-opacity=".4"/></filter></defs>
<g transform="translate(0 -20)"><circle cx="185" cy="200" r="150" fill="#2b1250" filter="url(#ds)"/>
<circle cx="185" cy="200" r="132" fill="url(#dl)"/>
{ticks}
<g transform="rotate({ag:.1f} 185 200)" opacity=".3"><rect x="182" y="84" width="6" height="120" rx="3" fill="#4a2a12"/></g>
<g transform="rotate({an:.1f} 185 200)"><rect x="181" y="76" width="8" height="132" rx="4" fill="#E8461E"/></g>
<circle cx="185" cy="200" r="16" fill="#2b1250"/></g>
<text x="185" y="250" text-anchor="middle" font-family="DejaVu Sans Mono" font-size="9" font-weight="700" fill="#4a2a12" letter-spacing="2">KG</text>
<text x="185" y="380" text-anchor="middle" font-family="DejaVu Sans Mono" font-size="8.5" fill="#fff" letter-spacing="1.5">FAINT NEEDLE = 8 WEEKS AGO (81.6)</text>
</svg>'''

html = head
html += col('A', 'FIGURINE', figA, 'A glossy vinyl-toy figure on a turntable, in the same cream as the jar blocks. It slims or broadens with the body fat and lean mass from your InBody scans, with a dashed outline of where you were 8 weeks ago. Drag the ruler to scrub through your weigh-ins and the figure morphs on a spring. Labelled schematic, not a scan.')
html += col('B', 'STACKS', figB, 'The same language as the DIET jar: each week is a stack of two chunky blocks, cream for lean mass and amber for fat, standing on a shelf. This week drops in with a thunk when a new weigh-in or scan arrives. The trend reads at a glance; tap a stack for that week’s numbers.')
html += col('C', 'DIAL', figC, 'A big bathroom-scale dial is the whole face. The red needle springs to today’s weight with a heavy wobble; a faint needle shows 8 weeks ago. Drag the ruler and the needle swings back through time. The number above counts with it.')
html += '</div></body></html>'
open(S + '/index.html', 'w').write(html)
