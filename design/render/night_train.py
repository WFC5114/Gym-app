# TRAIN straight from Blender (Wei, 14 Oct 2026: "none of the objects should
# be created from code, all straight from blender"). A rest timer (Wei, 15 Oct:
# "I don't need to add sets or record sets, only rest times"): the Night tray
# with the coach's plate beside the hero, the keys and the clay desk hourglass
# (design/mockups/clay/objects.py hourglass, in the Night palette) big and
# centred, laid out like DIET on the 420 x 852 pt face and rendered in pieces:
#   night-train-backdrop        the tray and the coach's plate, with the still
#                               keys' shadows baked in
#   night-train-key-<id>[-down] the keys, up and pressed
#   night-hourglass-<p>-empty   the whole hourglass with no sand; pose a upright,
#                               pose b turned over (the glass flips about the line
#                               of sight, so b is the same object lit as it
#                               really is upside down)
#   night-hourglass-<p>-full    the same with both bulbs packed full of sand
#   night-hourglass-shadow      its soft shadow on the tray, drawn under it
# The sand is simulated in the app (SandGlass.swift): falling grains, piling,
# the stream through the neck, sloshing in the flip. Where a grain is, the app
# shows the full picture, elsewhere the empty one, so every grain is Blender's
# sand seen through Blender's glass. night-train.json gives the glass's centre,
# axis and inner profile for that, plus every picture's rect and the layout:
# text anchors, the coach plate, the glass's base and largest height (the app
# scales it down for short rests). The hero reuses DIET's glyphs (night_diet.py).
#   python3 night_train.py <out dir> [samples] [only-prefix]
import bpy, bmesh, math, os
from mathutils import Vector, Quaternion
from night_kit import *


def at(px, py):
    """Face points to Blender (x, z) on the tray."""
    return ((px - FACE_W / 2) * U, ZC + (FACE_H / 2 - py) * U)


# --- Text the app sets, recorded as anchors (the same places as DIET's).
label_anchor('title', -0.43, Z(0.93), 0.042)
label_anchor('caption', -0.43, Z(0.885), 0.024, weight='medium')
label_anchor('nav', 0.43, Z(0.925), 0.026, align='right')
label_anchor('line1', -0.43, Z(0.545), 0.03)
label_anchor('line2', -0.43, Z(0.505), 0.028, weight='medium')
HERO_SIZE = 0.255
LAYOUT['hero'] = dict(x=round(face_pt(-0.445, 0)[0], 2), centerY=round(face_pt(0, Z(0.70))[1], 2),
                      fontSize=round(HERO_SIZE * PT * EM[HERO_FONT.name], 2))

# --- The coach's plate, right of the hero: a raised graphite clay plate held by
# four brass screws, COACH pressed into it. The app prints the advice on it.
COACH = [244.0, 88.0, 150.0, 92.0]
cx, cz = at(COACH[0] + COACH[2] / 2, COACH[1] + COACH[3] / 2)
PLATE = clay('plate', 0x2B2930, rough=0.55, coat=0.1, bump=0.06, grain=220)
MUTED = clay('muted', S['muted'], rough=0.5)
plate = link(block('coachPlate', COACH[2] / 2 * U, 0.012, COACH[3] / 2 * U, bevel=0.012, sub=3), None, PLATE, group='backdrop')
plate.location = (cx, FRONT - 0.012, cz)
for sx in (-1, 1):
    for sz in (-1, 1):
        screw('plateScrew', None, (cx + sx * (COACH[2] / 2 - 8) * U, FRONT - 0.025, cz + sz * (COACH[3] / 2 - 8) * U), 0.0055)
for o in scene.objects:
    if o.name.startswith('plateScrew') and o.parent is None:
        GROUPS['backdrop'].append(o)
lx, lz = at(COACH[0] + 14, COACH[1] + 20)
text('coachLabel', 'COACH', 0.02, LABEL_FONT, MUTED, (lx, FRONT - 0.025, lz), None, depth=0.002, spacing=1.2, group='backdrop')
LAYOUT['coach'] = COACH
label_anchor('coach.title', *at(COACH[0] + 14, COACH[1] + 40), 0.032)
label_anchor('coach.reasons', *at(COACH[0] + 14, COACH[1] + 58), 0.02, weight='medium')

