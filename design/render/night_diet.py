# DIET straight from Blender (Wei, 14 Oct 2026: "none of the objects should be
# created from code, all straight from blender; coding controls the reactions,
# feel and functionalities"). This is the Night mockup scene
# (design/mockups/clay/screen.py night), fitted to the app's DIET face
# (420 x 852 pt on the reference iPhone 18 Pro Max), rendered in pieces:
#   night-diet-backdrop   the tray with everything that never moves (rail, leader)
#   night-jar-back/front  the jar behind and in front of the food (they bob together)
#   night-quick-<kcal>    the quick-add blocks, which are dragged
#   night-key-<id>[-down] the keys, up and pressed
#   night-gauge-<m>-<nn>  a macro tube filled to nn/20
#   night-food-<tint>-<a> food blocks (three proportions), placed by the app
#   night-glyph-<c>       hero glyphs, set by the app with the font's advances
# Each picture is 3 px per point with its soft shadow on a transparent ground.
# night-diet.json gives every picture's rect on the face, in points, plus the
# layout the app's behaviour needs (jar glass, rail, label anchors).
#   python3 night_diet.py <out dir> [samples] [only-prefix]
import bpy, bmesh, math, sys, os, json
from mathutils import Vector

OUT = os.path.abspath(sys.argv[1])
SAMPLES = int(sys.argv[2]) if len(sys.argv) > 2 else 96
ONLY = sys.argv[3] if len(sys.argv) > 3 else ''
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

HERO_FONT = bpy.data.fonts.load(os.path.join(REPO, 'App', 'Fonts', 'Unbounded-Black.ttf'))
LABEL_FONT = bpy.data.fonts.load('/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf')
BODY_FONT = bpy.data.fonts.load('/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf')


def em_ratio(font):
    """Blender's text size is not the font's em: the share of it a cap takes,
    over the font's own cap height. Sizes are exported in em points, which is
    what the app's fonts take."""
    from PIL import ImageFont
    cu = bpy.data.curves.new('probe', 'FONT')
    cu.body, cu.font, cu.size, cu.align_y = 'H', font, 1.0, 'BOTTOM_BASELINE'
    o = bpy.data.objects.new('probe', cu)
    scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    me = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    cap = max(v.co.y for v in me.vertices)
    bpy.data.objects.remove(o, do_unlink=True)
    em = ImageFont.truetype(font.filepath, 1000)
    return cap / (-em.getbbox('H', anchor='ls')[1] / 1000)


EM = {f.name: em_ratio(f) for f in (HERO_FONT, LABEL_FONT, BODY_FONT)}

# --- The face. The mockup's tray (0.956 units wide) becomes the app's tray
# (406 pt wide, 7 pt inside the 420 x 852 face); its height is fitted to the
# face and the mockup's vertical positions are drawn in by the same share.
FACE_W, FACE_H = 420.0, 852.0
PT = 406 / 0.956                    # points per Blender unit
U = 1 / PT
TRAY_HW = 0.478
TRAY_HH = (FACE_H - 14) / 2 * U
ZC = -0.02                          # the tray's centre in the mockup
K = TRAY_HH / 1.0265                # the mockup's tray half height was 1.0265
FRONT = 0.02                        # the tray's face (objects stand at -y)
PX = 3


def Z(z):
    """A mockup height on the fitted face."""
    return ZC + (z - ZC) * K


def face_pt(x, z):
    """Blender (x, z) to face points (x right, y down from the face's top-left)."""
    return (FACE_W / 2 + x * PT, FACE_H / 2 - (z - ZC) * PT)


S = dict(tray=0x211F24, ink=0xF1ECE4, muted=0x8E8892, hero=0xF1ECE4, obj=0xE9DFD0, accent=0xD9774E,
         plinth=0x34303A, hardware=0xC9A46A, glass=0xE2E8F2, glass_rough=0.1, button=0xEDE5D8,
         button_text=0x221F24, quick=0xE3CB98)
FOODS = {'carbs': 0xD9A85B, 'protein': 0xB0704A, 'fat': 0xEFE3C8, 'mixed': 0xCDBDA6, 'quick': S['quick']}


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def clay(name, color, rough=0.46, coat=0.25, sss=0.12, bump=0.05, grain=320.0):
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
INK = clay('ink', S['ink'], rough=0.4)
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

