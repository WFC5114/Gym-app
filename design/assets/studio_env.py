# Bakes the studio the mockups are lit by (design/mockups/train/scene.py) into an
# equirectangular environment for the app's RealityKit scene, so reflections on
# glass, glossy blocks and numerals match the renders. Softboxes become bright
# emissive panels around the object; everything else is a dim studio.
#   python3 studio_env.py <out.png> [width]
# Blender axes: the object sits at the origin, the viewer is at -y, z is up.
import bpy, math, sys
from mathutils import Vector

out = sys.argv[1]
width = int(sys.argv[2]) if len(sys.argv) > 2 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
col = scene.collection

world = bpy.data.worlds.new('w')
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.03, 0.033, 0.045, 1)
bg.inputs['Strength'].default_value = 1.0


def panel(name, loc, size, strength, warm=1.0):
    """A softbox: an emissive rectangle at `loc` facing the origin."""
    me = bpy.data.meshes.new(name)
    w, h = size
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('Z', 'Y').to_euler()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes['Principled BSDF'])
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (1.0, 0.97 * warm + 0.03, 0.92 * warm + 0.08, 1)
    em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs['Emission'], nt.nodes['Material Output'].inputs['Surface'])
    me.materials.append(m)


# Same placement as the mockup rig, scaled to sit on a sphere around the object.
panel('key', (-5, -7, 8), (5, 5), 1.0, warm=0.97)
panel('fill', (3, -10, 1), (8, 8), 0.42)
panel('rimL', (-3.2, -0.6, 0), (0.6, 6), 0.9)
panel('rimR', (3.2, -0.6, 0), (0.6, 6), 0.9)
panel('top', (0, -2, 6), (3, 3), 0.7)

# A dim floor so the lower half is not a void.
me = bpy.data.meshes.new('floor')
me.from_pydata([(-40, -40, -6), (40, -40, -6), (40, 40, -6), (-40, 40, -6)], [], [(0, 1, 2, 3)])
floor = bpy.data.objects.new('floor', me)
col.objects.link(floor)
fm = bpy.data.materials.new('floor')
fm.use_nodes = True
fm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.05, 0.05, 0.06, 1)
fm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
me.materials.append(fm)

cam = bpy.data.cameras.new('pano')
cam.type = 'PANO'
cam.panorama_type = 'EQUIRECTANGULAR'
camo = bpy.data.objects.new('pano', cam)
col.objects.link(camo)
# Centre of the panorama looks away from the viewer (+y), toward the face plate.
camo.rotation_euler = (math.pi / 2, 0, 0)
scene.camera = camo

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = width
scene.render.resolution_y = width // 2
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = out
scene.render.image_settings.file_format = 'PNG'
bpy.ops.render.render(write_still=True)
print('baked', out)
