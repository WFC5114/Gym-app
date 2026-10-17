# Renders one TRAIN face mockup in Blender (Cycles). Units: 1 = 100 pt, the
# same as the app's World. Face-local (px, py) pt maps to x = px/100 - 2.2,
# z = 4.78 - py/100. The face plate's front is the y = 0 plane; the camera is
# orthographic, in front at -y, like the app's.
#   python3 scene.py <concept A|B|C> <out.png> <pixels per pt> <samples>
import bpy, bmesh, math, os, random, sys
from mathutils import Vector

concept, out, ppp, samples = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../App/Fonts/Unbounded-Black.ttf')
FW, FH = 4.40, 9.56

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
col = scene.collection


def P(px, py, y=0.0):
    return Vector((px / 100 - FW / 2, y, FH / 2 - py / 100))


def hexrgb(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def mat(name, color, rough=0.4, metal=0.0, coat=0.0, coat_rough=0.1, transmission=0.0, ior=1.45, bump=0.0, bump_scale=60):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = hexrgb(color) if isinstance(color, int) else color
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = coat_rough
    b.inputs['Transmission Weight'].default_value = transmission
    b.inputs['IOR'].default_value = ior
    if bump:
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = bump_scale
        n.inputs['Detail'].default_value = 2
        bp = nt.nodes.new('ShaderNodeBump')
        bp.inputs['Strength'].default_value = bump
        nt.links.new(n.outputs['Fac'], bp.inputs['Height'])
        nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    return m


def obj(name, mesh, material=None, loc=(0, 0, 0), smooth=True):
    o = bpy.data.objects.new(name, mesh)
    col.objects.link(o)
    o.location = loc
    if material:
        o.data.materials.append(material)
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def rounded_box(name, size, radius, material, loc, segments=8):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    o = obj(name, me, material, loc, smooth=False)
    bev = o.modifiers.new('bevel', 'BEVEL')
    bev.width = radius
    bev.segments = segments
    bev.limit_method = 'NONE'
    bev.harden_normals = False
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def spline(points, n):
    """Catmull-Rom through (z, r) points, n samples per span."""
    out = []
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                     + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
    out.append(points[-1])
    return out


def lathe(name, profile, material, loc, seg=128, cap_bottom=True, cap_top=True):
    """Revolves (z, r) pairs, bottom to top, about the local z axis."""
    bm = bmesh.new()
    rings = []
    for z, r in profile:
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    if cap_bottom:
        c = bm.verts.new((0, 0, profile[0][0]))
        for k in range(seg):
            bm.faces.new((rings[0][(k + 1) % seg], rings[0][k], c))
    if cap_top:
        c = bm.verts.new((0, 0, profile[-1][0]))
        for k in range(seg):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % seg], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    return obj(name, me, material, loc)


