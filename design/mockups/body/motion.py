# BODY motion test: a detailed wooden artist's mannequin (the IKEA-style
# jointed beech figure Wei likes) with idle life and a squash-and-bounce when
# touched. Not the app; a direction test for Wei ("figures feel soulless",
# "their models are extremely high quality and detailed").
#   python3 motion.py <out dir> [frames] [samples] [scale] [first frame]
# Writes PNG frames <out dir>/f0001.png ...; join them with ffmpeg.
import bpy, bmesh, math, sys, os

out = os.path.abspath(sys.argv[1])
FRAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 120
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 48
SCALE = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
FIRST = int(sys.argv[5]) if len(sys.argv) > 5 else 1
FPS = 30
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def principled(name, color, rough, coat=0.0, metal=0.0, sss=0.0, bump=0.0, bump_scale=300.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = 0.1
    if sss:
        b.inputs['Subsurface Weight'].default_value = sss
        b.inputs['Subsurface Radius'].default_value = (0.06, 0.04, 0.03)
        b.inputs['Subsurface Scale'].default_value = 0.04
    if bump:
        noise = nt.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = bump_scale
        bn = nt.nodes.new('ShaderNodeBump')
        bn.inputs['Strength'].default_value = bump
        bn.inputs['Distance'].default_value = 0.002
        nt.links.new(noise.outputs['Fac'], bn.inputs['Height'])
        nt.links.new(bn.outputs['Normal'], b.inputs['Normal'])
    return m


def walnut_material():
    m = principled('walnut', 0x3A2316, 0.48, coat=0.2)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    coord = nt.nodes.new('ShaderNodeTexCoord')
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.inputs['Scale'].default_value = 3.0
    wave.inputs['Distortion'].default_value = 5.0
    wave.inputs['Detail'].default_value = 4.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = lin(0x24150D)
    ramp.color_ramp.elements[1].color = lin(0x4A2D1B)
    nt.links.new(coord.outputs['Object'], wave.inputs['Vector'])
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    return m


def beech_material(name, light, dark):
    """Lacquered beech: long streaks along the part, faint growth rings, pores."""
    m = principled(name, light, 0.5, coat=0.18)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    coord = nt.nodes.new('ShaderNodeTexCoord')
    mapping = nt.nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = (70, 70, 5)
    streak = nt.nodes.new('ShaderNodeTexNoise')
    streak.inputs['Scale'].default_value = 1.0
    streak.inputs['Detail'].default_value = 6.0
    streak.inputs['Distortion'].default_value = 0.6
    rings = nt.nodes.new('ShaderNodeTexWave')
    rings.wave_type = 'RINGS'
    rings.inputs['Scale'].default_value = 9.0
    rings.inputs['Distortion'].default_value = 3.0
    mix = nt.nodes.new('ShaderNodeMath')
    mix.operation = 'MULTIPLY_ADD'
    mix.inputs[1].default_value = 0.25
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = lin(dark)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = lin(light)
    pores = nt.nodes.new('ShaderNodeTexNoise')
    pores.inputs['Scale'].default_value = 900
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.05
    bump.inputs['Distance'].default_value = 0.002
    nt.links.new(coord.outputs['Object'], mapping.inputs['Vector'])
    nt.links.new(mapping.outputs['Vector'], streak.inputs['Vector'])
    nt.links.new(coord.outputs['Object'], rings.inputs['Vector'])
    nt.links.new(rings.outputs['Fac'], mix.inputs[0])
    nt.links.new(streak.outputs['Fac'], mix.inputs[2])
    nt.links.new(mix.outputs['Value'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], b.inputs['Base Color'])
    nt.links.new(pores.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    return m


vinyl = beech_material('beech', 0xDDB27C, 0xB27E4B)
joint = beech_material('beechJoint', 0xCFA06A, 0x9E6C3E)
steel = principled('steel', 0xB9BCC2, 0.28, metal=1.0)
brass = principled('brass', 0xD9A54C, 0.22, metal=1.0)
black = principled('black', 0x111215, 0.62)
engrave = principled('engrave', 0x1A1410, 0.7)
plate_mat = principled('plate', 0x6A30D0, 0.72)
walnut = walnut_material()


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
    o.empty_display_size = 0.03
    scene.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    return o


def lathe(name, profile, segments=48):
    """Surface of revolution about z from (z, r) pairs, bottom to top."""
    bm = bmesh.new()
    rings = []
    for z, r in profile:
        ring = []
        for k in range(segments):
            a = 2 * math.pi * k / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segments):
            a, b = rings[i][k], rings[i][(k + 1) % segments]
            c, d = rings[i + 1][(k + 1) % segments], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def capsule(name, length, r0, r1, steps=10):
    """A tapered limb hanging down from z 0 to -length, domed at both ends."""
    prof = []
    for i in range(steps + 1):            # bottom dome
        a = -math.pi / 2 + (math.pi / 2) * i / steps
        prof.append((-length + r1 + r1 * math.sin(a), r1 * math.cos(a) + 1e-4))
    for i in range(1, 8):                 # gently swelling shaft
        t = i / 8
        r = r1 + (r0 - r1) * t
        prof.append((-length + r1 + (length - r0 - r1) * t, r))
    for i in range(steps + 1):            # top dome
        a = (math.pi / 2) * i / steps
        prof.append((-r0 + r0 * math.sin(a), r0 * math.cos(a) + 1e-4))
    return lathe(name, prof)


def rounded_block(name, w, d, h, top=1.0, bottom=1.0, bevel=0.03, sub=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        s = top if v.co.z > 0 else bottom
        v.co.x *= w * s * 2
        v.co.y *= d * (0.92 + 0.08 * s) * 2
        v.co.z *= h * 2
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    if bevel > 0:
        bv = o.modifiers.new('bevel', 'BEVEL')
        bv.width = bevel
        bv.segments = 5
        bv.limit_method = 'NONE'
    if sub:
        sd = o.modifiers.new('sub', 'SUBSURF')
        sd.levels = sd.render_levels = sub
    return o


def sphere(name, r, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r)
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def torus(name, R, r):
    bm = bmesh.new()
    M, N = 64, 12
    verts = [[bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
              for b in (2 * math.pi * j / N for j in range(N))] for a in (2 * math.pi * i / M for i in range(M))]
    for i in range(M):
        for j in range(N):
            bm.faces.new((verts[i][j], verts[(i + 1) % M][j], verts[(i + 1) % M][(j + 1) % N], verts[i][(j + 1) % N]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def joint_ball(name, r, parent, pins=False):
    """A turned wooden ball joint; hinge joints show a steel pin each side."""
    b = link(sphere(name, r), parent, joint)
    if pins:
        for x in (-1, 1):
            pin = link(lathe(name + 'Pin', [(0, 0.0001), (0, r * 0.22), (r * 0.06, r * 0.22), (r * 0.12, 0.0001)], 24), parent, steel)
            pin.location = (x * r * 0.97, 0, 0)
            pin.rotation_euler = (0, x * math.pi / 2, 0)
    return b


# ---------------------------------------------------------------------------
# Figure: a forward-kinematics rig of empties with detailed parts.
# ---------------------------------------------------------------------------
turn = empty('turn', (0, 0, 0))
rig = empty('rig', (0, 0, 0), turn)            # squash, stretch and hop at the feet
pelvis = empty('pelvis', (0, 0, 0.45), rig)
waist = empty('waist', (0, 0, 0.06), pelvis)
chest = empty('chest', (0, 0, 0.0), waist)
neck = empty('neck', (0, 0, 0.245), chest)
head = empty('head', (0, 0, 0.0), neck)

# Pelvis and torso: tapered blocks, a dark belt over the waist joint, a brass
# screw each side of the hips.
link(rounded_block('pelvisBlock', 0.11, 0.075, 0.055, top=1.0, bottom=0.8, bevel=0.04), pelvis, vinyl)
link(rounded_block('torso', 0.14, 0.088, 0.115, top=1.2, bottom=0.78, bevel=0.07), chest, vinyl).location = (0, 0, 0.12)
joint_ball('waistBall', 0.06, waist).location = (0, 0, -0.01)
for x in (-1, 1):
    s = link(lathe('screw', [(0, 0.0001), (0, 0.009), (0.003, 0.009), (0.005, 0.0001)], 24), pelvis, steel)
    s.location = (x * 0.11, 0, 0.0)
    s.rotation_euler = (0, x * math.pi / 2, 0)
    slot = link(rounded_block('slot', 0.008, 0.0012, 0.0012, bevel=0, sub=0), s, engrave)
    slot.location = (0, 0, 0.0062)
# Neck and head: an egg with a fine seam ring, like a toy helmet.
joint_ball('neckBall', 0.036, neck)
link(capsule('neckRod', 0.05, 0.03, 0.034), neck, vinyl).location = (0, 0, 0.06)
link(sphere('head', 0.098, (0.9, 0.95, 1.1)), head, vinyl).location = (0, 0, 0.145)

limbs = {}
for side, x in (('L', 1), ('R', -1)):
    sh = empty('shoulder' + side, (x * 0.178, 0, 0.2), chest)
    joint_ball('shoulderBall' + side, 0.04, sh)
    link(capsule('upperArm' + side, 0.15, 0.034, 0.029), sh, vinyl).location = (0, 0, -0.03)
    el = empty('elbow' + side, (0, 0, -0.19), sh)
    joint_ball('elbowBall' + side, 0.029, el, pins=True)
    link(capsule('forearm' + side, 0.14, 0.028, 0.023), el, vinyl).location = (0, 0, -0.025)
    link(sphere('hand' + side, 0.036, (0.75, 0.6, 1.1)), el, vinyl).location = (0, 0, -0.19)
    hip = empty('hip' + side, (x * 0.075, 0, -0.04), pelvis)
    joint_ball('hipBall' + side, 0.044, hip)
    link(capsule('thigh' + side, 0.19, 0.046, 0.036), hip, vinyl).location = (0, 0, -0.035)
    kn = empty('knee' + side, (0, 0, -0.215), hip)
    joint_ball('kneeBall' + side, 0.033, kn, pins=True)
    link(capsule('shin' + side, 0.17, 0.034, 0.027), kn, vinyl).location = (0, 0, -0.03)
    shoe = link(rounded_block('shoe' + side, 0.042, 0.07, 0.025, top=0.9, bevel=0.022), kn, vinyl)
    shoe.location = (0, -0.022, -0.188)
    sole = link(rounded_block('sole' + side, 0.044, 0.072, 0.006, bevel=0.005, sub=1), kn, joint)
    sole.location = (0, -0.022, -0.21)
    limbs[side] = (sh, el, hip, kn)

# ---------------------------------------------------------------------------
# Turntable: walnut disc, knurled brass bezel, engraved degree ticks, plinth
# with an engraved brass label.
# ---------------------------------------------------------------------------
link(lathe('disc', [(-0.05, 0.0001), (-0.05, 0.352), (-0.047, 0.358), (-0.005, 0.358), (0, 0.352), (0, 0.0001)], 128), turn, walnut)
bm = bmesh.new()
n = 240
outer = [bm.verts.new(((0.366 if k % 2 else 0.371) * math.cos(2 * math.pi * k / n),
                       (0.366 if k % 2 else 0.371) * math.sin(2 * math.pi * k / n), -0.034)) for k in range(n)]
inner = [bm.verts.new((0.357 * math.cos(2 * math.pi * k / n), 0.357 * math.sin(2 * math.pi * k / n), -0.034)) for k in range(n)]
for k in range(n):
    bm.faces.new((inner[k], outer[k], outer[(k + 1) % n], inner[(k + 1) % n]))
geom = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
bmesh.ops.translate(bm, vec=(0, 0, 0.018), verts=[v for v in geom['geom'] if isinstance(v, bmesh.types.BMVert)])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
me = bpy.data.meshes.new('bezel')
bm.to_mesh(me)
bm.free()
link(bpy.data.objects.new('bezel', me), turn, brass, smooth=False)
for k in range(72):
    a = 2 * math.pi * k / 72
    L = 0.03 if k % 6 == 0 else 0.016
    tk = link(rounded_block('tick', 0.0012, L / 2, 0.0006, bevel=0, sub=0), turn, engrave)
    r = 0.34 - L / 2
    tk.location = (r * math.sin(a), -r * math.cos(a), 0.0004)
    tk.rotation_euler = (0, 0, a)
link(lathe('plinth', [(-0.1, 0.0001), (-0.1, 0.33), (-0.096, 0.335), (-0.054, 0.335), (-0.05, 0.33), (-0.05, 0.0001)], 128), None, black)
link(rounded_block('label', 0.07, 0.003, 0.012, bevel=0.002, sub=1), None, brass).location = (0, -0.334, -0.075)
txt = bpy.data.curves.new('labelText', 'FONT')
txt.body = 'BODY  ·  SCHEMATIC'
txt.size = 0.0115
txt.align_x = 'CENTER'
txt.align_y = 'CENTER'
txt.extrude = 0.0006
txt_o = link(bpy.data.objects.new('labelText', txt), None, engrave, smooth=False)
txt_o.location = (0, -0.3375, -0.075)
txt_o.rotation_euler = (math.pi / 2, 0, 0)

# The stand: a steel rod from the turntable into the back of the pelvis, as on
# a real artist's mannequin. The figure is held by it, so it never leaves it.
rod = link(lathe('rod', [(0, 0.0001), (0, 0.0075), (0.41, 0.0075), (0.41, 0.0001)], 24), turn, steel)
rod.location = (0, 0.11, 0)
rod.rotation_euler = (0.116, 0, 0)
collar = link(lathe('rodCollar', [(0, 0.0001), (0, 0.022), (0.008, 0.022), (0.016, 0.012), (0.016, 0.0001)], 48), turn, brass)
collar.location = (0, 0.11, 0)

# Backdrop: the BODY face colour.
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 1.2, 0.5), rotation=(math.pi / 2, 0, 0))
bpy.context.object.data.materials.append(plate_mat)
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.1))
bpy.context.object.data.materials.append(plate_mat)

