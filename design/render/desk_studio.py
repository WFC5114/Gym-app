# The desk the live objects stand on (Wei, 17 Oct 2026, on the first desk
# prototype: "looks less good as if not baked in"). Everything that never moves
# is rendered here in Cycles and only shown by the live view:
#   desk-backdrop.jpg  the graphite clay desk with its engraved ring, from the
#                      live view's camera, light pooled where the object stands
#   desk-env.hdr       the studio seen from the object (key light left out),
#                      the live view's ambient light and reflections
# The live view adds what moves: the objects (their creases carry baked
# occlusion, export_objects.py), the key light and the shadows it casts.
#
# Units are the live view's: the object is scaled to 0.5 tall and centred on the
# origin (three.js, y up); here Blender's z is up and three's z is Blender's -y.
# Wei (17 Oct, on v2: "slightly ugly since it's all gray and black and white, I
# want some color but mature"): each tab has its own desk, a deep jewel-toned
# clay (TABS), and its own studio light, which carries the desk's colour.
#   python3 desk_studio.py <out dir> [samples] [tab ...]
import bpy, bmesh, math, os, sys
from mathutils import Vector

DESK = -0.254                     # the desk's top, just under the object
FOV, PITCH, DIST = 28.0, 15.0, 3.51
TARGET = (0.0, -0.02, 0.0)        # three.js
ASPECT = 0.62                     # the backdrop; narrower phones crop its sides
RING_R, RING_W = 0.36, 0.006
TABS = {'food': 0x0B5A45, 'rest': 0x1B3290, 'body': 0x5C1C60}   # pine, ink indigo, aubergine
WALL_Y, SWEEP_R = 1.9, 0.6       # the coloured desks curve up into a wall behind (Blender y)


def b(x, y, z):
    """three.js to Blender."""
    return Vector((x, -z, y))


