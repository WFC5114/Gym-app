# Claymorphism round for the other two faces (Wei, 14 Oct 2026: "redo jar and
# hourglass in the same style and the whole app should be the same"). Same
# clay kit as the BODY mannequin (design/mockups/body/mannequin.py, look clay):
# solid colours, satin sheen, a fine pressed surface, and real hardware detail.
# Mockup renders only; not the app.
#   python3 objects.py <hourglass|jar> <out.png> [samples] [scale]
import bpy, bmesh, math, sys, os

WHAT = sys.argv[1]
OUT = os.path.abspath(sys.argv[2])
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 64
SCALE = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def lin(h):
    c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


def clay(name, color, rough=0.42, coat=0.3, sss=0.15, bump=0.07):
    """The shared clay: one colour, soft sheen, a fine hand-pressed surface."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = 0.2
    b.inputs['Subsurface Weight'].default_value = sss
    b.inputs['Subsurface Radius'].default_value = (0.05, 0.03, 0.02)
    b.inputs['Subsurface Scale'].default_value = 0.03
    coord = nt.nodes.new('ShaderNodeTexCoord')
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 260.0
    noise.inputs['Detail'].default_value = 6.0
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = bump
    bp.inputs['Distance'].default_value = 0.0004
    nt.links.new(coord.outputs['Object'], noise.inputs['Vector'])
    nt.links.new(noise.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    return m


def glass_mat(name, tint):
    """Thick candy glass: clear, glossy, a faint tint so its edges read."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(tint)
    b.inputs['Roughness'].default_value = 0.04
    b.inputs['Transmission Weight'].default_value = 1.0
    b.inputs['IOR'].default_value = 1.45
    b.inputs['Coat Weight'].default_value = 0.4
    return m


def plain(name, color, rough=0.75):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = rough
    return m


CREAM = clay('cream', 0xF2C38C)
ORANGE = clay('orange', 0xF0904E)
RUST = clay('rust', 0xB8703C, rough=0.55, coat=0)
BUTTER = clay('butter', 0xFFD27A, rough=0.36)
PALE = clay('pale', 0xF4EEE6)
INDIGO = clay('indigo', 0x2A1257, rough=0.5)
LILAC = clay('lilac', 0xB894FF, coat=0.1)


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


def lathe(name, profile, segments=64, loop=False):
    """Surface of revolution about z from (z, r) pairs. A loop closes on itself."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / segments), r * math.sin(2 * math.pi * k / segments), z))
              for k in range(segments)] for z, r in profile]
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if loop else [])
    for a, b in pairs:
        for k in range(segments):
            bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
    if not loop:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def ellipsoid(name, rx, ry, rz):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1.0)
    for v in bm.verts:
        v.co.x *= rx
        v.co.y *= ry
        v.co.z *= rz
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def block(name, w, d, h, bevel=0.02, top=1.0, bottom=1.0, sub=2):
    """A rounded clay block of half sizes w, d, h, tapering bottom to top."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    for v in bm.verts:
        s = bottom + (top - bottom) * (v.co.z + 1) / 2
        v.co.x *= w * s
        v.co.y *= d * s
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


def spindle(name, length, r_top, r_bot, grooves=(0.13, 0.87)):
    """A turned post standing from z 0 to length, with lathe-cut grooves."""
    prof = []
    n = 96
    for i in range(n + 1):
        t = i / n
        base = r_bot + (r_top - r_bot) * t
        end = min(t, 1 - t) / 0.04
        cap = math.sqrt(max(0.0, 1 - (1 - min(end, 1)) ** 2))
        groove = sum(0.12 * base * math.exp(-((t - g) * length / 0.004) ** 2) for g in grooves)
        prof.append((length * t, max((base - groove) * cap, 1e-4)))
    return lathe(name, prof, 48)


def screw(name, parent, loc, rot, r=0.008):
    h = link(lathe(name, [(0, 1e-4), (0, r), (r * 0.25, r * 0.92), (r * 0.45, r * 0.6), (r * 0.52, 1e-4)], 32), parent, BUTTER)
    h.location, h.rotation_euler = loc, rot
    for a in (0, math.pi / 2):
        sl = link(block(name + 'Slot', r * 0.8, r * 0.13, r * 0.2, bevel=0, sub=0), h, RUST, smooth=False)
        sl.location = (0, 0, r * 0.5)
        sl.rotation_euler = (0, 0, a)
    return h


