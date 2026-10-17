# Desk objects (Wei, 17 Oct 2026: "use jar and hourglass and be able to
# manipulate them in 3d space, rotate, shake"): builds the Night jar or
# hourglass exactly as night_diet.py / night_train.py do, then exports it alone,
# at the origin and upright, as a glTF binary for live 3D (the browser
# prototype, later RealityKit). The hourglass also writes its inner glass
# profile, which the sand simulation needs.
# Wei (17 Oct, on the first prototype: "looks less good as if not baked in"):
# the clay parts carry Cycles ambient occlusion baked into a colour attribute
# (COLOR_0), the part of the lighting that stays true however the object is
# turned. The live renderer multiplies its ambient light by it.
#   python3 export_objects.py jar|hourglass <out dir> [ao samples]
import os, sys, json, runpy, math

which, out = sys.argv[1], os.path.abspath(sys.argv[2])
ao_samples = int(sys.argv[3]) if len(sys.argv) > 3 else 128
os.makedirs(out, exist_ok=True)
os.environ['NIGHT_DRY'] = '1'            # build and lay out, render nothing
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
script = {'jar': 'night_diet.py', 'hourglass': 'night_train.py'}[which]
sys.argv = [script, os.path.join(out, 'scratch-' + which)]
ns = runpy.run_path(os.path.join(here, script), run_name='__main__')

import bpy
from mathutils import Quaternion, Vector

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

# Bake the occlusion. Modifiers are applied first: a colour attribute belongs
# to the final mesh. Glass is left out of the bake both ways (it neither
# darkens the clay behind it nor gets darkened), and keeps a white attribute.
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.convert(target='MESH')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
glassy = lambda o: any(m and 'glass' in m.name.lower() for m in o.data.materials)
clay_parts = [o for o in meshes if not glassy(o)]
for o in meshes:
    if o.data.users > 1:
        o.data = o.data.copy()
    a = o.data.color_attributes.new('AO', 'BYTE_COLOR', 'POINT')   # per vertex: no seams for the simplifier
    a.data.foreach_set('color', [1.0] * (4 * len(a.data)))
    o.data.color_attributes.active_color = a
    o.data.color_attributes.render_color_index = o.data.color_attributes.active_color_index
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = ao_samples
scene.render.bake.target = 'VERTEX_COLORS'
zs = [(o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box]
scene.world.light_settings.distance = 0.12 * (max(zs) - min(zs))   # crevices, not whole sides
for o in meshes:
    o.hide_render = glassy(o)
bpy.ops.object.select_all(action='DESELECT')
for o in clay_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = clay_parts[0]
bpy.ops.object.bake(type='AO')
for o in meshes:
    o.hide_render = False
print('baked AO on', len(clay_parts), 'parts, distance', round(scene.world.light_settings.distance, 4))

path = os.path.join(out, which + '.glb')
bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True, export_yup=True,
                          export_materials='EXPORT', export_cameras=False, export_lights=False,
                          export_vertex_color='ACTIVE', export_all_vertex_colors=False)
print('exported', path, os.path.getsize(path))

if which == 'hourglass':
    meta = dict(inner=[[round(z, 4), round(r, 4)] for z, r in ns['INNER_TOP']])
    with open(os.path.join(out, 'hourglass-profile.json'), 'w') as fh:
        json.dump(meta, fh)

# DESK_REF=1: also render the object as the desk prototype frames it, in Cycles
# on the desk studio (desk_studio.py), the picture the live view is matched to.
if os.environ.get('DESK_REF'):
    import desk_studio as ds
    height = {'jar': 0.5 * 0.96, 'hourglass': 0.5 * 1.05}[which]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    s = height / (hi.z - lo.z)
    root.scale = root.scale * s
    root.location = -(lo + hi) / 2 * s + Vector((0, 0, ds.DESK + height / 2))   # standing on the desk
    bpy.context.view_layer.update()
    ds.studio_render_settings(scene, 96)
    ds.desk(scene)
    ds.lights(scene)
    ds.camera(scene, height=1000)
    scene.render.image_settings.file_format = 'JPEG'
    scene.render.image_settings.quality = 92
    scene.render.filepath = os.path.join(out, which + '-reference.jpg')
    bpy.ops.render.render(write_still=True)
    print('reference', scene.render.filepath)