GROUPS = {}  # group name -> top-level objects


def link(o, parent=None, mat=None, smooth=True, group=None):
    scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    if mat:
        o.data.materials.append(mat)
    if smooth and o.type == 'MESH':
        for p in o.data.polygons:
            p.use_smooth = True
    if group:
        GROUPS.setdefault(group, []).append(o)
    return o


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0), group=None):
    o = bpy.data.objects.new(name, None)
    scene.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    if group:
        GROUPS.setdefault(group, []).append(o)
    return o


def block(name, w, d, h, bevel=0.02, sub=2, top=1.0):
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
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=24, radius=r)
    for v in bm.verts:
        v.co.x, v.co.z = v.co.z, v.co.x
        if abs(v.co.x) > 1e-6:
            v.co.x += (length / 2 - r) * (1 if v.co.x > 0 else -1)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def text(name, body, size, font, mat, loc, parent=None, align='LEFT', align_y='CENTER', depth=0.004, bevel=0.35,
         rot=(math.pi / 2, 0, 0), spacing=1.0, group=None):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.font = font
    cu.size = size
    cu.align_x = align
    cu.align_y = align_y
    cu.extrude = depth
    cu.bevel_depth = depth * bevel
    cu.bevel_resolution = 3
    cu.space_character = spacing
    o = link(bpy.data.objects.new(name, cu), parent, mat, smooth=False, group=group)
    o.location, o.rotation_euler = loc, rot
    return o


def screw(name, parent, loc, r):
    h = empty(name, loc, parent, rot=(math.pi / 2, 0, 0))
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


LAYOUT = {'face': [FACE_W, FACE_H], 'labels': {}}


def label_anchor(key, x, z, size, align='left', weight='bold'):
    """Where the app sets a dynamic line of text: its left (or right) edge and
    vertical centre in face points, and its size in points."""
    px, py = face_pt(x, z)
    font = LABEL_FONT if weight == 'bold' else BODY_FONT
    LAYOUT['labels'][key] = dict(x=round(px, 2), y=round(py, 2), size=round(size * PT * EM[font.name], 2), align=align,
                                 weight=weight)


# --- The tray.
tray = link(block('tray', TRAY_HW, 0.06, TRAY_HH, bevel=0.05, sub=3), None, TRAY, group='backdrop')
tray.location = (0, 0.08, ZC)

# --- Text the app sets (fixture numbers in the mockup), recorded as anchors.
label_anchor('title', -0.43, Z(0.93), 0.042)
label_anchor('caption', -0.43, Z(0.885), 0.024, weight='medium')
label_anchor('nav', 0.43, Z(0.925), 0.026, align='right')
label_anchor('heroLabel', -0.43, Z(0.545), 0.03)
label_anchor('eaten', -0.43, Z(0.505), 0.028, weight='medium')
label_anchor('unknownMacros', -0.43, Z(0.315), 0.022, weight='medium')

# --- Hero: kcal left, set by the app from rendered glyphs.
HERO_SIZE = 0.255
LAYOUT['hero'] = dict(x=round(face_pt(-0.445, 0)[0], 2), centerY=round(face_pt(0, Z(0.70))[1], 2), fontSize=round(HERO_SIZE * PT * EM[HERO_FONT.name], 2))

# --- Macro gauges: glass tubes filled with clay.
GAUGE_LEN, GAUGE_R = 0.25, 0.021
gauges = {}
for i, (key, kind) in enumerate([('protein', 'protein'), ('carbs', 'carbs'), ('fat', 'fat')]):
    x = -0.43 + i * 0.3
    label_anchor('macro.%s.name' % key, x, Z(0.44), 0.022)
    label_anchor('macro.%s.value' % key, x, Z(0.405), 0.026, weight='medium')
    zc = Z(0.36)
    tube = link(capsule('tube', GAUGE_LEN, GAUGE_R), None, GLASS, group='gauge-' + key)
    tube.location = (x + GAUGE_LEN / 2, FRONT - GAUGE_R - 0.004, zc)
    gauges[key] = (x, zc, kind)

# --- The jar, as in the mockup, fitted.
JAR_Z = Z(-0.49)
jar = empty('jar', (0.07, -0.17, JAR_Z), rot=(math.radians(6), 0, math.radians(-8)))
JS = 0.88
JW, JD, JH, wall_t = 0.292 * JS, 0.172 * JS, 0.36 * JS * K, 0.045 * JS
base_top = 0.09 * JS