# --- Keys. Row one changes with the state: +0:30 REST while resting (the
# time added so far beside it), −0:15 / +0:15 round the planned rest
# otherwise. START REST becomes END REST while resting (same key, so one baked
# shadow). The coach's USE key is blank: the app prints the advised time on it.
LAYOUT['keys'] = {}
ROW1_Y, ROW1_H = 704.0, 44.0
PRIMARY = [31.63, 768.73, 363.11, 49.26]
KEYS = [  # id, label, face rect, clay key?
    ('add', '+0:30 REST', [31.63, ROW1_Y, 176.0, ROW1_H], False),
    ('shorter', '−0:15', [31.63, ROW1_Y, 94.0, ROW1_H], False),
    ('longer', '+0:15', [300.74, ROW1_Y, 94.0, ROW1_H], False),
    ('start', 'START REST', PRIMARY, True),
    ('stop', 'END REST', PRIMARY, True),
    ('use', '', [COACH[0], COACH[1] + COACH[3] + 8, COACH[2], 40.0], False),
]
for key, label, r, primary in KEYS:
    x, z = at(r[0] + r[2] / 2, r[1] + r[3] / 2)
    w, h = r[2] / 2 * U, r[3] / 2 * U
    for down in (False, True):
        g = 'key-%s%s' % (key, '-down' if down else '')
        y = -0.02 + (0.012 if down else 0)
        k = link(block('key', w, 0.035, h, bevel=min(0.056, h * 0.97), sub=3), None, BUTTON if primary else GLASS, group=g)
        k.location = (x, y, z)
        if label and primary:
            text('keyLabel', label, 0.032, LABEL_FONT, BUTTON_TEXT, (0, -0.0355, 0), k, align='CENTER', depth=0.003, spacing=1.2)
        elif label:
            text('keyLabel', label, 0.03, LABEL_FONT, INK, (x, y - 0.038, z), None, align='CENTER', depth=0.003, spacing=1.2, group=g)
    LAYOUT['keys'][key] = r
LAYOUT['labels']['rest.name'] = dict(x=213.19, y=ROW1_Y + 14, size=round(0.02 * PT * EM[LABEL_FONT.name], 2), align='center', weight='bold')
LAYOUT['labels']['rest.value'] = dict(x=213.19, y=ROW1_Y + 31, size=round(0.032 * PT * EM[BODY_FONT.name], 2), align='center', weight='medium')
# While resting, the time added so far, right of +0:30 REST.
LAYOUT['labels']['added.name'] = dict(x=306.0, y=ROW1_Y + 14, size=round(0.02 * PT * EM[LABEL_FONT.name], 2), align='center', weight='bold')
LAYOUT['labels']['added.value'] = dict(x=306.0, y=ROW1_Y + 31, size=round(0.032 * PT * EM[BODY_FONT.name], 2), align='center', weight='medium')

# --- The hourglass (design/mockups/clay/objects.py), Night palette: graphite
# plates with ivory panels, terracotta turned posts and cups, brass sleeves,
# feet, nuts, ticks and knurled knobs, thick round glass, pale clay sand.
DIAL = clay('dial', 0x3A3540, rough=0.45)
SAND = clay('sand', 0xF3E9D8, rough=0.8, coat=0.0, bump=0.25)
GLASS_X, BASE_Y, H_MAX = 210.0, 680.0, 410.0
pivot = empty('pivot', (0, 0, 0), group='glass')
pivot.rotation_mode = 'QUATERNION'
QA = (Quaternion((0, 0, 1), math.radians(-28)) @ Quaternion((1, 0, 0), math.radians(10)))
QB = Quaternion((0, 1, 0), math.pi) @ QA
pivot.rotation_quaternion = QA


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


def spindle(name, length, r, grooves):
    """A turned post standing from z 0 to length, with lathe-cut grooves."""
    prof = []
    for i in range(97):
        t = i / 96
        end = min(t, 1 - t) / 0.04
        cap = math.sqrt(max(0.0, 1 - (1 - min(end, 1)) ** 2))
        groove = sum(0.12 * r * math.exp(-((t - g) * length / 0.004) ** 2) for g in grooves)
        prof.append((length * t, max((r - groove) * cap, 1e-4)))
    return lathe(name, prof, 48)


