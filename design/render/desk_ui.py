# The desk prototype's controls straight from Blender (Wei, 17 Oct 2026: "over
# all not very claymorphic"; 14 Oct: the buttons come from Blender too). Puffy
# clay pills and a coach puck in the Night clay and studio, each rendered once
# on a transparent ground with its soft shadow, up and pressed, and sliced: the
# page keeps the round ends and stretches the middle, and prints the label.
#   desk-ui-primary[-down]  the ivory clay pill (the main action)
#   desk-ui-soft[-down]     a graphite clay pill 56 pt tall (other actions, the open tab)
#   desk-ui-chip[-down]     a graphite clay pill 44 pt tall (choices, quick adds)
#   desk-ui-chip-on         the ivory clay chip (the chosen one)
#   desk-ui-coach[-down]    the terracotta clay puck that opens the coach
#   desk-ui-well            the pressed slot the tabs sit in
# desk-ui.json gives each picture's rect, the object's rect inside it and the
# slice insets (top, left, bottom, right), in points; pictures are 3 px a point.
#   python3 desk_ui.py <out dir> [samples] [only prefix]

import bpy, math
from night_kit import *


def at(px, py):
    """Face points to Blender (x, z) on the tray."""
    return ((px - FACE_W / 2) * U, ZC + (FACE_H / 2 - py) * U)


GRAPHITE = clay('graphiteKey', 0x2E2B31, rough=0.5, coat=0.18, sss=0.1, bump=0.06, grain=260)
TERRA = clay('coach', S['accent'], rough=0.42, coat=0.3)
FLOOR = clay('wellFloor', 0x19171C, rough=0.7, coat=0.04, bump=0.03, grain=140)
SLICES = {}
CX, CY = 210.0, 426.0


def stadium(name, w, h, depth, edge, holes=()):
    """A pill of clay: a stadium w x h (points) pressed `depth` deep (Blender
    units) with its rim rounded by `edge`; `holes` are inner stadiums cut through."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = max(0.0, depth / 2 - edge)
    cu.bevel_depth = edge
    cu.bevel_resolution = 8
    for i_, (ww, hh) in enumerate(((w, h),) + tuple(holes)):
        half = max(0.0, (ww - hh) / 2 * U)
        r = hh / 2 * U + (edge if i_ else -edge)    # the rounded rim grows the outline by `edge`
        sp = cu.splines.new('POLY')
        pts = []
        for i in range(97):
            a = -math.pi / 2 + math.pi * i / 96
            pts.append((half + r * math.cos(a), r * math.sin(a)))
        for i in range(97):
            a = math.pi / 2 + math.pi * i / 96
            pts.append((-half + r * math.cos(a), r * math.sin(a)))
        sp.points.add(len(pts) - 1)
        for p_, (x, y) in zip(sp.points, pts):
            p_.co = (x, y, 0, 1)
        sp.use_cyclic_u = True
    o = bpy.data.objects.new(name, cu)
    return o


def place(o, mat, group, y):
    """Stands a stadium up on the tray, facing the camera, its back at `y`."""
    link(o, None, mat, smooth=False, group=group)
    o.rotation_euler = (math.pi / 2, 0, 0)
    kx, kz = at(CX, CY)
    o.location = (kx, y, kz)
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')          # the shooter shows and hides meshes
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return o


def pill(name, w, h, mat, press=0.008, states=(False, True)):
    r = [CX - w / 2, CY - h / 2, w, h]
    depth = h * U * 0.55
    for down in states:
        g = name + ('-down' if down else '')
        o = place(stadium('pill', w, h, depth, h / 2 * U * 0.42), mat, g, FRONT - depth / 2 - 0.001 + (press if down else 0))
        shoot(g, around(r, 12, 10, 28, 30), [g], fade=12)
        SLICES[g] = (r, h / 2 + 2)


pill('desk-ui-primary', 220, 56, BUTTON)
pill('desk-ui-soft', 220, 56, GRAPHITE)
pill('desk-ui-chip', 120, 44, GRAPHITE, press=0.006)
pill('desk-ui-chip-on', 120, 44, BUTTON, states=(False,))

# The coach puck: a round lozenge of terracotta clay with a pressed ring.
for down in (False, True):
    g = 'desk-ui-coach' + ('-down' if down else '')
    d = 52.0
    r = [CX - d / 2, CY - d / 2, d, d]
    depth = 0.05
    y = FRONT - depth / 2 - 0.001 + (0.008 if down else 0)
    place(stadium('puck', d, d, depth, d / 2 * U * 0.45), TERRA, g, y)
    place(stadium('puckRing', d * 0.66, d * 0.66, 0.004, 0.0015, holes=((d * 0.58, d * 0.58),)), RUST, g, y - depth / 2 - 0.0002)
    shoot(g, around(r, 10, 8, 26, 28), [g], fade=10)

# The tabs' well: a slot pressed into a graphite strip.
WELL = [30.0, 392.0, 360.0, 68.0]
RIM = 6.0
wy = FRONT - 0.001
place(stadium('wellRim', WELL[2], WELL[3], 0.03, 0.009, holes=((WELL[2] - 2 * RIM, WELL[3] - 2 * RIM),)), TRAY, 'desk-ui-well', wy - 0.015)
place(stadium('wellFloor', WELL[2] - 2, WELL[3] - 2, 0.006, 0.002), FLOOR, 'desk-ui-well', wy - 0.003)
shoot('desk-ui-well', around(WELL, 10, 8, 24, 26), ['desk-ui-well'], fade=12)
SLICES['desk-ui-well'] = (WELL, WELL[3] / 2 + 4)

for name, (obj, cap) in SLICES.items():
    if name not in SPRITES:
        continue
    pic = SPRITES[name]['rect']
    left, top = obj[0] - pic[0], obj[1] - pic[1]
    right, bottom = pic[0] + pic[2] - obj[0] - obj[2], pic[1] + pic[3] - obj[1] - obj[3]
    SPRITES[name]['object'] = [round(left, 2), round(top, 2), obj[2], obj[3]]
    SPRITES[name]['slice'] = [round(top + obj[3] / 2 - 1, 2), round(left + cap, 2), round(bottom + obj[3] / 2 - 1, 2), round(right + cap, 2)]
for name in ('desk-ui-coach', 'desk-ui-coach-down'):
    if name in SPRITES:
        pic = SPRITES[name]['rect']
        SPRITES[name]['object'] = [round(CX - 26 - pic[0], 2), round(CY - 26 - pic[1], 2), 52.0, 52.0]
write_meta('desk-ui')
