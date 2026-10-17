# Bakes the walnut grain the desk hourglass plates use (concept G in
# design/mockups/train/scene.py) into a square texture for the app.
#   python3 wood_texture.py <out.png> [size]
import bpy, math, sys

out = sys.argv[1]
size = int(sys.argv[2]) if len(sys.argv) > 2 else 512

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


me = bpy.data.meshes.new('plane')
me.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
plane = bpy.data.objects.new('plane', me)
scene.collection.objects.link(plane)
m = bpy.data.materials.new('walnut')
m.use_nodes = True
nt = m.node_tree
nt.nodes.remove(nt.nodes['Principled BSDF'])
coord = nt.nodes.new('ShaderNodeTexCoord')
wave = nt.nodes.new('ShaderNodeTexWave')
wave.inputs['Scale'].default_value = 1.6
wave.inputs['Distortion'].default_value = 4.0
wave.inputs['Detail'].default_value = 3.0
ramp = nt.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].color = lin(0x1E120C)
ramp.color_ramp.elements[1].color = lin(0x3A2316)
em = nt.nodes.new('ShaderNodeEmission')
nt.links.new(coord.outputs['Object'], wave.inputs['Vector'])
nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
nt.links.new(ramp.outputs['Color'], em.inputs['Color'])
nt.links.new(em.outputs['Emission'], nt.nodes['Material Output'].inputs['Surface'])
me.materials.append(m)

cam = bpy.data.cameras.new('cam')
cam.type = 'ORTHO'
cam.ortho_scale = 2
camo = bpy.data.objects.new('cam', cam)
scene.collection.objects.link(camo)
camo.location = (0, 0, 5)
scene.camera = camo

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.resolution_x = size
scene.render.resolution_y = size
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = out
scene.render.image_settings.file_format = 'PNG'
bpy.ops.render.render(write_still=True)
print('baked', out)