def knurled_knob(parent, loc, rot, r=0.03, length=0.03, ribs=24):
    """A grip knob on its side, ribbed round its barrel: the rest setter."""
    k = link(lathe('knob', [(0, 1e-4), (0, r * 0.7), (0.004, r), (length - 0.004, r), (length, r * 0.8), (length, 1e-4)], 48), parent, HARD)
    k.location, k.rotation_euler = loc, rot
    for i in range(ribs):
        a = 2 * math.pi * i / ribs
        rib = link(block('rib', 0.0025, 0.0025, length * 0.36, bevel=0.0015, sub=1), k, HARD)
        rib.location = (r * math.cos(a), r * math.sin(a), length / 2)
    cap = link(ellipsoid('knobCap', r * 0.55, r * 0.55, 0.006), k, ACCENT)
    cap.location = (0, 0, length)


side, thick = 0.29, 0.035
zb, zt = -0.43, 0.43
for s, z in ((-1, zb), (1, zt)):
    slab = link(block('slab', side, side, thick, bevel=0.03), pivot, DIAL)
    slab.location = (0, 0, z + s * thick)
    panel = link(block('panel', side - 0.035, side - 0.035, 0.012, bevel=0.012), pivot, OBJ)
    panel.location = (0, 0, z + s * (2 * thick + 0.008))
    cup = link(lathe('cup', [(0, 0.075), (0, 0.11), (0.01 * -s, 0.114), (0.022 * -s, 0.095), (0.03 * -s, 0.075)], 64, loop=True), pivot, ACCENT)
    cup.location = (0, 0, z)
    # A knurled knob on each base, so the glass reads the same either way up.
    knurled_knob(pivot, (side + 0.004, 0.08, z + s * thick), (0, math.pi / 2, 0))
for px in (-0.21, 0.21):
    for py in (-0.21, 0.21):
        f = link(ellipsoid('foot', 0.04, 0.04, 0.02), pivot, HARD)
        f.location = (px, py, zb - 2 * thick - 0.02)
        nut = link(ellipsoid('nut', 0.03, 0.03, 0.026), pivot, HARD)
        nut.location = (px, py, zt + 2 * thick + 0.02)
        post = link(spindle('post', zt - zb, 0.016, grooves=(0.08, 0.5, 0.92)), pivot, ACCENT)
        post.location = (px, py, zb)
        for s, z in ((1, zb), (-1, zt)):
            sleeve = link(lathe('sleeve', [(0, 1e-4), (0, 0.026), (0.006, 0.028), (0.05, 0.024), (0.06, 0.02), (0.06, 1e-4)], 48), pivot, HARD)
            sleeve.location = (px, py, z)
            sleeve.rotation_euler = (0 if s > 0 else math.pi, 0, 0)

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
GW = 0.022


def offset_in(prof):
    res = []
    for i, (z, r) in enumerate(prof):
        z0, r0 = prof[max(i - 1, 0)]
        z1, r1 = prof[min(i + 1, len(prof) - 1)]
        tz, tr = z1 - z0, r1 - r0
        L = math.hypot(tz, tr) or 1
        nz, nr = -tr / L, tz / L
        res.append((z - nz * GW, max(r - nr * GW, 0.007)))
    return res


prof = [(-z, r) for z, r in reversed(outer)] + outer[1:]
inner = offset_in(prof)
# Clear glass that lets light through to the sand: a tinted shell darkens
# what is behind it at every wall it crosses, and a shadowing shell leaves the
# sand lit only by refracted light, so pale sand read as grey in either bulb.
HG_GLASS = resin('hourglassGlass', 0xFAFBFD, 0.05)
shell = link(lathe('glass', prof + list(reversed(inner)), 192, loop=True), pivot, HG_GLASS)
shell.visible_shadow = False
link(lathe('neckRing', [(-0.012, 0.034), (-0.012, 0.04), (0.012, 0.04), (0.012, 0.034)], 64, loop=True), pivot, HARD)
for i in range(7):
    t = link(block('tick', 0.003, 0.004, 0.01 if i % 2 == 0 else 0.006, bevel=0.002, sub=1), pivot, HARD)
    t.location = (-0.15 + i * 0.05, -side - 0.003, zb - thick)
text('restLabel', 'REST', 0.028, LABEL_FONT, HARD, (0, -side - 0.001, zb - thick - 0.02), pivot, align='CENTER',
     depth=0.003, rot=(math.pi / 2, 0, 0))

# Place it: the largest glass (6 min rest) is H_MAX tall with its base on BASE_Y, centred.
INNER_TOP = sorted((z, r) for z, r in inner if z >= 0)


def r_at(z):
    z = abs(z)
    for (z0, r0), (z1, r1) in zip(INNER_TOP, INNER_TOP[1:]):
        if z0 <= z <= z1:
            return (r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-6)) - 0.002
    return 0.008