def raised_text(name, text, size, parent, mat, loc, rot=(0, 0, 0), depth=0.003):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    cu.extrude = depth
    cu.bevel_depth = depth * 0.35
    cu.bevel_resolution = 2
    o = link(bpy.data.objects.new(name, cu), parent, mat, smooth=False)
    o.location, o.rotation_euler = loc, rot
    return o


def knurled_knob(name, parent, loc, rot, r=0.03, length=0.03, ribs=24):
    """A grip knob on its side, ribbed round its barrel: the rest setter."""
    k = link(lathe(name, [(0, 1e-4), (0, r * 0.7), (0.004, r), (length - 0.004, r), (length, r * 0.8), (length, 1e-4)], 48), parent, BUTTER)
    k.location, k.rotation_euler = loc, rot
    for i in range(ribs):
        a = 2 * math.pi * i / ribs
        rib = link(block('rib', 0.0025, 0.0025, length * 0.36, bevel=0.0015, sub=1), k, BUTTER)
        rib.location = (r * math.cos(a), r * math.sin(a), length / 2)
    cap = link(ellipsoid('knobCap', r * 0.55, r * 0.55, 0.006), k, ORANGE)
    cap.location = (0, 0, length)
    return k


root = empty('root', (0, 0, 0))

# ---------------------------------------------------------------------------
if WHAT == 'hourglass':
    backdrop = 0x2340E0
    # Turned 28° and tipped 10° toward the camera, like the app's TRAIN face.
    pivot = empty('pivot', (0, 0, 0.5), root, rot=(math.radians(10), 0, math.radians(-28)))
    side, thick = 0.29, 0.035
    zb, zt = -0.43, 0.43            # inner faces of the plates, from the centre
    for s, z in ((-1, zb), (1, zt)):
        # Layered plate: an indigo slab, a cream panel with a beaded edge.
        slab = link(block('slab', side, side, thick, bevel=0.03), pivot, INDIGO)
        slab.location = (0, 0, z + s * thick)
        panel = link(block('panel', side - 0.035, side - 0.035, 0.012, bevel=0.012), pivot, CREAM)
        panel.location = (0, 0, z + s * (2 * thick + 0.008))
        # Turned cup where the bulb meets the plate.
        cup = link(lathe('cup', [(0, 0.075), (0, 0.11), (0.01 * -s, 0.114), (0.022 * -s, 0.095), (0.03 * -s, 0.075)], 64, loop=True), pivot, ORANGE)
        cup.location = (0, 0, z)
    # Bun feet under the base, dome nuts on top.
    for px in (-0.21, 0.21):
        for py in (-0.21, 0.21):
            f = link(ellipsoid('foot', 0.04, 0.04, 0.02), pivot, BUTTER)
            f.location = (px, py, zb - 2 * thick - 0.02)
            nut = link(ellipsoid('nut', 0.03, 0.03, 0.026), pivot, BUTTER)
            nut.location = (px, py, zt + 2 * thick + 0.02)
            # Turned post with grooves, sleeves and socket rings.
            post = link(spindle('post', zt - zb, 0.016, 0.016, grooves=(0.08, 0.5, 0.92)), pivot, ORANGE)
            post.location = (px, py, zb)
            for s, z in ((1, zb), (-1, zt)):
                sleeve = link(lathe('sleeve', [(0, 1e-4), (0, 0.026), (0.006, 0.028), (0.05, 0.024), (0.06, 0.02), (0.06, 1e-4)], 48), pivot, BUTTER)
                sleeve.location = (px, py, z)
                sleeve.rotation_euler = (0 if s > 0 else math.pi, 0, 0)
    # Glass (Wei, 14 Oct: smoother, rounder, thicker): two near-round bulbs on a
    # dense Catmull-Rom profile, turned at 192 segments, with a thick wall
    # offset along the surface normal and a heavy neck.
    knots = [(0.0, 0.032), (0.012, 0.036), (0.03, 0.068), (0.06, 0.115), (0.1, 0.158), (0.15, 0.186),
             (0.21, 0.195), (0.27, 0.186), (0.32, 0.162), (0.36, 0.128), (0.39, 0.096), (0.41, 0.08), (0.425, 0.076)]

    def catmull(pts, n=16):
        p = [pts[0]] + pts + [pts[-1]]
        out = []
        for i in range(1, len(p) - 2):
            for j in range(n):
                t = j / n
                out.append(tuple(0.5 * (2 * p[i][c] + (-p[i - 1][c] + p[i + 1][c]) * t
                                        + (2 * p[i - 1][c] - 5 * p[i][c] + 4 * p[i + 1][c] - p[i + 2][c]) * t * t
                                        + (-p[i - 1][c] + 3 * p[i][c] - 3 * p[i + 1][c] + p[i + 2][c]) * t ** 3) for c in (0, 1)))
        out.append(pts[-1])
        return out
    outer = catmull(knots)
    GW = 0.022  # glass wall

    def offset_in(prof):
        res = []
        for i, (z, r) in enumerate(prof):
            z0, r0 = prof[max(i - 1, 0)]
            z1, r1 = prof[min(i + 1, len(prof) - 1)]
            tz, tr = z1 - z0, r1 - r0
            L = math.hypot(tz, tr) or 1
            nz, nr = -tr / L, tz / L      # outward normal in (z, r)
            res.append((z - nz * GW, max(r - nr * GW, 0.007)))
        return res
    prof = [(-z, r) for z, r in reversed(outer)] + outer[1:]
    inner = offset_in(prof)
    glass = link(lathe('glass', prof + list(reversed(inner)), 192, loop=True), pivot, glass_mat('glass', 0xFFFFFF))
    ring = link(lathe('neckRing', [(-0.012, 0.034), (-0.012, 0.04), (0.012, 0.04), (0.012, 0.034)], 64, loop=True), pivot, BUTTER)
    inner_top = [(z, r) for z, r in inner if z >= 0]
    # Sand: pale clay, part drained. A mound up top, a heap below, a thin stream.
    SAND = clay('sand', 0xFFF2D6, rough=0.8, coat=0.0, bump=0.25)

    def r_at(z):
        z = abs(z)
        pts = sorted(inner_top)
        for (z0, r0), (z1, r1) in zip(pts, pts[1:]):
            if z0 <= z <= z1:
                return (r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-6)) - 0.002
        return 0.008
    top_level = 0.24
    top = [(0.03, 0.008)] + [(z, r_at(z)) for z in [0.03 + i * (top_level - 0.03) / 20 for i in range(1, 21)]]
    top.append((top_level + 0.012, r_at(top_level) * 0.6))
    top.append((top_level + 0.018, 1e-4))
    link(lathe('sandTop', [(top[0][0], 1e-4)] + top, 96), pivot, SAND)
    fill = -0.27
    heap = [(-0.4, 1e-4)]
    for i in range(0, 15):
        z = -0.4 + i * (fill + 0.4) / 14
        heap.append((z, r_at(z)))
    heap += [(fill + 0.03, r_at(fill) * 0.55), (fill + 0.065, r_at(fill) * 0.15), (fill + 0.075, 1e-4)]
    link(lathe('sandHeap', heap, 96), pivot, SAND)
    link(lathe('stream', [(fill + 0.07, 1e-4), (fill + 0.07, 0.0025), (0.03, 0.0025), (0.03, 1e-4)], 16), pivot, SAND)
    # Base front: raised minute ticks and a knurled knob to set the rest.
    for i in range(7):
        x = -0.15 + i * 0.05
        t = link(block('tick', 0.003, 0.004, 0.01 if i % 2 == 0 else 0.006, bevel=0.002, sub=1), pivot, BUTTER)
        t.location = (x, -side - 0.003, zb - thick)
    raised_text('restLabel', 'REST', 0.028, pivot, BUTTER, (0, -side - 0.001, zb - thick - 0.02), rot=(math.pi / 2, 0, 0))
    knurled_knob('setter', pivot, (side + 0.004, 0.08, zb - thick), (0, math.pi / 2, 0))
    cam_center, ortho = 0.5, 1.5