def jar_part(o, front=False):
    GROUPS.setdefault('jar-front' if front else 'jar-back', []).append(o)
    return o


def tank_wall(name, w, d, h, loc, front=False):
    o = link(block(name, w, d, h, bevel=min(0.02, w * 0.9, d * 0.9, h * 0.9), sub=2), jar, GLASS)
    o.location = loc
    return jar_part(o, front)


inner_h = 2 * JH - wall_t
tank_wall('wallBack', JW, wall_t / 2, JH, (0, JD - wall_t / 2, base_top + JH))
tank_wall('wallL', wall_t / 2, JD, JH, (-JW + wall_t / 2, 0, base_top + JH))
tank_wall('wallR', wall_t / 2, JD, JH, (JW - wall_t / 2, 0, base_top + JH))
tank_wall('floor', JW, JD, wall_t / 2, (0, 0, base_top + wall_t / 2))
tank_wall('wallFront', JW, wall_t / 2, JH, (0, -JD + wall_t / 2, base_top + JH), front=True)
plinth = jar_part(link(block('plinth', JW + 0.03, JD + 0.03, 0.04 * JS, bevel=0.025), jar, PLINTH))
plinth.location = (0, 0, base_top - 0.04 * JS)
band = jar_part(link(block('band', JW + 0.036, JD + 0.036, 0.01, bevel=0.008), jar, HARD))
band.location = (0, 0, base_top - 0.04 * JS)
for i in range(56):
    x = -JW - 0.025 + i * (2 * JW + 0.05) / 55
    rib = jar_part(link(block('knurl', 0.0019, 0.0019, 0.008, bevel=0.0011, sub=1), jar, HARD))
    rib.location = (x, -(JD + 0.047), base_top - 0.04 * JS)
cz = base_top + 2 * JH + 0.008
for name, w, d, loc, front in (('collarB', JW + 0.022, 0.011, (0, JD + 0.011, cz), False),
                               ('collarL', 0.011, JD + 0.022, (-JW - 0.011, 0, cz), False),
                               ('collarR', 0.011, JD + 0.022, (JW + 0.011, 0, cz), False),
                               ('collarF', JW + 0.022, 0.011, (0, -JD - 0.011, cz), True)):
    c = jar_part(link(block(name, w, d, 0.02, bevel=0.009), jar, OBJ), front)
    c.location = loc
    s = jar_part(link(block(name + 'Seam', w + 0.002, d + 0.002, 0.0022, bevel=0.002), jar, RUST), front)
    s.location = loc
for x in (-JW - 0.006, JW + 0.006):
    before = set(bpy.data.objects)
    screw('collarScrew', jar, (x, -JD - 0.024, cz), 0.0065)
    for o in set(bpy.data.objects) - before:
        if o.parent == jar:
            jar_part(o, True)
plaque = jar_part(link(block('plaque', 0.06, 0.004, 0.014, bevel=0.004), jar, HARD), True)
plaque.location = (0, -(JD + 0.025), cz)
text('dietPlaque', 'DIET', 0.018, LABEL_FONT, PLINTH, (0, -0.0045, 0), plaque, align='CENTER', depth=0.0012, spacing=1.2)
floor_z = base_top + wall_t
target_z = floor_z + inner_h * 0.74
for q in range(1, 4):
    t = jar_part(link(block('grad', 0.026, 0.003, 0.003, bevel=0.002, sub=1), jar, OBJ), True)
    t.location = (JW - 0.05, -JD - 0.003, floor_z + inner_h * 0.74 * q / 4)
bar = jar_part(link(block('targetBar', JW * 0.9, 0.003, 0.0035, bevel=0.002, sub=1), jar, ACCENT), True)
bar.location = (0, -JD - 0.003, target_z)
bpy.context.view_layer.update()


def project(local):
    w = jar.matrix_world @ Vector(local)
    return face_pt(w.x, w.z)


def rect_of(points):
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return [round(min(xs), 2), round(min(ys), 2), round(max(xs) - min(xs), 2), round(max(ys) - min(ys), 2)]


