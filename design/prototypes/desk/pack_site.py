# Packs this folder into the published artifact's files (python3 pack_site.py <out dir>):
# the models and studio light as base64 JSON (the artifact serves no .glb or
# .hdr), the controls split into caps and middle, and the Night clay numerals.
import base64, glob, json, os, shutil, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1])
RENDERED = os.path.join(HERE, '..', '..', '..', 'App', 'Resources', 'Rendered')
os.makedirs(OUT, exist_ok=True)
for n in ('jar', 'hourglass'):
    with open(os.path.join(HERE, n + '.glb'), 'rb') as f:
        json.dump({'format': 'glb-base64', 'glb': base64.b64encode(f.read()).decode()}, open(os.path.join(OUT, n + '.json'), 'w'))
with open(os.path.join(HERE, 'desk-env.hdr'), 'rb') as f:
    json.dump({'format': 'radiance-hdr-base64', 'hdr': base64.b64encode(f.read()).decode()}, open(os.path.join(OUT, 'env.json'), 'w'))
for f in ['desk.html', 'desk-backdrop.jpg']:
    shutil.copy(os.path.join(HERE, f), OUT)
shutil.copy(os.path.join(HERE, 'ui', 'desk-ui.json'), OUT)
ui = json.load(open(os.path.join(HERE, 'ui', 'desk-ui.json')))
for p in glob.glob(os.path.join(HERE, 'ui', '*.png')):
    name = os.path.basename(p)[:-len('@3x.png')]
    sp = ui['sprites'].get(name, {})
    if 'slice' not in sp:
        shutil.copy(p, OUT)
        continue
    im = Image.open(p)
    l, r = round(sp['slice'][1] * 3), round(sp['slice'][3] * 3)
    im.crop((0, 0, l, im.height)).save(os.path.join(OUT, name + '-l@3x.png'))
    im.crop((l, 0, im.width - r, im.height)).save(os.path.join(OUT, name + '-m@3x.png'))
    im.crop((im.width - r, 0, im.width, im.height)).save(os.path.join(OUT, name + '-r@3x.png'))
for c in ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'colon', 'comma', 'period', 'minus', 'hyphen']:
    shutil.copy(os.path.join(RENDERED, 'night-glyph-%s@3x.png' % c), OUT)
print(len(os.listdir(OUT)), 'files in', OUT)