# Studio: soft key, fill, two rim strips and a top light.
aim = empty('aim', (0, 0, 0.42))


def area(name, loc, size, energy, color=(1, 1, 1), size_y=None):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy = energy
    d.color = color
    d.shape = 'RECTANGLE'
    d.size = size
    d.size_y = size_y or size
    o = bpy.data.objects.new(name, d)
    scene.collection.objects.link(o)
    o.location = loc
    o.constraints.new('TRACK_TO').target = aim
    return o


area('key', (-1.4, -1.6, 2.0), 1.4, 80, (1.0, 0.96, 0.9))
area('fill', (1.8, -1.2, 0.8), 2.0, 28, (0.85, 0.9, 1.0))
area('rimL', (-1.2, 1.0, 1.2), 0.25, 60, size_y=2.0)
area('rimR', (1.2, 1.0, 1.2), 0.25, 60, size_y=2.0)
area('top', (0, 0, 2.6), 1.0, 20)

world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.05, 0.04, 0.07, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.3
scene.world = world

cam_d = bpy.data.cameras.new('cam')
cam_d.type = 'ORTHO'
cam_d.ortho_scale = 1.3
cam = bpy.data.objects.new('cam', cam_d)
scene.collection.objects.link(cam)
cam.rotation_euler = (math.radians(77), 0, 0)
cam.location = (0, -4, 0.42 + 4 * math.tan(math.radians(13)))
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = int(720 * SCALE)
scene.render.resolution_y = int(900 * SCALE)
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.file_format = 'PNG'