# The glass as the app's physics sees it: the front wall, outer and inner.
LAYOUT['jar'] = dict(
    outer=rect_of([project((sx * JW, -JD, z)) for sx in (-1, 1) for z in (base_top, base_top + 2 * JH)]),
    interior=rect_of([project((sx * (JW - wall_t), -JD, z)) for sx in (-1, 1) for z in (floor_z, base_top + 2 * JH)]),
    targetY=round(project((0, -JD, target_z))[1], 2))
target_world_z = ZC + (FACE_H / 2 - LAYOUT['jar']['targetY']) * U
label_anchor('target.name', -0.44, target_world_z + 0.018, 0.02)
label_anchor('target.value', -0.44, target_world_z - 0.02, 0.03, weight='medium')
lead = link(block('leader', 0.03, 0.002, 0.0018, bevel=0.0012, sub=1), None, INK, group='backdrop')
lead.location = (-0.29, FRONT - 0.003, target_world_z)

# --- The rail and its quick-add blocks.
rail_z = Z(-0.72)
rail = link(block('rail', 0.45, 0.06, 0.011, bevel=0.009), None, PLINTH, group='backdrop')
rail.location = (0, -0.03, rail_z)
LAYOUT['railY'] = round(face_pt(0, rail_z + 0.011)[1], 2)
LAYOUT['quick'] = {}
for i, (kcal, w, h) in enumerate([(50, 0.08, 0.05), (100, 0.085, 0.056), (250, 0.09, 0.064), (500, 0.095, 0.074)]):
    x = -0.34 + i * 0.226
    q = link(block('quick', w, 0.045, h, bevel=0.03), None, FOOD['quick'], group='quick-%d' % kcal)
    q.location = (x, -0.04, rail_z + 0.011 + h)
    text('quickNum', str(kcal), 0.042, HERO_FONT, PLINTH, (0, -0.0455, 0.008), q, align='CENTER', depth=0.003)
    text('quickUnit', 'KCAL', 0.014, LABEL_FONT, PLINTH, (0, -0.0455, -h + 0.018), q, align='CENTER', depth=0.0015, spacing=1.2)
    LAYOUT['quick'][str(kcal)] = rect_of([face_pt(x - w, rail_z + 0.011), face_pt(x + w, rail_z + 0.011 + 2 * h)])

# --- Keys: clay LOG FOOD / LOAD and resin UNDO / DISCARD, up and pressed.
KEY_Z = Z(-0.92)
LAYOUT['keys'] = {}
KEYS = [('log', 'LOG FOOD', -0.15, 0.27, BUTTON, BUTTON_TEXT), ('load', 'LOAD', -0.15, 0.27, BUTTON, BUTTON_TEXT),
        ('undo', 'UNDO', 0.3, 0.135, GLASS, INK), ('discard', 'DISCARD', 0.3, 0.135, GLASS, INK)]
for key, label, x, w, mat, ink in KEYS:
    for down in (False, True):
        g = 'key-%s%s' % (key, '-down' if down else '')
        y = -0.02 + (0.012 if down else 0)
        k = link(block('key', w, 0.035, 0.058, bevel=0.056, sub=3), None, mat, group=g)
        k.location = (x, y, KEY_Z)
        if mat is GLASS:
            text('keyLabel', label, 0.03, LABEL_FONT, ink, (x, y - 0.038, KEY_Z), None, align='CENTER', depth=0.003, spacing=1.2, group=g)
        else:
            text('keyLabel', label, 0.032, LABEL_FONT, ink, (0, -0.0355, 0), k, align='CENTER', depth=0.003, spacing=1.2)
    LAYOUT['keys'][key] = rect_of([face_pt(x - w, KEY_Z - 0.058), face_pt(x + w, KEY_Z + 0.058)])

# --- Studio, exactly the mockup's.
aim = empty('aim')


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

cam_d = bpy.data.cameras.new('cam')
cam_d.type = 'ORTHO'
cam = bpy.data.objects.new('cam', cam_d)
scene.collection.objects.link(cam)
cam.rotation_euler = (math.radians(90), 0, 0)
cam_d.clip_start = 0.01
cam_d.clip_end = 10
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.transparent_max_bounces = 16
scene.cycles.transmission_bounces = 12
scene.render.film_transparent = True
scene.cycles.film_transparent_glass = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Base Contrast'