# ---------------------------------------------------------------------------
elif WHAT == 'jar':
    backdrop = 0xE8461E
    pivot = empty('pivot', (0, 0, 0), root, rot=(math.radians(8), 0, math.radians(-14)))
    W, D, H, wall = 0.292, 0.172, 0.36, 0.045  # Wei: thicker glass; same inside
    base_top = 0.1
    # Glass tank: a rounded box, open at the top, with thick walls.
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    for v in bm.verts:
        v.co.x *= W
        v.co.y *= D
        v.co.z = (v.co.z + 1) * H
    top_face = [f for f in bm.faces if all(v.co.z > H * 1.99 for v in f.verts)]
    bmesh.ops.delete(bm, geom=top_face, context='FACES')
    me = bpy.data.meshes.new('tank')
    bm.to_mesh(me)
    bm.free()
    tank = link(bpy.data.objects.new('tank', me), pivot, glass_mat('glass', 0xFFF1E8))
    tank.location = (0, 0, base_top)
    so = tank.modifiers.new('solid', 'SOLIDIFY')
    so.thickness = wall
    bv = tank.modifiers.new('bevel', 'BEVEL')
    bv.width, bv.segments = 0.03, 4
    sd = tank.modifiers.new('sub', 'SUBSURF')
    sd.levels = sd.render_levels = 2
    # Base: indigo plinth with a knurled butter band, bun feet and a plaque.
    plinth = link(block('plinth', W + 0.035, D + 0.035, 0.045, bevel=0.03), pivot, INDIGO)
    plinth.location = (0, 0, base_top - 0.045)
    band = link(block('band', W + 0.042, D + 0.042, 0.012, bevel=0.01), pivot, BUTTER)
    band.location = (0, 0, base_top - 0.045)
    for i in range(46):
        x = -W - 0.03 + i * (2 * W + 0.06) / 45
        for y in (-(D + 0.054), D + 0.054):
            r = link(block('knurl', 0.0022, 0.0022, 0.009, bevel=0.0012, sub=1), pivot, BUTTER)
            r.location = (x, y, base_top - 0.045)
    for px in (-W + 0.02, W - 0.02):
        for py in (-D + 0.01, D - 0.01):
            f = link(ellipsoid('foot', 0.035, 0.035, 0.018), pivot, BUTTER)
            f.location = (px, py, base_top - 0.095)
    plaque = link(block('plaque', 0.07, 0.004, 0.016, bevel=0.004), pivot, BUTTER)
    plaque.location = (0, -(D + 0.06), base_top - 0.07)
    raised_text('dietLabel', 'DIET', 0.02, plaque, INDIGO, (0, -0.005, 0), rot=(math.pi / 2, 0, 0), depth=0.0015)
    for x in (-0.058, 0.058):
        screw('plaqueScrew', plaque, (x, -0.004, 0), (math.pi / 2, 0, 0), r=0.004)
    # Mouth collar: cream clay with a seam, four corner screws.
    collar = link(block('collar', W + 0.025, D + 0.025, 0.022, bevel=0.018), pivot, CREAM)
    collar.location = (0, 0, base_top + 2 * H + 0.01)
    seam = link(block('collarSeam', W + 0.027, D + 0.027, 0.0025, bevel=0.002), pivot, RUST)
    seam.location = (0, 0, base_top + 2 * H + 0.01)
    hole = link(block('mouth', W - wall + 0.002, D - wall + 0.002, 0.03, bevel=0.01), pivot, None)
    bo = collar.modifiers.new('mouth', 'BOOLEAN')
    bo.operation, bo.object, bo.solver = 'DIFFERENCE', hole, 'EXACT'
    hole.location = collar.location
    hole.hide_render = True
    bo2 = seam.modifiers.new('mouth', 'BOOLEAN')
    bo2.operation, bo2.object, bo2.solver = 'DIFFERENCE', hole, 'EXACT'
    for x in (-W - 0.008, W + 0.008):
        for y in (-D - 0.008, D + 0.008):
            screw('collarScrew', pivot, (x, y, base_top + 2 * H + 0.033), (0, 0, 0), r=0.007)
    # Raised graduations on the front glass, and the TARGET flag.
    target_z = base_top + 2 * H * 0.74
    for q in range(1, 4):
        z = base_top + 2 * H * 0.74 * q / 4
        t = link(block('grad', 0.03, 0.003, 0.0035, bevel=0.002, sub=1), pivot, PALE)
        t.location = (W - 0.06, -D - 0.003, z)
    bar = link(block('targetBar', W * 0.9, 0.003, 0.004, bevel=0.002, sub=1), pivot, BUTTER)
    bar.location = (0, -D - 0.003, target_z)
    flag = link(block('flag', 0.05, 0.004, 0.014, bevel=0.004), pivot, BUTTER)
    flag.location = (-W + 0.07, -D - 0.006, target_z + 0.024)
    raised_text('targetText', 'TARGET', 0.014, flag, INDIGO, (0, -0.005, 0), rot=(math.pi / 2, 0, 0), depth=0.0012)
    # Food blocks: chunky clay by main macro, tumbled at angles on a pile.
    macro = {'carb': clay('carb', 0xE9B44C), 'protein': clay('protein', 0xC9874A), 'fat': clay('fat', 0xF6E7C8),
             'mixed': CREAM, 'quick': clay('quick', 0xFFD77A)}
    floor = wall
    pile = [('carb', -0.18, 0.0, 0.058, 0.05, floor + 0.05, 0.04), ('protein', -0.05, 0.0, 0.052, 0.05, floor + 0.05, -0.05),
            ('mixed', 0.1, 0.0, 0.068, 0.052, floor + 0.052, 0.03), ('quick', 0.21, 0.0, 0.032, 0.032, floor + 0.032, 0.0),
            ('fat', -0.12, 0.0, 0.046, 0.042, floor + 0.15, 0.32), ('carb', 0.03, 0.0, 0.05, 0.044, floor + 0.152, -0.22),
            ('protein', 0.18, 0.0, 0.042, 0.036, floor + 0.128, 0.42), ('mixed', -0.2, 0.0, 0.04, 0.038, floor + 0.14, -0.1),
            ('quick', -0.05, 0.0, 0.03, 0.03, floor + 0.235, 0.5), ('carb', 0.1, 0.0, 0.044, 0.04, floor + 0.24, 0.18)]
    for kind, x, y, w, h, z, ang in pile:
        b = link(block('food', w, 0.09, h, bevel=min(w, h) * 0.45), pivot, macro[kind])
        b.location = (x, y, base_top + z)
        b.rotation_euler = (0, ang, 0)
        # A raised label strip on each block's front: the tactile bit.
        lab = link(block('label', w * 0.6, 0.004, h * 0.22, bevel=0.003, sub=1), b, PALE)
        lab.location = (0, -0.092, 0)
    cam_center, ortho = 0.43, 1.1

