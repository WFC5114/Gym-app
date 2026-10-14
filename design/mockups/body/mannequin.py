# BODY mannequin, round 2: a hard, tall artist's mannequin (about eight heads),
# stylised like Not Boring's objects: invented, but dense with sculpted detail
# and strongly lit. Wei, 14 Oct: "mannequins are hard", "taller", "fake but
# highly detailed and 3d". Mockup only; not the app.
#   python3 mannequin.py <look> <out> [samples] [scale]            one still
#   python3 mannequin.py <look> <out dir> [samples] [scale] motion  frames
# look: beech | graphite
import bpy, bmesh, math, sys, os

LOOK = sys.argv[1]
OUT = os.path.abspath(sys.argv[2])
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 64
SCALE = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
MOTION = len(sys.argv) > 5 and sys.argv[5] == 'motion'
FRAMES, FPS = 120, 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def principled(name, color, rough, coat=0.0, metal=0.0, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Specular IOR Level'].default_value = spec
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = 0.06
    return m


def grain(m, light, dark, contrast=0.35, scale=(90, 90, 4)):
    """Fine, quiet grain along each part: a lacquered, idealised wood."""
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    coord = nt.nodes.new('ShaderNodeTexCoord')
    mapping = nt.nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = scale
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 1.0
    noise.inputs['Detail'].default_value = 4.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.5 - contrast / 2
    ramp.color_ramp.elements[0].color = lin(dark)
    ramp.color_ramp.elements[1].position = 0.5 + contrast / 2
    ramp.color_ramp.elements[1].color = lin(light)
    nt.links.new(coord.outputs['Object'], mapping.inputs['Vector'])
    nt.links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    return m


if LOOK == 'beech':
    body = grain(principled('body', 0xE0B887, 0.32, coat=0.5), 0xE6C190, 0xC99A62)
    jnt = grain(principled('joint', 0xD3A46D, 0.3, coat=0.5), 0xD9AA72, 0xB0814E)
    socket = principled('socket', 0x7A5434, 0.4, coat=0.3)
    backdrop = 0x6A30D0
else:  # graphite: satin black, like the Weather cloud
    body = principled('body', 0x1E1F23, 0.26, coat=0.6, spec=0.6)
    jnt = principled('joint', 0x2A2B30, 0.22, coat=0.7, spec=0.6)
    socket = principled('socket', 0x0D0D10, 0.45)
    backdrop = 0x7B3FE4
steel = principled('steel', 0xC2C5CC, 0.18, metal=1.0)
brass = principled('brass', 0xD9A54C, 0.2, metal=1.0)
walnut = grain(principled('walnut', 0x3A2316, 0.35, coat=0.45), 0x4C2F1C, 0x2A180E, contrast=0.5, scale=(4, 60, 60))
black = principled('black', 0x101114, 0.5)
engrave = principled('engrave', 0x0E0B08, 0.7)
plate = principled('plate', backdrop, 0.75)


def link(o, parent=None, mat=None, smooth=True):
    scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    if mat:
        o.data.materials.append(mat)
    if smooth and o.type == 'MESH':
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def empty(name, loc, parent=None):
    o = bpy.data.objects.new(name, None)
    scene.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    return o


def lathe(name, profile, segments=64):
    """Surface of revolution about z from (z, r) pairs, bottom to top."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / segments), r * math.sin(2 * math.pi * k / segments), z))
              for k in range(segments)] for z, r in profile]
    for i in range(len(rings) - 1):
        for k in range(segments):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % segments], rings[i + 1][(k + 1) % segments], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def spindle(name, length, r_top, r_bot, bulge=0.0, peak=0.3, cup=0.0):
    """A turned limb hanging from z 0 to -length: rounded ends, a muscle swell
    near the top, and a shallow socket lip at each end."""
    prof = []
    n = 28
    for i in range(n + 1):
        t = i / n                          # 0 at the bottom, 1 at the top
        base = r_bot + (r_top - r_bot) * t
        swell = bulge * math.exp(-((t - (1 - peak)) / 0.28) ** 2)
        end = min(t, 1 - t) / 0.08
        cap = math.sqrt(max(0.0, 1 - (1 - min(end, 1)) ** 2))
        prof.append((-length + length * t, max((base + swell) * cap, 1e-4)))
    o = lathe(name, prof)
    return o


def ellipsoid(name, rx, ry, rz):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=32, radius=1.0)
    for v in bm.verts:
        v.co.x *= rx
        v.co.y *= ry
        v.co.z *= rz
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def shaped(name, w, d, h, top=1.0, bottom=1.0, front=0.0, bevel=0.02, sub=2):
    """A sculpted block: tapered top to bottom, with an optional forward bulge."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    for v in bm.verts:
        u = (v.co.z + 1) / 2
        s = bottom + (top - bottom) * u
        v.co.x *= w * s
        v.co.y *= d * (0.9 + 0.1 * s)
        if v.co.y < 0:
            v.co.y -= front * d * (1 - v.co.x ** 2 / max(w * w, 1e-6)) * math.sin(math.pi * u)
        v.co.z *= h
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bv = o.modifiers.new('bevel', 'BEVEL')
    bv.width = bevel
    bv.segments = 4
    sd = o.modifiers.new('sub', 'SUBSURF')
    sd.levels = sd.render_levels = sub
    return o


def ring(name, r, z, parent, width=0.004, depth=0.003):
    """A socket lip: a thin dark band where a limb meets its ball."""
    o = link(lathe(name, [(z - width / 2, r), (z - width / 2, r + depth), (z + width / 2, r + depth), (z + width / 2, r)]), parent, socket)
    return o


def ball(name, r, parent, pins=False):
    b = link(ellipsoid(name, r, r, r), parent, jnt)
    if pins:
        for x in (-1, 1):
            p = link(lathe(name + 'Pin', [(0, 1e-4), (0, r * 0.3), (r * 0.08, r * 0.3), (r * 0.16, 1e-4)], 32), parent, steel)
            p.location = (x * r * 0.96, 0, 0)
            p.rotation_euler = (0, x * math.pi / 2, 0)
            slot = link(shaped(name + 'Slot', r * 0.24, r * 0.025, r * 0.025, bevel=0, sub=0), p, socket, smooth=False)
            slot.location = (0, 0, r * 0.15)
    return b


# ---------------------------------------------------------------------------
# Figure, about 1.0 tall, feet at z 0. Forward kinematics on empties.
# ---------------------------------------------------------------------------
turn = empty('turn', (0, 0, 0))
pelvis = empty('pelvis', (0, 0, 0.5), turn)
abdomen = empty('abdomen', (0, 0, 0.065), pelvis)
chest = empty('chest', (0, 0, 0.035), abdomen)
neck = empty('neck', (0, 0, 0.215), chest)
head = empty('head', (0, 0, 0.03), neck)

link(shaped('pelvisBlock', 0.072, 0.046, 0.036, top=1.0, bottom=0.7, front=0.25, bevel=0.016), pelvis, body).location = (0, 0, 0.0)
ball('abdomenBall', 0.042, abdomen)
ring('abdTop', 0.03, 0.035, abdomen)
torso = link(shaped('rib', 0.085, 0.054, 0.092, top=1.12, bottom=0.56, front=0.5, bevel=0.034), chest, body)
torso.location = (0, 0, 0.105)
ball('neckBall', 0.022, neck)
link(spindle('neckRod', 0.035, 0.016, 0.019), neck, body).location = (0, 0, 0.04)
link(ellipsoid('skull', 0.047, 0.055, 0.066), head, body).location = (0, -0.004, 0.07)
link(ellipsoid('jaw', 0.036, 0.04, 0.03), head, body).location = (0, -0.018, 0.03)

limbs = {}
for side, x in (('L', 1), ('R', -1)):
    sh = empty('shoulder' + side, (x * 0.1, 0, 0.17), chest)
    ball('shoulderBall' + side, 0.028, sh)
    link(spindle('upperArm' + side, 0.15, 0.022, 0.017, bulge=0.004), sh, body).location = (0, 0, -0.02)
    el = empty('elbow' + side, (0, 0, -0.17), sh)
    ball('elbowBall' + side, 0.019, el, pins=True)
    link(spindle('forearm' + side, 0.145, 0.018, 0.013, bulge=0.003), el, body).location = (0, 0, -0.016)
    wr = empty('wrist' + side, (0, 0, -0.165), el)
    ball('wristBall' + side, 0.012, wr)
    hand = link(shaped('hand' + side, 0.0075, 0.017, 0.032, top=0.85, bottom=1.0, bevel=0.006), wr, body)
    hand.location = (0, 0, -0.04)
    thumb = link(spindle('thumb' + side, 0.03, 0.006, 0.005), wr, body)
    thumb.location = (x * -0.006, -0.012, -0.018)
    thumb.rotation_euler = (0.5, 0, 0)

    hip = empty('hip' + side, (x * 0.045, 0, -0.04), pelvis)
    ball('hipBall' + side, 0.03, hip)
    link(spindle('thigh' + side, 0.205, 0.03, 0.021, bulge=0.005), hip, body).location = (0, 0, -0.022)
    kn = empty('knee' + side, (0, 0, -0.228), hip)
    ball('kneeBall' + side, 0.022, kn, pins=True)
    link(spindle('shin' + side, 0.19, 0.022, 0.015, bulge=0.004, peak=0.25), kn, body).location = (0, 0, -0.018)
    an = empty('ankle' + side, (0, 0, -0.21), kn)
    ball('ankleBall' + side, 0.014, an)
    foot = link(shaped('foot' + side, 0.02, 0.045, 0.011, top=0.8, bottom=1.0, bevel=0.008), an, body)
    foot.location = (0, -0.022, -0.012)
    limbs[side] = (sh, el, wr, hip, kn, an)

# ---------------------------------------------------------------------------
# Turntable with the stand rod into the back of the pelvis.
# ---------------------------------------------------------------------------
link(lathe('disc', [(-0.04, 1e-4), (-0.04, 0.24), (-0.037, 0.245), (-0.004, 0.245), (0, 0.24), (0, 1e-4)], 128), turn, walnut)
bm = bmesh.new()
n = 256
outer = [bm.verts.new(((0.252 if k % 2 else 0.256) * math.cos(2 * math.pi * k / n),
                       (0.252 if k % 2 else 0.256) * math.sin(2 * math.pi * k / n), -0.029)) for k in range(n)]
inner = [bm.verts.new((0.244 * math.cos(2 * math.pi * k / n), 0.244 * math.sin(2 * math.pi * k / n), -0.029)) for k in range(n)]
for k in range(n):
    bm.faces.new((inner[k], outer[k], outer[(k + 1) % n], inner[(k + 1) % n]))
g = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
bmesh.ops.translate(bm, vec=(0, 0, 0.014), verts=[v for v in g['geom'] if isinstance(v, bmesh.types.BMVert)])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
me = bpy.data.meshes.new('bezel')
bm.to_mesh(me)
bm.free()
link(bpy.data.objects.new('bezel', me), turn, brass, smooth=False)
for k in range(72):
    a = 2 * math.pi * k / 72
    L = 0.022 if k % 6 == 0 else 0.011
    t = link(shaped('tick', 0.0007, L / 2, 0.0004, bevel=0, sub=0), turn, engrave, smooth=False)
    r = 0.232 - L / 2
    t.location = (r * math.sin(a), -r * math.cos(a), 0.0003)
    t.rotation_euler = (0, 0, a)
rod = link(lathe('rod', [(0, 1e-4), (0, 0.0045), (0.445, 0.0045), (0.445, 1e-4)], 24), turn, steel)
rod.location = (0, 0.075, 0)
rod.rotation_euler = (math.atan2(0.05, 0.445), 0, 0)
link(lathe('collar', [(0, 1e-4), (0, 0.016), (0.005, 0.016), (0.012, 0.008), (0.03, 0.007), (0.03, 1e-4)], 48), turn, brass).location = (0, 0.075, 0)
link(lathe('plinth', [(-0.075, 1e-4), (-0.075, 0.225), (-0.072, 0.23), (-0.044, 0.23), (-0.04, 0.225), (-0.04, 1e-4)], 128), None, black)

bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 1.0, 0.5), rotation=(math.pi / 2, 0, 0))
bpy.context.object.data.materials.append(plate)
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.075))
bpy.context.object.data.materials.append(plate)