# Catches the shadows of the pieces drawn over the backdrop.
catcher = link(block('catcher', 3, 0.001, 3, bevel=0, sub=0), None, TRAY, smooth=False)
catcher.location = (0, FRONT + 0.0011, 0)
catcher.is_shadow_catcher = True

SPRITES = {}


def tree(o):
    return [o] + list(o.children_recursive)


def show(groups, ghosts=()):
    keep, ghost = set(), set()
    for g in groups:
        for o in GROUPS.get(g, []):
            keep.update(tree(o))
    for g in ghosts:
        for o in GROUPS.get(g, []):
            ghost.update(tree(o))
    for o in scene.objects:
        if o.type in ('MESH', 'FONT') and o is not catcher:
            o.hide_render = o not in keep and o not in ghost
            o.visible_camera = o in keep


def feather(path, points):
    """Fades a picture's caught shadow to nothing over its outer `points`, so
    a soft shadow never ends on the picture's edge."""
    import numpy as np
    from PIL import Image
    px = np.array(Image.open(path).convert('RGBA')).astype(np.float32)
    h, w = px.shape[:2]
    d = np.minimum(np.minimum(np.arange(h), np.arange(h)[::-1])[:, None], np.minimum(np.arange(w), np.arange(w)[::-1])[None, :])
    t = np.clip(d / (points * PX), 0, 1)
    px[..., 3] *= t * t * (3 - 2 * t)
    Image.fromarray(px.round().astype(np.uint8)).save(path)


def shoot(name, rect, groups, catch=True, ghosts=(), fade=0):
    """Renders `groups` framed on `rect` (face points: x, y, w, h). `ghosts`
    cast their shadows and reflections without being seen; `fade` feathers a
    caught shadow at the picture's edge."""
    if ONLY and not name.startswith(ONLY):
        return
    x, y, w, h = rect
    show(groups, ghosts)
    catcher.hide_render = not catch
    cam_d.ortho_scale = max(w, h) * U
    cam_d.sensor_fit = 'HORIZONTAL' if w >= h else 'VERTICAL'
    cam.location = ((x + w / 2 - FACE_W / 2) * U, -3, ZC + (FACE_H / 2 - (y + h / 2)) * U)
    scene.render.resolution_x = round(w * PX)
    scene.render.resolution_y = round(h * PX)
    scene.render.filepath = os.path.join(OUT, name + '@3x.png')
    bpy.ops.render.render(write_still=True)
    if catch and fade:
        feather(scene.render.filepath, fade)
    SPRITES[name] = dict(rect=[round(v, 2) for v in rect])
    print('rendered', name, flush=True)


def around(r, left=6, top=6, right=24, bottom=24):
    """A picture's rect: the object's rect with room for its shadow, snapped to whole points."""
    x, y, w, h = r
    x0, y0 = math.floor(x - left), math.floor(y - top)
    return [x0, y0, math.ceil(x + w + right) - x0, math.ceil(y + h + bottom) - y0]


# 1. The backdrop: tray, rail, leader, with the soft shadows of the objects
# that stay put (jar, keys, gauge tubes) baked in. Those objects' own pictures
# carry no shadow; anything that moves carries its own, feathered.
STILL = ['jar-back', 'jar-front', 'key-log', 'key-undo', 'gauge-protein', 'gauge-carbs', 'gauge-fat']
shoot('night-diet-backdrop', [0, 0, FACE_W, FACE_H], ['backdrop'], catch=False, ghosts=STILL)

# 2. The jar in two layers that bob together and sandwich the food: the back
# (plinth, sides, back wall, collar back) and the front (front wall, collar
# front, screws, plaque, graduations, TARGET bar).
jr = LAYOUT['jar']['outer']
jar_rect = around([jr[0], jr[1] - 30, jr[2], jr[3] + 30], 34, 30, 44, 44)
shoot('night-jar-back', jar_rect, ['jar-back'], catch=False)
shoot('night-jar-front', jar_rect, ['jar-front'], catch=False)

# 3. Quick-add blocks.
for kcal, r in LAYOUT['quick'].items():
    shoot('night-quick-' + kcal, around(r, 16, 16, 40, 40), ['quick-' + kcal], fade=14)

# 4. Keys, up and pressed.
for key, r in LAYOUT['keys'].items():
    for down in ('', '-down'):
        shoot('night-key-%s%s' % (key, down), around(r, 8, 8, 26, 30), ['key-%s%s' % (key, down)], catch=False)