def glass_objects():
    return [o for o in tree(pivot) if o.type in ('MESH', 'FONT')]


def glass_rect():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in glass_objects():
        e = o.evaluated_get(dg)
        pts += [face_pt(*(lambda w: (w.x, w.z))(e.matrix_world @ Vector(c))) for c in e.bound_box]
    return rect_of(pts)


r0 = glass_rect()
pivot.scale = (H_MAX / r0[3],) * 3
r1 = glass_rect()
gx, gz = at(GLASS_X, BASE_Y - r1[3] / 2)
cx0, cy0 = r1[0] + r1[2] / 2, r1[1] + r1[3] / 2
# Its back stands just off the tray.
pivot.location = (gx - (cx0 - FACE_W / 2) * U, FRONT - 0.42 * pivot.scale[0], gz + (cy0 - FACE_H / 2) * U)
r2 = glass_rect()
centre = face_pt(pivot.location.x, pivot.location.z)

def projected(local):
    """A point in glass units, in face points (pose a, largest glass)."""
    w = pivot.matrix_world @ Vector(local)
    return face_pt(w.x, w.z)


bpy.context.view_layer.update()
c0, c1 = projected((0, 0, 0)), projected((0, 0, 1))
LAYOUT['glass'] = dict(rect=r2, centre=[round(centre[0], 2), round(centre[1], 2)], baseY=round(r2[1] + r2[3], 2),
                       maxHeight=round(r2[3], 2), minShare=0.6,
                       # For the sand: one glass unit of radius in points, the glass's
                       # axis (+z, toward the A bulb) in points per unit, the inner wall
                       # as (z, r) from the neck out, and the sand's line when one bulb is full.
                       unitPoints=round(pivot.scale[0] * PT, 3),
                       axis=[round(c1[0] - c0[0], 3), round(c1[1] - c0[1], 3)],
                       inner=[[round(z, 4), round(max(r - 0.002, 0.004), 4)] for z, r in INNER_TOP[::3] + INNER_TOP[-1:]],
                       sandLine=0.34)
print('glass rect', r2, 'centre', centre, 'axis', LAYOUT['glass']['axis'])

# --- Sand: pale clay packed into both bulbs, for the "full" pictures.
def full_sand():
    zs = [x[0] for x in INNER_TOP]
    prof = [(-zs[-1], 1e-4)] + [(-z, r_at(z) - 0.001) for z in reversed(zs)] + [(z, r_at(z) - 0.001) for z in zs[1:]] + [(zs[-1], 1e-4)]
    return link(lathe('sandFull', prof, 128), pivot, SAND, group='sandPiece')


# 1. Backdrop: tray and coach plate, with the shadows of START REST (always there) baked in.
shoot('night-train-backdrop', [0, 0, FACE_W, FACE_H], ['backdrop'], catch=False, ghosts=['key-start'])

# 2. Keys. The primary key's shadow is in the backdrop; the others come and go
# with the state, so they carry their own.
for key, label, r, primary in KEYS:
    for down in ('', '-down'):
        name = 'night-train-key-%s%s' % (key, down)
        if ONLY and not name.startswith(ONLY):
            continue
        if primary:
            shoot(name, around(r, 8, 8, 26, 30), ['key-%s%s' % (key, down)], catch=False)
        else:
            shoot(name, around(r, 14, 14, 34, 36), ['key-%s%s' % (key, down)], fade=12)

# 3. The hourglass's shadow, from the glass seen by nothing but the tray.
if not ONLY or 'night-hourglass-shadow'.startswith(ONLY):
    shoot('night-hourglass-shadow', around(r2, 30, 30, 90, 90), [], ghosts=['glass'], fade=40)

# 4. The hourglass empty and packed full, upright (a) and turned over (b).
glass_frame = around(r2, 16, 16, 16, 16)
for pose, q in (('a', QA), ('b', QB)):
    pivot.rotation_quaternion = q
    for fill in ('empty', 'full'):
        name = 'night-hourglass-%s-%s' % (pose, fill)
        if ONLY and not name.startswith(ONLY):
            continue
        if fill == 'full':
            full_sand()
        shoot(name, glass_frame, ['glass', 'sandPiece'], catch=False)
        for o in list(GROUPS.get('sandPiece', [])):
            bpy.data.objects.remove(o, do_unlink=True)
        GROUPS['sandPiece'] = []

write_meta('train')
