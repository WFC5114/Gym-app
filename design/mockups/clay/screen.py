# Whole-screen claymorphism study (Wei, 14 Oct 2026: "the whole app does not
# feel claymorphism, just minimalism; I want 3D-ish claymorphism with some
# glassish stuff resembling clay, not too childish but mature"). One DIET
# screen with every element as an object: a pressed clay tray, a clay hero
# number, resin-glass macro capsules filled with clay, the jar, a clay rail of
# quick-add blocks and clay / resin buttons. Three palettes. Mockup renders
# only, with fixture numbers; not the app.
#   python3 screen.py <stone|night|kiln> <out.png> [samples] [scale]
import bpy, bmesh, math, sys, os

STYLE = sys.argv[1]
OUT = os.path.abspath(sys.argv[2])
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 64
SCALE = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

HERO_FONT = bpy.data.fonts.load(os.path.join(REPO, 'App', 'Fonts', 'Unbounded-Black.ttf'))
LABEL_FONT = bpy.data.fonts.load('/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf')
BODY_FONT = bpy.data.fonts.load('/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf')

STYLES = {
    # Warm greige clay, ink numerals, smoked resin, a terracotta accent.
    'stone': dict(wall=0x2B2724, tray=0xD9D1C5, ink=0x26221E, muted=0x7A7167, hero=0x2A2622, obj=0xEEE7DB,
                  accent=0xC2603D, plinth=0x3A332D, hardware=0xC9A46A, glass=0xF4E9DA, glass_rough=0.16,
                  button=0x2A2622, button_text=0xEEE7DB, quick=0xE6CF9C),
    # Graphite clay, ivory objects, clear cool glass.
    'night': dict(wall=0x0B0A0C, tray=0x211F24, ink=0xF1ECE4, muted=0x8E8892, hero=0xF1ECE4, obj=0xE9DFD0,
                  accent=0xD9774E, plinth=0x34303A, hardware=0xC9A46A, glass=0xE2E8F2, glass_rough=0.1,
                  button=0xEDE5D8, button_text=0x221F24, quick=0xE3CB98),
    # The DIET colour kept, matured to burnt terracotta, cream and indigo ink.
    'kiln': dict(wall=0x1A0E0A, tray=0xB0502F, ink=0xFBF1E4, muted=0xF0C9B2, hero=0xFBF1E4, obj=0xF4E3CC,
                 accent=0x2F2A6B, plinth=0x3B1D16, hardware=0xE9C77F, glass=0xFFEADF, glass_rough=0.14,
                 button=0xF6E8D4, button_text=0x7E3018, quick=0xF0D79E),
}
S = STYLES[STYLE]
FOODS = {'carb': 0xD9A85B, 'protein': 0xB0704A, 'fat': 0xEFE3C8, 'mixed': 0xCDBDA6, 'quick': S['quick']}


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def clay(name, color, rough=0.46, coat=0.25, sss=0.12, bump=0.05, grain=320.0):
    """Mature clay: one colour, soft satin sheen, a fine hand-pressed surface."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = 0.25
    b.inputs['Subsurface Weight'].default_value = sss
    b.inputs['Subsurface Radius'].default_value = (0.05, 0.03, 0.02)
    b.inputs['Subsurface Scale'].default_value = 0.02
    coord = nt.nodes.new('ShaderNodeTexCoord')
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = grain
    noise.inputs['Detail'].default_value = 6.0
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = bump
    bp.inputs['Distance'].default_value = 0.0003
    nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
    nt.links.new(noise.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    return m


def resin(name, tint, rough):
    """Clay-like glass: thick frosted resin, glossy on the skin, soft inside."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(tint)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Transmission Weight'].default_value = 1.0
    b.inputs['IOR'].default_value = 1.46
    b.inputs['Coat Weight'].default_value = 1.0
    b.inputs['Coat Roughness'].default_value = 0.03
    return m


TRAY = clay('tray', S['tray'], rough=0.62, coat=0.08, bump=0.08, grain=180)
WALL = clay('wall', S['wall'], rough=0.8, coat=0)
INK = clay('ink', S['ink'], rough=0.4)
MUTED = clay('muted', S['muted'], rough=0.5)
HERO = clay('hero', S['hero'], rough=0.32, coat=0.5)
OBJ = clay('obj', S['obj'])
ACCENT = clay('accent', S['accent'])
PLINTH = clay('plinth', S['plinth'], rough=0.5)
HARD = clay('hardware', S['hardware'], rough=0.3, coat=0.4)
RUST = clay('seam', 0x6B4A35, rough=0.6, coat=0)
GLASS = resin('glass', S['glass'], S['glass_rough'])
BUTTON = clay('button', S['button'], rough=0.38, coat=0.4)
BUTTON_TEXT = clay('buttonText', S['button_text'])
FOOD = {k: clay(k, v) for k, v in FOODS.items()}


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