# ---------------------------------------------------------------------------
# Motion: damped springs (mass/stiffness/damping) stepped at 240 Hz.
# ---------------------------------------------------------------------------
class Spring:
    def __init__(self, m, k, c, x=0.0):
        self.m, self.k, self.c, self.x, self.v, self.target = m, k, c, x, 0.0, x

    def step(self, dt):
        a = (-self.k * (self.x - self.target) - self.c * self.v) / self.m
        self.v += a * dt
        self.x += self.v * dt


squash = Spring(1.0, 260, 9)     # + flattens, - stretches
hop = Spring(1.0, 180, 11)       # body height above the disc
arms = Spring(1.0, 110, 4.5)     # arms lag behind the body
look = Spring(1.2, 70, 10)       # head turns to the viewer
spin = Spring(2.0, 40, 12)       # turntable swing after the touch

TAP = 1.6
dt_sub = 1 / 240
t = 0.0
for f in range(1, FRAMES + 1):
    T = (f - 1) / FPS
    while t < T:
        if t < TAP:
            look.target = -0.45 if t > 0.5 else 0.0
        elif t < TAP + 0.12:
            squash.target = 0.12          # pressed down
        elif t < TAP + 0.2:
            squash.target = -0.07         # released: springs up stretched
            spin.target = 0.5
            look.target = 0.0
        else:
            squash.target = hop.target = spin.target = 0.0
        arms.target = squash.x * 0.9 - hop.v * 0.05
        for s in (squash, hop, arms, look, spin):
            s.step(dt_sub)
        t += dt_sub
    if f < FIRST:
        continue

    breathe = math.sin(2 * math.pi * T / 1.8)
    sway = math.sin(2 * math.pi * T / 3.6)
    sq = squash.x
    rig.scale = (1 + sq * 0.5, 1 + sq * 0.5, 1 - sq)
    rig.location = (0, 0, max(hop.x, 0))
    turn.rotation_euler = (0, 0, -0.35 + spin.x)
    # Weight shift: the pelvis sways, the chest counters, the head stays level.
    pelvis.rotation_euler = (0, sway * 0.05, 0)
    pelvis.location = (sway * 0.008, 0, 0.45)
    chest.rotation_euler = (breathe * 0.015, -sway * 0.07, 0)
    chest.scale = (1 + breathe * 0.012, 1 + breathe * 0.02, 1 + breathe * 0.008)
    head.rotation_euler = (-breathe * 0.02, sway * 0.03, look.x)
    for side, x in (('L', 1), ('R', -1)):
        sh, el, hip, kn = limbs[side]
        sh.rotation_euler = (breathe * 0.03 - arms.x * 0.4, x * (0.12 + arms.x * 0.9 + breathe * 0.02), 0)
        el.rotation_euler = (-0.25 - arms.x * 0.5, 0, 0)
        bend = 0.08 + max(sq, 0) * 1.2 + (0.04 if side == 'L' else 0) * (1 + sway)
        hip.rotation_euler = (-bend, -x * sway * 0.03 - pelvis.rotation_euler.y, 0)
        kn.rotation_euler = (bend * 2, 0, 0)
    scene.frame_set(f)
    scene.render.filepath = os.path.join(out, 'f%04d.png' % f)
    bpy.ops.render.render(write_still=True)
    print('frame', f, flush=True)
