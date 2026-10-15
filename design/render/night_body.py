# BODY straight from Blender (Wei, 14 Oct 2026: "none of the objects should be
# created from code, all straight from blender"), except the mannequin and its
# turntable, which move too much to pre-render and stay live 3D. The Night tray
# with the history ruler's plate, laid out like DIET and TRAIN on the 420 x 852
# pt face, rendered in pieces:
#   night-body-backdrop        the tray and the ruler's plate, with the soft
#                              shadows of the live turntable and mannequin baked
#                              in from stand-in shapes (they cast, unseen). The
#                              app shows it behind the live 3D figure.
#   night-body-tick-<kind>     a day, week-start or scan-day tick on the ruler
#   night-body-fine            a vernier fine tick riding the cursor
#   night-body-cursor          the terracotta slider with its index needle
# night-body.json gives every picture's rect, the text anchors and the ruler's
# track, so the app lays the ticks out from the data.
#
#   python3 night_body.py <out dir> [samples] [only prefix]

import bpy, bmesh, math, os
from night_kit import *


def at(px, py):
    """Face points to Blender (x, z) on the tray."""
    return ((px - FACE_W / 2) * U, ZC + (FACE_H / 2 - py) * U)


# --- Text the app sets (the same places as DIET's and TRAIN's).
label_anchor('title', -0.43, Z(0.93), 0.042)
label_anchor('caption', -0.43, Z(0.885), 0.024, weight='medium')
label_anchor('nav', 0.43, Z(0.925), 0.026, align='right')
label_anchor('line1', -0.43, Z(0.545), 0.03)
label_anchor('line2', -0.43, Z(0.505), 0.028, weight='medium')
label_anchor('unit', 0, 0, 0.034)
HERO_SIZE = 0.255
LAYOUT['hero'] = dict(x=round(face_pt(-0.445, 0)[0], 2), centerY=round(face_pt(0, Z(0.70))[1], 2),
                      fontSize=round(HERO_SIZE * PT * EM[HERO_FONT.name], 2))
label_anchor('schematic', *at(210, 268), 0.028, align='center')
label_anchor('sources', *at(210, 285), 0.025, align='center', weight='medium')
for i, key in enumerate(('fat', 'lean', 'source')):
    label_anchor('reading.%s.name' % key, *at(118 + i * 92, 685), 0.027, align='center')
    label_anchor('reading.%s.value' % key, *at(118 + i * 92, 702), 0.036, align='center', weight='medium')

# --- The ruler's plate: a raised graphite clay plate held by four brass screws.
RULER = [26.0, 718.0, 368.0, 106.0]
TRACK = [46.0, 374.0]         # first and last day's x
BASE_Y = RULER[1] + RULER[3] - 16
TICK = dict(day=(2.0, 14.0), week=(2.2, 24.0), scan=(2.6, 40.0))
FINE = (1.4, 10.0)
CURSOR_TOP = BASE_Y - 46
PLATE = clay('plate', 0x2B2930, rough=0.55, coat=0.1, bump=0.06, grain=220)
TICK_MAT = {'day': clay('tickDay', 0x8E8892, rough=0.5), 'week': clay('tickWeek', S['obj'], rough=0.45),
            'scan': HARD}
rx, rz = at(RULER[0] + RULER[2] / 2, RULER[1] + RULER[3] / 2)
plate = link(block('rulerPlate', RULER[2] / 2 * U, 0.012, RULER[3] / 2 * U, bevel=0.016, sub=3), None, PLATE, group='backdrop')
plate.location = (rx, FRONT - 0.012, rz)
for sx in (-1, 1):
    for sz in (-1, 1):
        screw('rulerScrew', None, (rx + sx * (RULER[2] / 2 - 8) * U, FRONT - 0.025, rz + sz * (RULER[3] / 2 - 8) * U), 0.0055)
for o in scene.objects:
    if o.name.startswith('rulerScrew') and o.parent is None:
        GROUPS['backdrop'].append(o)
# A fine groove the ticks stand on.
gx, gz = at(210, BASE_Y + 1)
groove = link(block('groove', (TRACK[1] - TRACK[0] + 12) / 2 * U, 0.002, 0.8 * U, bevel=0.0006, sub=1), None, RUST, group='backdrop')
groove.location = (gx, FRONT - 0.0245, gz)
LAYOUT['ruler'] = dict(rect=RULER, track=TRACK, baseY=BASE_Y, cursorTop=CURSOR_TOP)