def empty(name, loc, parent=None, rot=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    scene.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    return o


def block(name, w, d, h, bevel=0.02, sub=2, top=1.0):
    """A rounded block of half sizes w (x), d (y, depth) and h (z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    for v in bm.verts:
        s = 1 + (top - 1) * (v.co.z + 1) / 2
        v.co.x *= w * s
        v.co.y *= d
        v.co.z *= h
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bv = o.modifiers.new('bevel', 'BEVEL')
    bv.width = min(bevel, w * 0.98, d * 0.98, h * 0.98)
    bv.segments = 5
    sd = o.modifiers.new('sub', 'SUBSURF')
    sd.levels = sd.render_levels = sub
    return o


def capsule(name, length, r, segments=48):
    """A horizontal capsule along x, centred."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=24, radius=r)
    for v in bm.verts:
        v.co.x, v.co.z = v.co.z, v.co.x  # poles on x, so the equator ring sits at x 0
        if abs(v.co.x) > 1e-6:
            v.co.x += (length / 2 - r) * (1 if v.co.x > 0 else -1)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def text(name, body, size, font, mat, loc, parent=None, align='LEFT', depth=0.004, bevel=0.35, rot=(math.pi / 2, 0, 0), spacing=1.0):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.font = font
    cu.size = size
    cu.align_x = align
    cu.align_y = 'CENTER'
    cu.extrude = depth
    cu.bevel_depth = depth * bevel
    cu.bevel_resolution = 3
    cu.space_character = spacing
    o = link(bpy.data.objects.new(name, cu), parent, mat, smooth=False)
    o.location, o.rotation_euler = loc, rot
    return o


def screw(name, parent, loc, r):
    h = bpy.data.objects.new(name, None)
    scene.collection.objects.link(h)
    h.parent = parent
    h.location = loc
    h.rotation_euler = (math.pi / 2, 0, 0)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=r)
    for v in bm.verts:
        v.co.z = max(v.co.z, 0) * 0.55
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    link(bpy.data.objects.new(name, me), h, HARD)
    for a in (0, math.pi / 2):
        sl = link(block(name + 'Slot', r * 0.8, r * 0.12, r * 0.3, bevel=0, sub=0), h, RUST, smooth=False)
        sl.location = (0, 0, r * 0.45)
        sl.rotation_euler = (math.pi / 2, 0, a)


# Screen: x across (width 1), z up (height 2.173), the camera looks along +y.
W, H = 1.0, 2.173
root = empty('root', (0, 0, 0))

# The face: a pressed clay tray standing just proud of a darker wall.
wall = link(block('wall', 0.75, 0.02, 1.4, bevel=0.0), root, WALL)
wall.location = (0, 0.16, 0)
tray = link(block('tray', W / 2 - 0.022, 0.06, H / 2 - 0.06, bevel=0.05, sub=3), root, TRAY)
tray.location = (0, 0.08, -0.02)
FRONT = 0.02  # the tray's face

# Header.
text('face', 'DIET', 0.042, LABEL_FONT, INK, (-0.43, FRONT - 0.001, 0.93), root, spacing=1.15)
text('date', 'TUE 14 OCT · FIXTURE DATA', 0.024, BODY_FONT, MUTED, (-0.43, FRONT - 0.001, 0.885), root, spacing=1.1)
text('nav', 'TRAIN   BODY', 0.026, LABEL_FONT, MUTED, (0.43, FRONT - 0.001, 0.925), root, align='RIGHT', spacing=1.15)

# Hero: kcal left as a thick clay numeral.
hero = text('hero', '1,126', 0.255, HERO_FONT, HERO, (-0.445, FRONT - 0.002, 0.7), root, depth=0.03, bevel=0.3)
text('heroLabel', 'KCAL LEFT', 0.03, LABEL_FONT, INK, (-0.43, FRONT - 0.001, 0.545), root, spacing=1.2)
text('eaten', '1,324 of 2,450 eaten', 0.028, BODY_FONT, MUTED, (-0.43, FRONT - 0.001, 0.505), root)

# Macros: resin capsules filled with clay to the share eaten.
for i, (label, value, share, kind) in enumerate([('PROTEIN', '92 / 180 g', 92 / 180, 'protein'),
                                                ('CARBS', '162 / 250 g', 162 / 250, 'carb'),
                                                ('FAT', '22 / 80 g', 22 / 80, 'fat')]):
    x = -0.43 + i * 0.3
    text('macro' + label, label, 0.022, LABEL_FONT, MUTED, (x, FRONT - 0.001, 0.44), root, spacing=1.15)
    text('macroValue' + label, value, 0.026, BODY_FONT, INK, (x, FRONT - 0.001, 0.405), root)
    length, r = 0.25, 0.021
    tube = link(capsule('tube', length, r), root, GLASS)
    tube.location = (x + length / 2, FRONT - r - 0.004, 0.36)
    fill_len = max(2 * r * 0.75, (length - 0.012) * share)
    fill = link(capsule('fill', fill_len, r * 0.72), root, FOOD[kind])
    fill.location = (x + 0.006 + fill_len / 2, FRONT - r - 0.004, 0.36)

