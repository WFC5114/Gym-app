# Packs this folder into the published artifact's files (python3 pack_site.py <out dir>):
# the models and each tab's studio light as base64 JSON (the artifact serves no .glb or
# .hdr), the controls and the Night clay numerals.
import base64, glob, json, os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1])
RENDERED = os.path.join(HERE, '..', '..', '..', 'App', 'Resources', 'Rendered')
os.makedirs(OUT, exist_ok=True)
for n in ('jar', 'hourglass'):
    with open(os.path.join(HERE, n + '.glb'), 'rb') as f:
        json.dump({'format': 'glb-base64', 'glb': base64.b64encode(f.read()).decode()}, open(os.path.join(OUT, n + '.json'), 'w'))
for tab in ('food', 'rest', 'body'):
    with open(os.path.join(HERE, 'desk-env-%s.hdr' % tab), 'rb') as f:
        json.dump({'format': 'radiance-hdr-base64', 'hdr': base64.b64encode(f.read()).decode()}, open(os.path.join(OUT, 'env-%s.json' % tab), 'w'))
    shutil.copy(os.path.join(HERE, 'desk-backdrop-%s.jpg' % tab), OUT)
shutil.copy(os.path.join(HERE, 'desk.html'), OUT)
shutil.copy(os.path.join(HERE, 'ui', 'desk-ui.json'), OUT)
for p in glob.glob(os.path.join(HERE, 'ui', '*.png')):
    shutil.copy(p, OUT)          # the page stretches the sliced ones with a border image
for c in ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'colon', 'comma', 'period', 'minus', 'hyphen']:
    shutil.copy(os.path.join(RENDERED, 'night-glyph-%s@3x.png' % c), OUT)
print(len(os.listdir(OUT)), 'files in', OUT)
