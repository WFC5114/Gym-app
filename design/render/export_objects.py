# Desk objects (Wei, 17 Oct 2026: "use jar and hourglass and be able to
# manipulate them in 3d space, rotate, shake"): builds the Night jar or
# hourglass exactly as night_diet.py / night_train.py do, then exports it alone,
# at the origin and upright, as a glTF binary for live 3D (the browser
# prototype, later RealityKit). The hourglass also writes its inner glass
# profile, which the sand simulation needs.
#   python3 export_objects.py jar|hourglass <out dir>
import os, sys, json, runpy, math

which, out = sys.argv[1], os.path.abspath(sys.argv[2])
os.makedirs(out, exist_ok=True)
os.environ['NIGHT_DRY'] = '1'            # build and lay out, render nothing
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
script = {'jar': 'night_diet.py', 'hourglass': 'night_train.py'}[which]
sys.argv = [script, os.path.join(out, 'scratch-' + which)]
ns = runpy.run_path(os.path.join(here, script), run_name='__main__')

import bpy
from mathutils import Quaternion

root = ns['jar'] if which == 'jar' else ns['pivot']
root.location = (0, 0, 0)
if which == 'jar':
    root.rotation_euler = (0, 0, 0)
else:
    root.rotation_quaternion = Quaternion()
    root.scale = (1, 1, 1)
bpy.context.view_layer.update()

keep = set(ns['tree'](root))
for o in list(bpy.data.objects):
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
# Text becomes mesh so the exporter keeps the raised lettering.
for o in list(bpy.data.objects):
    if o.type == 'FONT':
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.convert(target='MESH')

path = os.path.join(out, which + '.glb')
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True, export_yup=True,
                          export_materials='EXPORT', export_cameras=False, export_lights=False)
print('exported', path, os.path.getsize(path))

if which == 'hourglass':
    meta = dict(inner=[[round(z, 4), round(r, 4)] for z, r in ns['INNER_TOP']])
    with open(os.path.join(out, 'hourglass-profile.json'), 'w') as fh:
        json.dump(meta, fh)