# The jar (clay round 2), turned a little so its depth reads.
JAR_Z = -0.49
jar = empty('jar', (0.07, -0.17, JAR_Z), root, rot=(math.radians(6), 0, math.radians(-8)))
JS = 0.88
JW, JD, JH, wall_t = 0.292 * JS, 0.172 * JS, 0.36 * JS, 0.045 * JS
base_top = 0.09 * JS
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=2.0)
for v in bm.verts:
    v.co.x *= JW
    v.co.y *= JD
    v.co.z = (v.co.z + 1) * JH
top_face = [f for f in bm.faces if all(v.co.z > JH * 1.99 for v in f.verts)]
bmesh.ops.delete(bm, geom=top_face, context='FACES')
me = bpy.data.meshes.new('tank')
bm.to_mesh(me)
bm.free()
tank = link(bpy.data.objects.new('tank', me), jar, GLASS)
tank.location = (0, 0, base_top)
so = tank.modifiers.new('solid', 'SOLIDIFY')
so.thickness = wall_t
bv = tank.modifiers.new('bevel', 'BEVEL')
bv.width, bv.segments = 0.035 * JS, 5
sd = tank.modifiers.new('sub', 'SUBSURF')
sd.levels = sd.render_levels = 2
plinth = link(block('plinth', JW + 0.03, JD + 0.03, 0.04 * JS, bevel=0.025), jar, PLINTH)
plinth.location = (0, 0, base_top - 0.04 * JS)
band = link(block('band', JW + 0.036, JD + 0.036, 0.01, bevel=0.008), jar, HARD)
band.location = (0, 0, base_top - 0.04 * JS)
for i in range(56):
    x = -JW - 0.025 + i * (2 * JW + 0.05) / 55
    rib = link(block('knurl', 0.0019, 0.0019, 0.008, bevel=0.0011, sub=1), jar, HARD)
    rib.location = (x, -(JD + 0.047), base_top - 0.04 * JS)
collar = link(block('collar', JW + 0.022, JD + 0.022, 0.02, bevel=0.016), jar, OBJ)
collar.location = (0, 0, base_top + 2 * JH + 0.008)
seam = link(block('collarSeam', JW + 0.024, JD + 0.024, 0.0022, bevel=0.002), jar, RUST)
seam.location = collar.location
hole = link(block('mouth', JW - wall_t + 0.002, JD - wall_t + 0.002, 0.03, bevel=0.01), jar, None)
hole.location = collar.location
hole.hide_render = True
for o in (collar, seam):
    bo = o.modifiers.new('mouth', 'BOOLEAN')
    bo.operation, bo.object, bo.solver = 'DIFFERENCE', hole, 'EXACT'
for x in (-JW - 0.006, JW + 0.006):
    screw('collarScrew', jar, (x, -JD - 0.024, base_top + 2 * JH + 0.008), 0.0065)
plaque = link(block('plaque', 0.06, 0.004, 0.014, bevel=0.004), jar, HARD)
plaque.location = (0, -(JD + 0.025), base_top + 2 * JH + 0.008)
text('dietPlaque', 'DIET', 0.018, LABEL_FONT, PLINTH, (0, -0.0045, 0), plaque, align='CENTER', depth=0.0012, spacing=1.2)
target_z = base_top + 2 * JH * 0.74
for q in range(1, 4):
    t = link(block('grad', 0.026, 0.003, 0.003, bevel=0.002, sub=1), jar, OBJ)
    t.location = (JW - 0.05, -JD - 0.003, base_top + 2 * JH * 0.74 * q / 4)
bar = link(block('targetBar', JW * 0.9, 0.003, 0.0035, bevel=0.002, sub=1), jar, ACCENT)
bar.location = (0, -JD - 0.003, target_z)
text('targetLabel', 'TARGET', 0.02, LABEL_FONT, MUTED, (-0.44, FRONT - 0.001, JAR_Z + target_z + 0.018), root, spacing=1.2)
text('targetValue', '2,450', 0.03, BODY_FONT, INK, (-0.44, FRONT - 0.001, JAR_Z + target_z - 0.02), root)
lead = link(block('leader', 0.03, 0.002, 0.0018, bevel=0.0012, sub=1), root, INK)
lead.location = (-0.29, FRONT - 0.003, JAR_Z + target_z)
# Food: chunky clay by main macro, with raised names on the big ones.
floor = wall_t
pile = [('carb', -0.17, 0.06, 0.0, 0.04, 'OATS 311'), ('protein', -0.04, 0.05, 0.0, -0.05, None),
        ('mixed', 0.11, 0.07, 0.0, 0.03, 'RICE 325'), ('quick', 0.215, 0.032, 0.0, 0.0, '100'),
        ('fat', -0.12, 0.045, 0.105, 0.3, None), ('carb', 0.03, 0.05, 0.118, -0.2, 'PASTA'),
        ('protein', 0.17, 0.042, 0.1, 0.4, None)]