# 5. Gauges at 21 fills: the tube with its clay filled to n/20.
LAYOUT['gauges'] = {}
for key, (x, zc, kind) in gauges.items():
    r = rect_of([face_pt(x, zc - GAUGE_R), face_pt(x + GAUGE_LEN, zc + GAUGE_R)])
    LAYOUT['gauges'][key] = r
    for n in range(21):
        name = 'night-gauge-%s-%02d' % (key, n)
        if ONLY and not name.startswith(ONLY):
            continue
        fill = None
        share = n / 20
        if n > 0:
            fill_len = max(2 * GAUGE_R * 0.75, (GAUGE_LEN - 0.012) * share)
            fill = link(capsule('fill', fill_len, GAUGE_R * 0.72), None, FOOD[kind], group='fill')
            fill.location = (x + 0.006 + fill_len / 2, FRONT - GAUGE_R - 0.004, zc)
        shoot(name, around(r, 6, 6, 16, 16), ['gauge-' + key, 'fill'], catch=False)
        if fill:
            GROUPS['fill'].remove(fill)
            bpy.data.objects.remove(fill, do_unlink=True)

# 6. Food blocks and hero glyphs are placed by the app; they are rendered at
# the face's centre, framed around themselves.
for o in list(scene.objects):
    if o.type in ('MESH', 'FONT') and o is not catcher:
        o.hide_render = True
FOOD_H = 50.0
for kind in ('carbs', 'protein', 'fat', 'mixed', 'quick'):
    for aspect in (1.2, 1.6, 2.0):
        name = 'night-food-%s-%d' % (kind, round(aspect * 10))
        w = FOOD_H * aspect
        hw, hh = w / 2 * U, FOOD_H / 2 * U
        b = link(block('food', hw, 0.08 * JS, hh, bevel=min(hw, hh) * 0.84), None, FOOD[kind], group='food')
        b.location = (0, FRONT - 0.08 * JS, ZC)
        r = [FACE_W / 2 - w / 2, FACE_H / 2 - FOOD_H / 2, w, FOOD_H]
        shoot(name, around(r, 14, 14, 34, 34), ['food'], fade=12)
        SPRITES.get(name, {})['object'] = [round(v, 2) for v in r]
        GROUPS['food'].remove(b)
        bpy.data.objects.remove(b, do_unlink=True)

GLYPHS = {'0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five', '6': 'six', '7': 'seven',
          '8': 'eight', '9': 'nine', ',': 'comma', '.': 'period', ':': 'colon', '×': 'times', '−': 'minus',
          '-': 'hyphen', '—': 'emdash', 'G': 'G', 'O': 'O'}
size_pt = HERO_SIZE * PT
for ch, slug in GLYPHS.items():
    name = 'night-glyph-' + slug
    ox, oy = FACE_W / 2 - size_pt * 0.3, FACE_H / 2 + size_pt * 0.3  # the glyph's origin on the baseline
    g = text('glyph', ch, HERO_SIZE, HERO_FONT, HERO, ((ox - FACE_W / 2) * U, FRONT - 0.002, ZC + (FACE_H / 2 - oy) * U),
             None, align='LEFT', align_y='BOTTOM_BASELINE', depth=0.03, bevel=0.3, group='glyph')
    r = [ox - size_pt * 0.1, oy - size_pt * 0.95, size_pt * 1.15, size_pt * 1.25]
    shoot(name, [round(v, 2) for v in r], ['glyph'], fade=10)
    if name in SPRITES:
        SPRITES[name].update(character=ch, fontSize=round(size_pt * EM[HERO_FONT.name], 2), origin=[round(ox, 2), round(oy, 2)])
    GROUPS['glyph'].remove(g)
    bpy.data.objects.remove(g, do_unlink=True)

meta_path = os.path.join(OUT, 'night-diet.json')
old = {}
if ONLY and os.path.exists(meta_path):
    with open(meta_path) as fh:
        old = json.load(fh).get('sprites', {})
old.update(SPRITES)
with open(meta_path, 'w') as fh:
    json.dump(dict(scale=PX, pointsPerUnit=PT, layout=LAYOUT, sprites=old), fh, indent=1, ensure_ascii=False, sort_keys=True)
print('done', len(SPRITES))