# ---------------------------------------------------------------------------
plate = bpy.data.materials.new('plate')
plate.use_nodes = True
plate.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = lin(backdrop)
plate.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.75
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 1.2, 0.5), rotation=(math.pi / 2, 0, 0))
bpy.context.object.data.materials.append(plate)
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.06 if WHAT == 'jar' else -0.05))
bpy.context.object.data.materials.append(plate)

aim = empty('aim', (0, 0, cam_center))


def area(name, loc, size, energy, size_y=None, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy, d.color, d.shape = energy, color, 'RECTANGLE'
    d.size, d.size_y = size, size_y or size
    o = bpy.data.objects.new(name, d)
    scene.collection.objects.link(o)
    o.location = loc
    o.constraints.new('TRACK_TO').target = aim
    return o


area('key', (-1.4, -1.8, 2.2), 2.4, 85, color=(1.0, 0.97, 0.93))
area('fill', (1.8, -1.6, 0.8), 3.0, 30, color=(0.9, 0.92, 1.0))
area('rimL', (-1.1, 0.9, 1.3), 0.6, 45, size_y=2.4)
area('rimR', (1.1, 0.9, 1.3), 0.6, 45, size_y=2.4)
area('top', (0, -0.2, 2.6), 1.6, 25)
world = bpy.data.worlds.new('w')
world.use_nodes = True
bgc = lin(backdrop)
world.node_tree.nodes['Background'].inputs['Color'].default_value = (bgc[0] * 0.5, bgc[1] * 0.5, bgc[2] * 0.5, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
scene.world = world

cam_d = bpy.data.cameras.new('cam')
cam_d.type = 'ORTHO'
cam_d.ortho_scale = ortho
cam = bpy.data.objects.new('cam', cam_d)
scene.collection.objects.link(cam)
cam.rotation_euler = (math.radians(90), 0, 0)
cam.location = (0, -4, cam_center)
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.transparent_max_bounces = 16
scene.cycles.transmission_bounces = 12
scene.render.resolution_x = int(720 * SCALE)
scene.render.resolution_y = int(1000 * SCALE)
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