for kind, x, w, z, ang, label in pile:
    w *= JS
    hh = w * 0.85
    b = link(block('food', w, 0.08 * JS, hh, bevel=min(w, hh) * 0.42), jar, FOOD[kind])
    b.location = (x * JS, 0, base_top + floor + hh + z * JS)
    b.rotation_euler = (0, ang, 0)
    if label:
        text('foodLabel', label, 0.016, LABEL_FONT, PLINTH, (0, -0.08 * JS - 0.0005, 0), b, align='CENTER', depth=0.0015, spacing=1.1)

# Loading rail with the quick-add blocks.
rail_z = -0.72
rail = link(block('rail', 0.45, 0.06, 0.011, bevel=0.009), root, PLINTH)
rail.location = (0, -0.03, rail_z)
for i, (kcal, w, h) in enumerate([(50, 0.08, 0.05), (100, 0.085, 0.056), (250, 0.09, 0.064), (500, 0.095, 0.074)]):
    x = -0.34 + i * 0.226
    q = link(block('quick', w, 0.045, h, bevel=0.03), root, FOOD['quick'])
    q.location = (x, -0.04, rail_z + 0.011 + h)
    text('quickNum', str(kcal), 0.042, HERO_FONT, PLINTH, (0, -0.0455, 0.008), q, align='CENTER', depth=0.003)
    text('quickUnit', 'KCAL', 0.014, LABEL_FONT, PLINTH, (0, -0.0455, -h + 0.018), q, align='CENTER', depth=0.0015, spacing=1.2)

# Buttons: a clay pill and a resin pill, standing proud with soft shadows.
log = link(block('logFood', 0.27, 0.035, 0.058, bevel=0.056, sub=3), root, BUTTON)
log.location = (-0.15, -0.02, -0.92)
text('logLabel', 'LOG FOOD', 0.032, LABEL_FONT, BUTTON_TEXT, (0, -0.0355, 0), log, align='CENTER', depth=0.003, spacing=1.2)
undo = link(block('undo', 0.135, 0.035, 0.058, bevel=0.056, sub=3), root, GLASS)
undo.location = (0.3, -0.02, -0.92)
text('undoLabel', 'UNDO', 0.03, LABEL_FONT, INK, (0.3, -0.058, -0.92), root, align='CENTER', depth=0.003, spacing=1.2)

# Studio: a soft key from the upper left, fill, two rims and a top light.
aim = empty('aim', (0, 0, 0))


def area(name, loc, size, energy, size_y=None, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy, d.color, d.shape = energy, color, 'RECTANGLE'
    d.size, d.size_y = size, size_y or size
    o = bpy.data.objects.new(name, d)
    scene.collection.objects.link(o)
    o.location = loc
    o.constraints.new('TRACK_TO').target = aim
    return o


area('key', (-2.2, -3.0, 3.0), 3.0, 230, color=(1.0, 0.97, 0.93))
area('fill', (2.6, -2.8, 0.4), 4.0, 80, color=(0.92, 0.94, 1.0))
area('rimL', (-1.8, 0.2, 1.4), 0.8, 60, size_y=3.0)
area('rimR', (1.8, 0.2, -0.6), 0.8, 45, size_y=3.0)
area('top', (0, -1.2, 3.4), 2.0, 60)
world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.18, 0.18, 0.2, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
scene.world = world

# A long lens, nearly orthographic, so the screen reads straight-on but the
# objects keep a little perspective depth.
cam_d = bpy.data.cameras.new('cam')
cam_d.lens = 200
cam_d.sensor_fit = 'VERTICAL'
cam_d.sensor_height = 36
cam = bpy.data.objects.new('cam', cam_d)
scene.collection.objects.link(cam)
dist = cam_d.lens / cam_d.sensor_height * H * 1.0
cam.location = (0, -dist, 0)
cam.rotation_euler = (math.radians(90), 0, 0)
cam_d.clip_end = dist + 5
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.transparent_max_bounces = 16
scene.cycles.transmission_bounces = 12
scene.render.resolution_x = int(600 * SCALE)
scene.render.resolution_y = int(600 * H * SCALE)
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Base Contrast'
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