def camera_three():
    p = math.radians(PITCH)
    return (TARGET[0], TARGET[1] + DIST * math.sin(p), TARGET[2] + DIST * math.cos(p))


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def desk_material(color=0x211F24, floor=0.0, wall=False):
    """Pressed clay (the Night tray's by default), its light pooled round the
    object; away from it, it falls to `floor` of its light (0: into the night).
    The wall's light falls with height instead."""
    m = bpy.data.materials.new('desk')
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.7
    bsdf.inputs['Coat Weight'].default_value = 0.03
    bsdf.inputs['Coat Roughness'].default_value = 0.25
    bsdf.inputs['Subsurface Weight'].default_value = 0.12
    bsdf.inputs['Subsurface Radius'].default_value = (0.05, 0.03, 0.02)
    bsdf.inputs['Subsurface Scale'].default_value = 0.02
    coord = nt.nodes.new('ShaderNodeTexCoord')
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 180.0
    noise.inputs['Detail'].default_value = 6.0
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.08
    bump.inputs['Distance'].default_value = 0.0003
    nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
    nt.links.new(noise.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    # A broad, faint mottling, like pressed clay that was worked by hand.
    mott = nt.nodes.new('ShaderNodeTexNoise')
    mott.inputs['Scale'].default_value = 3.0
    mott.inputs['Detail'].default_value = 2.0
    nt.links.new(coord.outputs['Object'], mott.inputs['Vector'])
    tone = nt.nodes.new('ShaderNodeMapRange')
    tone.inputs['To Min'].default_value = 0.36
    tone.inputs['To Max'].default_value = 0.48
    nt.links.new(mott.outputs['Fac'], tone.inputs['Value'])
    # Darker away from the object: the desk falls into the night (or the wall
    # darkens as it rises).
    dist = nt.nodes.new('ShaderNodeVectorMath')
    fall = nt.nodes.new('ShaderNodeMapRange')
    fall.interpolation_type = 'SMOOTHERSTEP'
    if wall:
        dist.operation = 'DOT_PRODUCT'
        dist.inputs[1].default_value = (0, 0, 1)
        fall.inputs['From Min'].default_value = DESK + 0.1
        fall.inputs['From Max'].default_value = DESK + 1.5
        fall.inputs['To Min'].default_value = 0.95
    else:
        dist.operation = 'LENGTH'
        fall.inputs['From Min'].default_value = 0.9
        fall.inputs['From Max'].default_value = 4.5
        fall.inputs['To Min'].default_value = 1.0
    fall.inputs['To Max'].default_value = floor
    nt.links.new(coord.outputs['Object'], dist.inputs[0])
    nt.links.new(dist.outputs['Value'], fall.inputs['Value'])
    mul = nt.nodes.new('ShaderNodeMath')
    mul.operation = 'MULTIPLY'
    nt.links.new(tone.outputs['Result'], mul.inputs[0])
    nt.links.new(fall.outputs['Result'], mul.inputs[1])
    col = nt.nodes.new('ShaderNodeMix')
    col.data_type = 'RGBA'
    col.blend_type = 'MULTIPLY'
    col.inputs['Factor'].default_value = 1.0
    col.inputs['A'].default_value = lin(color)
    nt.links.new(mul.outputs['Value'], col.inputs['B'])
    nt.links.new(col.outputs['Result'], bsdf.inputs['Base Color'])
    # ...its sheen and gloss too, so the far desk has no edge against the night.
    black = nt.nodes.new('ShaderNodeBsdfDiffuse')
    black.inputs['Color'].default_value = (0, 0, 0, 1)
    gone = nt.nodes.new('ShaderNodeMath')
    gone.operation = 'SUBTRACT'
    gone.inputs[0].default_value = 1.0
    nt.links.new(fall.outputs['Result'], gone.inputs[1])
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(gone.outputs['Value'], mix.inputs['Fac'])
    nt.links.new(bsdf.outputs['BSDF'], mix.inputs[1])
    nt.links.new(black.outputs['BSDF'], mix.inputs[2])
    nt.links.new(mix.outputs['Shader'], nt.nodes['Material Output'].inputs['Surface'])
    return m


def sweep(scene, color):
    """The coloured desks' wall: the desk curves up behind the object like a
    photographer's paper sweep, darker the higher it goes."""
    bm = bmesh.new()
    prof = []
    for i in range(25):
        a = -math.pi / 2 + math.pi / 2 * i / 24
        prof.append((WALL_Y - SWEEP_R + SWEEP_R * math.cos(a), DESK + 0.0005 + SWEEP_R + SWEEP_R * math.sin(a)))
    prof.append((WALL_Y, DESK + 4.0))
    rows = [[bm.verts.new((x, y, z)) for (y, z) in prof] for x in (-30.0, 30.0)]
    for i in range(len(prof) - 1):
        bm.faces.new((rows[0][i], rows[1][i], rows[1][i + 1], rows[0][i + 1]))   # facing the object
    me = bpy.data.meshes.new('sweep')
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new('sweep', me)
    scene.collection.objects.link(o)
    o.data.materials.append(desk_material(color, floor=0.15, wall=True))
    return o


def desk(scene, color=0x211F24, wall=False):
    """A big clay slab with a ring pressed into it where the object stands,
    ticked like a measuring mat; with `wall`, it curves up behind."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 60
        v.co.y *= 60
        v.co.z = DESK - 0.05 + v.co.z * 0.1
    me = bpy.data.meshes.new('desk')
    bm.to_mesh(me)
    bm.free()
    slab = bpy.data.objects.new('desk', me)
    scene.collection.objects.link(slab)
    slab.data.materials.append(desk_material(color, floor=0.62 if wall else 0.0))
    if wall:
        sweep(scene, color)

    # the cutter: a groove ring and short ticks outside it, joined into one
    parts = []

    def cutter(name, mesh):
        o = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(o)
        parts.append(o)
        return o

    for r_out, r_in in ((RING_R + RING_W / 2, RING_R - RING_W / 2),):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=False, segments=256, radius=r_out)
        bmesh.ops.create_circle(bm, cap_ends=False, segments=256, radius=r_in)
        edges = bm.edges[:]
        bmesh.ops.bridge_loops(bm, edges=edges)
        geom = bm.faces[:]
        ext = bmesh.ops.extrude_face_region(bm, geom=geom)
        for v in [e for e in ext['geom'] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z -= 0.02
        for v in bm.verts:
            v.co.z += DESK + 0.01
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new('ring')
        bm.to_mesh(me)
        bm.free()
        cutter('ring', me)
    for i in range(72):
        a = i / 72 * math.tau
        long = i % 6 == 0
        ln = 0.026 if long else 0.014
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co.x = v.co.x * ln + RING_R + RING_W + 0.012 + ln / 2
            v.co.y *= 0.0032 if long else 0.0024
            v.co.z = v.co.z * 0.02 + DESK
        bmesh.ops.rotate(bm, verts=bm.verts[:], cent=(0, 0, 0), matrix=__import__('mathutils').Matrix.Rotation(a, 3, 'Z'))
        me = bpy.data.meshes.new('tick')
        bm.to_mesh(me)
        bm.free()
        cutter('tick', me)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    cut = parts[0]
    cut.hide_render = True
    cut.hide_viewport = True
    mod = slab.modifiers.new('engrave', 'BOOLEAN')
    mod.operation, mod.object, mod.solver = 'DIFFERENCE', cut, 'EXACT'
    # the groove's edges softened, as if pressed with a rounded tool
    bv = slab.modifiers.new('soften', 'BEVEL')
    bv.width, bv.segments, bv.limit_method = 0.0016, 3, 'ANGLE'
    for p in slab.data.polygons:
        p.use_smooth = False
    return slab


def lights(scene, with_key=True):
    """The Night studio (night_kit.py), aimed at the object; the low rim that sat
    under the face's objects is lifted above the desk."""
    aim = bpy.data.objects.new('deskAim', None)
    scene.collection.objects.link(aim)
    out = {}
    for name, loc, size, energy, size_y, color in (
            ('key', (-2.2, -3.0, 3.0), 3.0, 230, None, (1.0, 0.97, 0.93)),
            ('fill', (2.6, -2.8, 0.4), 4.0, 80, None, (0.92, 0.94, 1.0)),
            ('rimL', (-1.8, 0.2, 1.4), 0.8, 60, 3.0, (1, 1, 1)),
            ('rimR', (1.8, 0.2, 0.6), 0.8, 45, 3.0, (1, 1, 1)),
            ('top', (0, -1.2, 3.4), 2.0, 60, None, (1, 1, 1))):
        if name == 'key' and not with_key:
            continue
        d = bpy.data.lights.new('desk-' + name, 'AREA')
        d.energy, d.color, d.shape = energy, color, 'RECTANGLE'
        d.size, d.size_y = size, size_y or size
        o = bpy.data.objects.new('desk-' + name, d)
        scene.collection.objects.link(o)
        o.location = loc
        o.constraints.new('TRACK_TO').target = aim
        out[name] = o
    w = bpy.data.worlds.new('deskWorld')
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.18, 0.18, 0.2, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
    scene.world = w
    w.cycles_visibility.camera = False          # the night behind the desk is black
    return out


def camera(scene, aspect=ASPECT, height=2000):
    d = bpy.data.cameras.new('deskCam')
    d.type = 'PERSP'
    d.sensor_fit = 'VERTICAL'
    d.angle_y = math.radians(FOV)
    d.clip_start, d.clip_end = 0.05, 60
    c = bpy.data.objects.new('deskCam', d)
    scene.collection.objects.link(c)
    c.location = b(*camera_three())
    c.rotation_euler = (b(*TARGET) - c.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = c
    scene.render.resolution_y = height
    scene.render.resolution_x = round(height * aspect)
    return c


def studio_render_settings(scene, samples):
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.transparent_max_bounces = 16
    scene.cycles.transmission_bounces = 12
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Base Contrast'


def render_tab(out, samples, tab):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    studio_render_settings(scene, samples)
    desk(scene, TABS[tab], wall=True)
    ls = lights(scene)
    camera(scene)
    scene.render.image_settings.file_format = 'JPEG'
    scene.render.image_settings.quality = 90
    scene.render.filepath = os.path.join(out, 'desk-backdrop-%s.jpg' % tab)
    bpy.ops.render.render(write_still=True)
    print('rendered backdrop', tab, flush=True)

    # The studio from the object, for the live view's ambient light: the key is
    # the live light (it casts the shadows), so it is left out here. The other
    # lights are seen as the glowing panels they are.
    ls['key'].hide_render = True
    for o in ls.values():
        o.visible_camera = True
    pano = bpy.data.cameras.new('pano')
    pano.type = 'PANO'
    pano.panorama_type = 'EQUIRECTANGULAR'
    pc = bpy.data.objects.new('pano', pano)
    scene.collection.objects.link(pc)
    pc.location = (0, 0, 0)
    pc.rotation_euler = (math.radians(90), 0, math.radians(-90))
    scene.camera = pc
    scene.render.resolution_x, scene.render.resolution_y = 768, 384
    scene.cycles.samples = max(32, samples // 2)
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.image_settings.file_format = 'HDR'
    scene.render.filepath = os.path.join(out, 'desk-env-%s.hdr' % tab)
    bpy.ops.render.render(write_still=True)
    print('rendered env', tab, flush=True)


if __name__ == '__main__':
    out = os.path.abspath(sys.argv[1])
    samples = int(sys.argv[2]) if len(sys.argv) > 2 else 128
    os.makedirs(out, exist_ok=True)
    for tab in sys.argv[3:] or list(TABS):
        render_tab(out, samples, tab)