# --- Stand-ins for the live turntable and mannequin (MannequinRig.swift,
# FigureGeometry): they only cast the shadows baked into the backdrop.
FACE_H_REF = 852.0
MECH_Y, MECH_H = FACE_H_REF * 0.30, FACE_H_REF * 0.50
UNIT = MECH_H * 0.80 * U          # one figure unit, in Blender units
FEET = (210.0, MECH_Y + MECH_H - 40)
PROUD = 90 * U
fx, fz = at(*FEET)
stand = empty('stand', (fx, FRONT - PROUD, fz), group='figure')
stand.rotation_euler = (0.16, 0, 0)    # the stand leans its top toward the viewer
stand.scale = (UNIT, UNIT, UNIT)


def part(o, loc, rot=(0, 0, 0)):
    link(o, stand)
    o.location, o.rotation_euler = loc, rot
    return o


def cylinder(name, r, h, segments=96):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


# Dial and plinth (figure units, z up).
part(cylinder('dial', 0.264, 0.04), (0, 0, -0.02))
part(cylinder('plinth', 0.075, 0.075, 48), (0, 0, -0.0775))
# Figure: legs, hips, torso, shoulders, head and arms as rounded capsules.
VERT = (0, math.pi / 2, 0)
for sx in (-1, 1):
    part(capsule('leg', 0.5, 0.045), (sx * 0.055, 0, 0.25), VERT)
    part(capsule('arm', 0.38, 0.03), (sx * 0.128, 0, 0.56), VERT)
part(capsule('hips', 0.2, 0.07), (0, 0, 0.5))
part(capsule('torso', 0.3, 0.1), (0, 0, 0.66), VERT)
part(capsule('shoulders', 0.24, 0.05), (0, 0, 0.76))
part(capsule('head', 0.16, 0.065), (0, 0, 0.88), VERT)
for o in stand.children:
    o.data.materials.append(TRAY)

# 1. Backdrop: tray and ruler plate, with the figure's and turntable's shadows baked in.
if os.environ.get('SHOW_STANDINS'):   # a check picture: the stand-ins seen, to line them up with the app
    shoot('night-body-backdrop', [0, 0, FACE_W, FACE_H], ['backdrop', 'figure'], catch=False)
else:
    shoot('night-body-backdrop', [0, 0, FACE_W, FACE_H], ['backdrop'], catch=False, ghosts=['figure'])


def relative(name, r):
    """Records the object's rect inside its picture, so the app can stand it on the track."""
    if name in SPRITES:
        pic = SPRITES[name]['rect']
        SPRITES[name]['object'] = [round(r[0] - pic[0], 2), round(r[1] - pic[1], 2), r[2], r[3]]


# 2. Ruler pieces, each centred on its rect so the app can place it by its foot.
def tick(name, w, h, mat, rounded=True):
    tx, tz = at(210, 426 - h / 2)
    t = link(block(name, w / 2 * U, 0.004, h / 2 * U, bevel=w / 2 * U * 0.9 if rounded else 0.0005, sub=2), None, mat,
             group=name)
    t.location = (tx, FRONT - 0.016, tz)
    r = [210 - w / 2, 426 - h, w, h]
    shoot(name, around(r, 4, 4, 8, 8), [name], fade=3)
    relative(name, r)


for kind, (w, h) in TICK.items():
    tick('night-body-tick-' + kind, w, h, TICK_MAT[kind])
tick('night-body-fine', FINE[0], FINE[1], INK)

# The cursor: a terracotta slider riding the track, its brass needle down to the base.
NEEDLE_H = BASE_Y - CURSOR_TOP
cx, cz = at(210, 426 - NEEDLE_H)
needle = link(block('needle', 0.6 * U, 0.003, NEEDLE_H / 2 * U, bevel=0.0005, sub=1), None, HARD, group='cursor')
needle.location = (cx, FRONT - 0.018, at(210, 426 - NEEDLE_H / 2)[1])
slider = link(block('slider', 6 * U, 0.008, 8 * U, bevel=0.012, sub=3), None, ACCENT, group='cursor')
slider.location = (cx, FRONT - 0.026, cz + 2 * U)
for k in (-1, 0, 1):
    g = link(block('grip', 3.6 * U, 0.0015, 0.35 * U, bevel=0.0004, sub=1), slider, RUST)
    g.location = (0, -0.0085, k * 2.6 * U)
cr = [210 - 6, 426 - NEEDLE_H - 10, 12, NEEDLE_H + 10]
shoot('night-body-cursor', around(cr, 8, 8, 16, 16), ['cursor'], fade=6)
relative('night-body-cursor', cr)

write_meta('body')
