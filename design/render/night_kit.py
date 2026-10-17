# The Night render kit shared by the faces drawn from Blender (Wei, 14 Oct
# 2026: "none of the objects should be created from code, all straight from
# blender"): the fitted face, the Night clay and glass materials, the mockup's
# studio, the tray, and the picture shooter. night_diet.py and night_train.py
# build their face's objects on it and render them in pieces.
# Each picture is 3 px per point with its soft shadow on a transparent ground;
# each face's JSON gives every picture's rect on the face, in points, plus the
# layout the app's behaviour needs.
#   python3 night_<face>.py <out dir> [samples] [only-prefix]
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


def rect_of(points):
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return [round(min(xs), 2), round(min(ys), 2), round(max(xs) - min(xs), 2), round(max(ys) - min(ys), 2)]


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


def feather(path, points, scale=PX):
    """Fades a picture's caught shadow to nothing over its outer `points`, so
    a soft shadow never ends on the picture's edge."""
    import numpy as np
    from PIL import Image
    px = np.array(Image.open(path).convert('RGBA')).astype(np.float32)
    h, w = px.shape[:2]
    d = np.minimum(np.minimum(np.arange(h), np.arange(h)[::-1])[:, None], np.minimum(np.arange(w), np.arange(w)[::-1])[None, :])
    t = np.clip(d / (points * scale), 0, 1)
    px[..., 3] *= t * t * (3 - 2 * t)
    Image.fromarray(px.round().astype(np.uint8)).save(path)


def shoot(name, rect, groups, catch=True, ghosts=(), fade=0, px=PX):
    """Renders `groups` framed on `rect` (face points: x, y, w, h). `ghosts`
    cast their shadows and reflections without being seen; `fade` feathers a
    caught shadow at the picture's edge."""
    if ONLY and not name.startswith(ONLY):
        return
    if os.environ.get('NIGHT_DRY'):   # record the rects only, to rebuild the JSON after an interrupted run
        SPRITES[name] = dict(rect=[round(v, 2) for v in rect])
        return
    x, y, w, h = rect
    show(groups, ghosts)
    catcher.hide_render = not catch
    cam_d.ortho_scale = max(w, h) * U
    cam_d.sensor_fit = 'HORIZONTAL' if w >= h else 'VERTICAL'
    cam.location = ((x + w / 2 - FACE_W / 2) * U, -3, ZC + (FACE_H / 2 - (y + h / 2)) * U)
    scene.render.resolution_x = round(w * px)
    scene.render.resolution_y = round(h * px)
    scene.render.filepath = os.path.join(OUT, '%s@%dx.png' % (name, px))
    bpy.ops.render.render(write_still=True)
    if catch and fade:
        feather(scene.render.filepath, fade, px)
    SPRITES[name] = dict(rect=[round(v, 2) for v in rect])
    print('rendered', name, flush=True)


def around(r, left=6, top=6, right=24, bottom=24):
    """A picture's rect: the object's rect with room for its shadow, snapped to whole points."""
    x, y, w, h = r
    x0, y0 = math.floor(x - left), math.floor(y - top)
    return [x0, y0, math.ceil(x + w + right) - x0, math.ceil(y + h + bottom) - y0]


def write_meta(face):
    """night-<face>.json: the layout and every picture's rect. A run limited to
    a prefix keeps the other pictures' entries."""
    path = os.path.join(OUT, 'night-%s.json' % face)
    old = {}
    if ONLY and os.path.exists(path):
        with open(path) as fh:
            old = json.load(fh).get('sprites', {})
    old.update(SPRITES)
    with open(path, 'w') as fh:
        json.dump(dict(scale=PX, pointsPerUnit=PT, layout=LAYOUT, sprites=old), fh, indent=1, ensure_ascii=False, sort_keys=True)
    print('done', len(SPRITES))