def cylinder(name, r, h, material, loc, bevel=0.0, seg=96, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    o = obj(name, me, material, loc, smooth=False)
    if rot:
        o.rotation_euler = rot
    if bevel:
        b = o.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = 6
        b.limit_method = 'ANGLE'
    for p in o.data.polygons:
        p.use_smooth = abs(p.normal.z) < 0.99
    return o


def torus(name, R, r, material, loc, rot=(0, 0, 0)):
    bm = bmesh.new()
    seg, ring = 128, 32
    verts = [[bm.verts.new(((R + r * math.cos(2 * math.pi * j / ring)) * math.cos(2 * math.pi * i / seg),
                             (R + r * math.cos(2 * math.pi * j / ring)) * math.sin(2 * math.pi * i / seg),
                             r * math.sin(2 * math.pi * j / ring))) for j in range(ring)] for i in range(seg)]
    for i in range(seg):
        for j in range(ring):
            bm.faces.new((verts[i][j], verts[(i + 1) % seg][j], verts[(i + 1) % seg][(j + 1) % ring], verts[i][(j + 1) % ring]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    o = obj(name, me, material, loc)
    o.rotation_euler = rot
    return o


def sphere(name, r, material, loc, seg=48):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    return obj(name, me, material, loc)


def text(body, size, material, loc, extrude=0.12, bevel=0.02, align='LEFT'):
    cu = bpy.data.curves.new('t', 'FONT')
    cu.body = body
    cu.font = bpy.data.fonts.load(FONT)
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    cu.align_x = align
    o = bpy.data.objects.new('text', cu)
    col.objects.link(o)
    o.data.materials.append(material)
    o.rotation_euler = (math.pi / 2, 0, 0)
    o.location = loc
    return o


# ---------- materials ----------
CREAM = 0xFFF4E0
m_face = mat('face', 0x2340E0, rough=0.55, coat=0.25, coat_rough=0.3)
m_cream = mat('cream', CREAM, rough=0.32, coat=0.7, coat_rough=0.12)
m_glass = mat('glass', [1, 1, 1, 1], rough=0.02, transmission=1.0, ior=1.47)
# Glass lets shadow rays through so the sand inside is lit (no caustics needed).
_nt = m_glass.node_tree
_lp = _nt.nodes.new('ShaderNodeLightPath')
_tr = _nt.nodes.new('ShaderNodeBsdfTransparent')
_mix = _nt.nodes.new('ShaderNodeMixShader')
_out = _nt.nodes['Material Output']
_nt.links.new(_lp.outputs['Is Shadow Ray'], _mix.inputs['Fac'])
_nt.links.new(_nt.nodes['Principled BSDF'].outputs['BSDF'], _mix.inputs[1])
_nt.links.new(_tr.outputs['BSDF'], _mix.inputs[2])
_nt.links.new(_mix.outputs['Shader'], _out.inputs['Surface'])
m_sand = mat('sand', 0xF2B33D, rough=0.55, bump=0.35, bump_scale=180)
m_brass = mat('brass', 0xE0A84A, rough=0.22, metal=1.0)
m_chrome = mat('chrome', 0xE8EAF0, rough=0.08, metal=1.0)
m_navy = mat('navy', 0x0E1A5C, rough=0.35, coat=0.6, coat_rough=0.15)
m_orange = mat('orange', 0xFF6A1A, rough=0.3, coat=0.8, coat_rough=0.08)
m_dark = mat('dark', 0x161A2E, rough=0.45, coat=0.4)

# ---------- face, hero, keys ----------
MIN = concept in 'DEFG'  # Wei, 13 Oct: elegant but minimal
if MIN:
    m_face = mat('faceMin', 0x2340E0, rough=0.62, coat=0.08, coat_rough=0.4)
    m_tone = mat('tone', 0x1D36C4, rough=0.55, coat=0.15)
    m_satin = mat('satin', CREAM, rough=0.45, coat=0.3, coat_rough=0.2)
rounded_box('plate', (FW, 0.2, FH), 0.08, m_face, (0, 0.1, 0))
text('2:08', 1.30, m_cream, P(36, 232, -0.10), extrude=0.10, bevel=0.025)
if MIN:
    # Quiet keys: tone-on-tone pills for the small actions, one slim cream pill for SET DONE.
    rounded_box('keyA', (1.74, 0.12, 0.46), 0.059, m_tone, P(36 + 87, 792, -0.06).to_tuple(), segments=12)
    rounded_box('keyB', (1.74, 0.12, 0.46), 0.059, m_tone, P(404 - 87, 792, -0.06).to_tuple(), segments=12)
    rounded_box('keyDone', (3.68, 0.16, 0.62), 0.079, m_satin, P(220, 868, -0.08).to_tuple(), segments=12)
else:
    rounded_box('keyA', (1.78, 0.36, 0.64), 0.16, m_navy, P(36 + 89, 779, -0.18).to_tuple())
    rounded_box('keyB', (1.78, 0.36, 0.64), 0.16, m_navy, P(404 - 89, 779, -0.18).to_tuple())
    rounded_box('keyDone', (3.68, 0.44, 0.80), 0.2, m_cream, P(220, 866, -0.22).to_tuple())

# ---------- the hourglass ----------
CY_PT = {'A': 545, 'B': 528, 'C': 520, 'D': 540, 'E': 540, 'F': 545, 'G': 540}[concept]
CX, CZ = P(220, CY_PT).x, P(220, CY_PT).z
before = set(bpy.data.objects)
Y = -0.95  # stands proud of the face


def bulb_profile(h, rmax, neck, top_r):
    half = [(0.0, neck), (0.07 * h, neck * 1.25), (0.18 * h, rmax * 0.45), (0.33 * h, rmax * 0.85),
            (0.5 * h, rmax), (0.72 * h, rmax * 0.93), (0.88 * h, rmax * 0.78), (h, top_r)]
    up = spline(half, 10)
    down = [(-z, r) for z, r in reversed(up[1:])]
    return down + up


def sand_top(prof_inner, level, neck_z):
    # Sand resting in the top bulb: from the neck up to `level`, with a dished surface.
    pts = [(z, r) for z, r in prof_inner if neck_z <= z <= level]
    r_level = pts[-1][1]
    return [(neck_z - 0.001, 0.0)] + pts + [(level - 0.08, r_level * 0.5), (level - 0.12, 0.0)]


def heap(prof_inner, floor_z, fill_z, apex_z):
    pts = [(z, r) for z, r in prof_inner if floor_z <= z <= fill_z]
    r_fill = pts[-1][1]
    return [(floor_z, 0.0)] + pts + [(fill_z + (apex_z - fill_z) * 0.35, r_fill * 0.55), (apex_z, 0.02), (apex_z + 0.005, 0.0)]


def classic_glass(h, rmax, neck, top_r, wall, loc, top_level, fill_z, apex_z):
    outer = bulb_profile(h, rmax, neck, top_r)
    inner = [(z, max(r - wall, 0.012)) for z, r in outer]
    lathe('glass_out', outer, m_glass, loc)
    gi = lathe('glass_in', [(z * 0.985, r) for z, r in inner], m_glass, loc)
    for p in gi.data.polygons:
        p.flip()
    inner_s = [(z, r - 0.006) for z, r in inner]
    lathe('sand_top', sand_top(inner_s, top_level, 0.05), m_sand, loc)
    lathe('sand_heap', heap(inner_s, -h * 0.97, fill_z, apex_z), m_sand, loc)
    cylinder('stream', 0.011, 0.05 - apex_z, m_sand, (loc[0], loc[1], loc[2] + (0.05 + apex_z) / 2), seg=24)


m_white = mat('sandWhite', 0xD9CBB2, rough=0.8, bump=0.5, bump_scale=260)
m_char = mat('sandChar', 0x2A2C33, rough=0.6, bump=0.3, bump_scale=200)
m_champ = mat('champagne', 0xD8C3A0, rough=0.3, metal=1.0)
m_matte = mat('matteCream', CREAM, rough=0.62, coat=0.1)


def glass(half, wall, loc, top_level, fill_z, apex_z, floor_z, sand, caps=True):
    up = spline(half, 12)
    outer = [(-z, r) for z, r in reversed(up[1:])] + up
    inner = [(z * 0.99, max(r - wall, 0.012)) for z, r in outer]
    lathe('glass_out', outer, m_glass, loc, cap_bottom=caps, cap_top=caps)
    gi = lathe('glass_in', inner, m_glass, loc, cap_bottom=caps, cap_top=caps)
    for p in gi.data.polygons:
        p.flip()
    inner_s = [(z, r - 0.006) for z, r in inner]
    lathe('sand_top', sand_top(inner_s, top_level, 0.05), sand, loc)
    lathe('sand_heap', heap(inner_s, floor_z, fill_z, apex_z), sand, loc)
    cylinder('stream', 0.009, 0.05 - apex_z, sand, (loc[0], loc[1], loc[2] + (0.05 + apex_z) / 2), seg=24)


if concept == 'D':
    # Teardrop: one seamless glass form, no frame, resting in a small cream cup.
    loc = (CX, Y, CZ)
    glass([(0, 0.05), (0.07, 0.065), (0.2, 0.2), (0.4, 0.36), (0.62, 0.42), (0.85, 0.4), (1.05, 0.33), (1.2, 0.2), (1.29, 0.07), (1.31, 0.0)],
          0.035, loc, top_level=0.62, fill_z=-0.86, apex_z=-0.6, floor_z=-1.26, sand=m_white)
    cylinder('cup', 0.13, 0.08, m_matte, (CX, Y, CZ - 1.33), bevel=0.03, seg=64)
    cylinder('disc', 0.4, 0.035, m_matte, (CX, Y, CZ - 1.385), bevel=0.012)

elif concept == 'E':
    # Orbit: two glass spheres hung on one thin champagne hoop.
    loc = (CX, Y, CZ)
    glass([(0, 0.045), (0.05, 0.08), (0.15, 0.3), (0.3, 0.46), (0.55, 0.53), (0.8, 0.46), (0.95, 0.3), (1.05, 0.1), (1.09, 0.0)],
          0.035, loc, top_level=0.52, fill_z=-0.72, apex_z=-0.46, floor_z=-1.02, sand=m_white)
    Rh = 1.34
    torus('hoop', Rh, 0.022, m_champ, (CX, Y, CZ), rot=(math.pi / 2, 0, 0))
    for s in (1, -1):
        cylinder('hanger', 0.016, Rh - 1.07, m_champ, (CX, Y, CZ + s * (1.07 + (Rh - 1.07) / 2)), seg=24)
    rounded_box('foot', (0.7, 0.16, 0.05), 0.02, m_matte, (CX, Y, CZ - Rh - 0.045))

elif concept == 'F':
    # Column: straight glass between two thin cream discs, one slender rod behind, dark sand.
    loc = (CX, Y, CZ)
    glass([(0, 0.06), (0.06, 0.08), (0.18, 0.3), (0.3, 0.4), (0.45, 0.42), (1.0, 0.42), (1.12, 0.42)],
          0.035, loc, top_level=0.72, fill_z=-0.78, apex_z=-0.5, floor_z=-1.1, sand=m_char)
    for s in (1, -1):
        cylinder('disc', 0.52, 0.06, m_matte, (CX, Y, CZ + s * 1.15), bevel=0.02)
    cylinder('rod', 0.018, 2.3, m_champ, (CX, Y + 0.47, CZ), seg=24)

elif concept == 'G':
    # Desk hourglass (Wei's reference photos, 13 Oct): square dark-wood plates,
    # four matte black posts with brass collars, round clear bulbs, fine white sand.
    m_wood = mat('walnut', 0x3A2418, rough=0.55, coat=0.08, coat_rough=0.4)
    nt = m_wood.node_tree
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.inputs['Scale'].default_value = 1.6
    wave.inputs['Distortion'].default_value = 4.0
    wave.inputs['Detail'].default_value = 3.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = hexrgb(0x1E120C)
    ramp.color_ramp.elements[1].color = hexrgb(0x3A2316)
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], nt.nodes['Principled BSDF'].inputs['Base Color'])
    m_black = mat('blackMatte', 0x0E0F12, rough=0.72, coat=0.0)
    m_sandG = mat('sandFine', 0xC9C1B4, rough=0.9, bump=0.5, bump_scale=320)
    loc = (CX, Y, CZ)
    glass([(0, 0.04), (0.06, 0.07), (0.15, 0.27), (0.3, 0.44), (0.5, 0.52), (0.7, 0.5), (0.85, 0.42), (0.95, 0.3), (1.0, 0.2)],
          0.03, loc, top_level=0.55, fill_z=-0.78, apex_z=-0.52, floor_z=-0.97, sand=m_sandG)
    side, thick = 1.22, 0.13
    post_xy = 0.5
    for s in (1, -1):
        cylinder('collar', 0.24, 0.05, m_black, (CX, Y, CZ + s * 1.02), bevel=0.01)
        rounded_box('plate', (side, side, thick), 0.03, m_wood, (CX, Y, CZ + s * (1.045 + thick / 2)))
    span = 2 * 1.045
    for px in (-post_xy, post_xy):
        for py in (-post_xy, post_xy):
            cylinder('post', 0.032, span, m_black, (CX + px, Y + py, CZ), seg=32)
            for s in (1, -1):
                cylinder('sleeve', 0.042, 0.13, m_brass, (CX + px, Y + py, CZ + s * (1.045 - 0.065)), seg=32)
                # Dome nuts on top, round feet underneath.
                sphere('nut', 0.055, m_black, (CX + px, Y + py, CZ + s * (1.045 + thick + 0.01)), seg=32)

elif concept == 'A':
    # Classic lab hourglass: thick glass, cream turned caps, three brass posts.
    h = 1.12
    loc = (CX, Y, CZ)
    classic_glass(h, 0.62, 0.075, 0.42, 0.06, loc, top_level=0.55, fill_z=-0.78, apex_z=-0.42)
    for s in (1, -1):
        z = CZ + s * (h + 0.13)
        cylinder('cap', 0.82, 0.24, m_cream, (CX, Y, z), bevel=0.06)
        cylinder('lip', 0.6, 0.08, m_cream, (CX, Y, z - s * 0.15), bevel=0.03)
        torus('groove', 0.82, 0.018, m_dark, (CX, Y, z + s * 0.035))
    for ang in (90, 210, 330):
        a = math.radians(ang)
        cylinder('post', 0.055, 2 * h + 0.1, m_brass, (CX + 0.72 * math.cos(a), Y + 0.72 * math.sin(a), CZ), bevel=0.0, seg=48)
        for s in (1, -1):
            sphere('knob', 0.075, m_brass, (CX + 0.72 * math.cos(a), Y + 0.72 * math.sin(a), CZ + s * (h + 0.03)))

elif concept == 'B':
    # Candy capsule: one pinched glass pill, glossy bead "sand", orange cradle.
    h = 1.32
    R = 0.68
    half = [(0.0, 0.165), (0.08, 0.19), (0.22, 0.4), (0.45, 0.62), (0.7, R), (0.95, 0.62), (1.15, 0.45), (1.27, 0.24), (h, 0.0)]
    up = spline(half, 12)
    outer = [(-z, r) for z, r in reversed(up[1:])] + up
    loc = (CX, Y, CZ)
    lathe('glass_out', outer, m_glass, loc, cap_bottom=False, cap_top=False)
    gi = lathe('glass_in', [(z * 0.93, max(r - 0.08, 0.03)) for z, r in outer], m_glass, loc, cap_bottom=False, cap_top=False)
    for p in gi.data.polygons:
        p.flip()
    inner = [(z * 0.93, max(r - 0.09, 0.0)) for z, r in outer]

    def r_at(z):
        best = min(inner, key=lambda p: abs(p[0] - z))
        return best[1]
    rng = random.Random(7)
    beads = [mat('bead%d' % i, c, rough=0.18, coat=1.0, coat_rough=0.05) for i, c in enumerate([0xFFB21E, 0xFF8A1E, 0xFFD25A])]
    br = 0.062
    placed = []

    def pack(zlo, zhi, n):
        tries = 0
        while n and tries < 60000:
            tries += 1
            z = rng.uniform(zlo, zhi)
            rr = r_at(z) - br
            if rr <= 0:
                continue
            a, d = rng.uniform(0, 2 * math.pi), rr * math.sqrt(rng.random())
            p = Vector((d * math.cos(a), d * math.sin(a), z))
            if all((p - q).length > 2 * br * 0.98 for q in placed):
                placed.append(p)
                n -= 1
    # Bottom heap first (lowest layers first so it reads as a settled pile).
    for k in range(14):
        zlo = -1.2 + k * 0.05
        pack(zlo, zlo + 0.05, 60)
    nb = len(placed)
    for k in range(9):
        zlo = 0.12 + k * 0.05
        pack(zlo, zlo + 0.05, 60)
    pack(-0.02, 0.06, 1)  # one bead falling through the neck
    proto = [sphere('bead', br, b, (0, 0, 0), seg=24) for b in beads]
    for i, p in enumerate(placed):
        o = bpy.data.objects.new('b', proto[i % 3].data)
        col.objects.link(o)
        o.location = (CX + p.x, Y + p.y, CZ + p.z)
    for o in proto:
        bpy.data.objects.remove(o)
    torus('collar', 0.2, 0.06, m_cream, (CX, Y, CZ))
    # Cradle: a glossy orange cup and foot under the bottom dome.
    cradle = [(-0.15, 0.0), (-0.15, 0.62), (-0.08, 0.66), (0.05, 0.6), (0.2, 0.58), (0.32, 0.64), (0.36, 0.6), (0.36, 0.0)]
    lathe('cradle', spline(cradle, 6), m_orange, (CX, Y, CZ - h - 0.17))

elif concept == 'C':
    # Gimbal: the hourglass swings on an axle inside a chrome ring with minute ticks.
    h = 0.9
    loc = (CX, Y, CZ)
    classic_glass(h, 0.52, 0.065, 0.36, 0.05, loc, top_level=0.45, fill_z=-0.63, apex_z=-0.34)
    for s in (1, -1):
        cylinder('cap', 0.6, 0.16, m_cream, (CX, Y, CZ + s * (h + 0.09)), bevel=0.05)
    Rr = 1.26
    torus('ring', Rr, 0.075, m_chrome, (CX, Y, CZ), rot=(math.pi / 2, 0, 0))
    for k in range(12):
        a = 2 * math.pi * k / 12
        L = 0.16 if k % 3 == 0 else 0.09
        t = rounded_box('tick', (0.035, 0.05, L), 0.012, m_cream,
                        (CX + (Rr - 0.13 - L / 2) * math.sin(a), Y - 0.02, CZ + (Rr - 0.13 - L / 2) * math.cos(a)))
        t.rotation_euler = (0, a, 0)
    for s in (1, -1):
        cylinder('axle', 0.05, Rr - 0.56, m_chrome, (CX + s * (0.56 + (Rr - 0.56) / 2), Y, CZ), rot=(0, math.pi / 2, 0), seg=32)
        sphere('hub', 0.11, m_orange, (CX + s * 0.54, Y, CZ))
    cylinder('stem', 0.09, 0.3, m_chrome, (CX, Y, CZ - Rr - 0.15), seg=48)
    cylinder('foot', 0.72, 0.16, m_cream, (CX, Y, CZ - Rr - 0.34), bevel=0.05)

# Grow the mechanism about its centre (the glass is 1.25x the first test). The
# desk hourglass is also turned and tipped toward the camera so all four posts
# and the tops of its plates read in the orthographic view.
K = 1.25
pivot = bpy.data.objects.new('pivot', None)
col.objects.link(pivot)
pivot.location = (CX, Y, CZ)
for o in set(bpy.data.objects) - before - {pivot}:
    o.parent = pivot
    o.location = o.location - Vector((CX, Y, CZ))
pivot.scale = (K, K, K)
pivot.rotation_mode = 'ZYX'
pivot.rotation_euler = (math.radians(10), 0, math.radians(28)) if concept == 'G' else (0, 0, 0)

# ---------- light and camera ----------
world = bpy.data.worlds.new('w')
scene.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.03, 0.035, 0.06, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0


def area(name, loc, target, size, energy, sx=None):
    l = bpy.data.lights.new(name, 'AREA')
    l.energy = energy
    if sx:
        l.shape = 'RECTANGLE'
        l.size, l.size_y = sx, size
    else:
        l.size = size
    o = bpy.data.objects.new(name, l)
    col.objects.link(o)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return o


area('key', (-6, -9, 9), (0, 0, 0), 9 if MIN else 5, 1500 if MIN else 1700)
area('fill', (3, -10, 1), (0, 0, 0), 8, 700)
# Minimal: rims further forward so they catch the glass edges, not the plate.
rim_y, rim_e = (-3.0, 650) if MIN else (-0.6, 900)
area('rimL', (-3.2, rim_y, 0), (CX, Y, CZ), 6, rim_e, sx=0.6)
area('rimR', (3.2, rim_y, 0), (CX, Y, CZ), 6, rim_e, sx=0.6)
area('top', (0, -2, 6), (CX, Y, CZ), 3, 500)

cam = bpy.data.cameras.new('cam')
cam.type = 'ORTHO'
cam.ortho_scale = FH
camo = bpy.data.objects.new('cam', cam)
col.objects.link(camo)
camo.location = (0, -30, 0)
camo.rotation_euler = (math.pi / 2, 0, 0)
scene.camera = camo

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = samples
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 16
scene.cycles.transmission_bounces = 16
scene.cycles.glossy_bounces = 8
scene.cycles.caustics_reflective = False
scene.cycles.caustics_refractive = False
scene.render.resolution_x = int(440 * ppp)
scene.render.resolution_y = int(956 * ppp)
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.render.filepath = out
scene.render.image_settings.file_format = 'PNG'
bpy.ops.render.render(write_still=True)
print('rendered', out)