# Strong, graphic studio light: a crisp key, a weak fill, hard rims.
aim = empty('aim', (0, 0, 0.5))


def area(name, loc, size, energy, size_y=None, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy, d.color, d.shape = energy, color, 'RECTANGLE'
    d.size, d.size_y = size, size_y or size
    o = bpy.data.objects.new(name, d)
    scene.collection.objects.link(o)
    o.location = loc
    o.constraints.new('TRACK_TO').target = aim
    return o


key_e = 55 if LOOK == 'beech' else 110
area('key', (-1.3, -1.7, 2.2), 0.9, key_e, color=(1.0, 0.97, 0.92))
area('fill', (1.8, -1.4, 0.7), 2.0, 14, color=(0.85, 0.9, 1.0))
area('rimL', (-1.1, 0.9, 1.3), 0.12, 70 if LOOK == 'beech' else 140, size_y=2.4)
area('rimR', (1.1, 0.9, 1.3), 0.12, 70 if LOOK == 'beech' else 140, size_y=2.4)
area('top', (0, -0.2, 2.6), 0.8, 18)

world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.04, 0.035, 0.06, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.25
scene.world = world

cam_d = bpy.data.cameras.new('cam')
cam_d.type = 'ORTHO'
cam_d.ortho_scale = 1.22
cam = bpy.data.objects.new('cam', cam_d)
scene.collection.objects.link(cam)
cam.rotation_euler = (math.radians(80), 0, 0)
cam.location = (0, -4, 0.47 + 4 * math.tan(math.radians(10)))
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = int(720 * SCALE)
scene.render.resolution_y = int(1000 * SCALE)
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'


# ---------------------------------------------------------------------------
# Pose and motion: rigid joints only, each angle on a damped spring.
# ---------------------------------------------------------------------------
class Spring:
    def __init__(self, m, k, c, x=0.0):
        self.m, self.k, self.c, self.x, self.v, self.target = m, k, c, x, 0.0, x

    def step(self, dt):
        a = (-self.k * (self.x - self.target) - self.c * self.v) / self.m
        self.v += a * dt
        self.x += self.v * dt


flex = Spring(1.0, 140, 13)   # 0 rest, 1 right arm up in a flex
look = Spring(1.2, 60, 10)
spin = Spring(2.0, 40, 12)


def pose(T, f):
    breathe = math.sin(2 * math.pi * T / 2.2)
    shift = math.sin(2 * math.pi * T / 4.4)
    fl = flex.x
    turn.rotation_euler = (0, 0, -0.42 + spin.x)
    # Contrapposto: weight on the left leg, hips tilt, shoulders counter.
    pelvis.rotation_euler = (0, 0.03 + shift * 0.02, 0.05)
    abdomen.rotation_euler = (breathe * 0.012, -0.05 - shift * 0.02, -0.03)
    chest.rotation_euler = (-breathe * 0.02, -0.03 - shift * 0.015, -0.03)
    neck.rotation_euler = (0.04, 0.02, look.x * 0.5)
    head.rotation_euler = (-0.05 + breathe * 0.01, 0.03, look.x * 0.5)
    sh, el, wr, hip, kn, an = limbs['L']
    sh.rotation_euler = (0.08, 0.1, 0)
    el.rotation_euler = (-0.25, 0, 0)
    wr.rotation_euler = (0, 0.1, 0)
    hip.rotation_euler = (-0.02, -0.06 - shift * 0.02, 0)
    kn.rotation_euler = (0.03, 0, 0)
    an.rotation_euler = (0, 0.04, 0)
    sh, el, wr, hip, kn, an = limbs['R']
    # Right arm: hangs, or rises into a flex when touched.
    sh.rotation_euler = (0.05 - fl * 0.2, -0.12 - fl * 1.45, 0)
    el.rotation_euler = (-0.3 - fl * 1.9, 0, 0)
    wr.rotation_euler = (-fl * 0.3, 0, 0)
    hip.rotation_euler = (-0.12, 0.1 - shift * 0.02, 0)
    kn.rotation_euler = (0.24, 0, 0)
    an.rotation_euler = (-0.12, -0.06, 0)


if not MOTION:
    pose(0.0, 1)
    scene.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    sys.exit(0)

os.makedirs(OUT, exist_ok=True)
TAP = 1.4
dt = 1 / 240
t = 0.0
for f in range(1, FRAMES + 1):
    T = (f - 1) / FPS
    while t < T:
        look.target = -0.5 if 0.4 < t < TAP else 0.0
        flex.target = 1.0 if TAP < t < TAP + 1.3 else 0.0
        spin.target = 0.35 if TAP < t < TAP + 0.15 else 0.0
        for s in (flex, look, spin):
            s.step(dt)
        t += dt
    pose(T, f)
    scene.frame_set(f)
    scene.render.filepath = os.path.join(OUT, 'f%04d.png' % f)
    bpy.ops.render.render(write_still=True)
    print('frame', f, flush=True)
