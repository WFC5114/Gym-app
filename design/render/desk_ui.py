# The desk prototype's controls straight from Blender (Wei, 17 Oct 2026: "over
# all not very claymorphic"; 14 Oct: the buttons come from Blender too).
# Wei, later on 17 Oct: "I want some color but mature and some glassish jelly
# like buttons and there should be a bar for macros that fills up". So the
# controls are thick glass: clear glass that takes the desk's colour, or glass
# with a pressed clay core (honey for the main action, ivory for the open tab),
# a ruby jelly coach puck, and the macro gauges are glass tubes the page fills
# with clay. Each is rendered once on a transparent ground with its soft shadow,
# up and pressed, and sliced: the page keeps the round ends and stretches the
# middle, and prints the label.
#   desk-ui-primary[-down]  honey clay in glass (the main action)
#   desk-ui-soft[-down]     ivory clay in glass, 56 pt tall (other actions, the open tab)
#   desk-ui-chip[-down]     clear glass, 44 pt tall (choices, quick adds)
#   desk-ui-chip-on         honey clay in glass, 44 pt tall (the chosen one)
#   desk-ui-coach[-down]    the ruby jelly puck that opens the coach
#   desk-ui-well            the glass rim the tabs sit in
#   desk-ui-tube            a macro gauge's glass tube, 18 pt tall
#   desk-ui-fill-p|c|f      its clay fill (protein, carbs, fat), drawn under the tube
# desk-ui.json gives each picture's rect, the object's rect inside it and the
# slice insets (top, left, bottom, right), in points; pictures are 3 px a point.
#   python3 desk_ui.py <out dir> [samples] [only prefix]

import bpy, math
from night_kit import *


def at(px, py):
    """Face points to Blender (x, z) on the tray."""
    return ((px - FACE_W / 2) * U, ZC + (FACE_H / 2 - py) * U)


def glass(name, tint=0xDCE6E8, density=0.5):
    """Thick clear glass, its depth faintly tinted. Seen on the transparent
    ground, it takes the colour of whatever desk the page puts behind it."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(tint)
    b.inputs['Roughness'].default_value = 0.06
    b.inputs['Transmission Weight'].default_value = 1.0
    b.inputs['IOR'].default_value = 1.38
    b.inputs['Coat Weight'].default_value = 1.0
    b.inputs['Coat Roughness'].default_value = 0.02
    va = nt.nodes.new('ShaderNodeVolumeAbsorption')
    va.inputs['Color'].default_value = lin(tint)
    va.inputs['Density'].default_value = density
    nt.links.new(va.outputs[0], nt.nodes['Material Output'].inputs['Volume'])
    return m


def jelly(name, color, trans=0.4):
    """A gummy jelly: light scatters through it and some passes straight on."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = lin(color)
    b.inputs['Roughness'].default_value = 0.12
    b.inputs['Subsurface Weight'].default_value = 1.0
    b.inputs['Subsurface Radius'].default_value = (1.0, 0.6, 0.3)
    b.inputs['Subsurface Scale'].default_value = 0.05
    b.inputs['Transmission Weight'].default_value = trans
    b.inputs['IOR'].default_value = 1.4
    b.inputs['Coat Weight'].default_value = 1.0
    b.inputs['Coat Roughness'].default_value = 0.02
    return m


# The rays that pass through the glass see the transparent ground, not the
# shadow catcher behind it.
catcher.visible_transmission = False
catcher.visible_glossy = False
scene.cycles.film_transparent_glass = True

CLEAR = glass('clearGlass')
HONEY_GLASS = glass('honeyGlass', 0xF2C27A, 2.0)
HONEY = clay('honey', 0xE39A2E, rough=0.35, coat=0.2)
IVORY = clay('ivoryCore', 0xE9DFD0, rough=0.4, coat=0.2)
RUBY = jelly('ruby', 0xC24A32)
MACRO = {'p': 0xC65D3E, 'c': 0xE3A43A, 'f': 0x9DBF8E}    # the page's food clays: protein, carbs, fat
SLICES = {}
CX, CY = 210.0, 426.0


def stadium(name, w, h, depth, edge, holes=()):
    """A stadium w x h (points) `depth` deep (Blender units) with its rim
    rounded by `edge`; `holes` are inner stadiums cut through."""
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


def pill(name, w, h, shell, core=None, press=0.008, states=(False, True)):
    """A glass pill, with a clay core pressed into its back when `core` is given."""
    r = [CX - w / 2, CY - h / 2, w, h]
    depth = h * U * 0.6
    inset = 7 if h > 50 else 6
    for down in states:
        g = name + ('-down' if down else '')
        y = FRONT - depth / 2 - 0.001 + (press if down else 0)
        place(stadium('pill', w, h, depth, h / 2 * U * 0.48), shell, g, y)
        if core:
            ch = h - 2 * inset
            place(stadium('core', w - 2 * inset, ch, depth * 0.45, ch / 2 * U * 0.5), core, g, y + depth * 0.12)
        shoot(g, around(r, 12, 10, 28, 30), [g], fade=12)
        SLICES[g] = (r, h / 2 + 2)


pill('desk-ui-primary', 220, 56, HONEY_GLASS, HONEY)
pill('desk-ui-soft', 220, 56, CLEAR, IVORY)
pill('desk-ui-chip', 120, 44, CLEAR, press=0.006)
pill('desk-ui-chip-on', 120, 44, HONEY_GLASS, HONEY, states=(False,))

# The coach puck: a round lozenge of ruby jelly.
for down in (False, True):
    g = 'desk-ui-coach' + ('-down' if down else '')
    d = 52.0
    r = [CX - d / 2, CY - d / 2, d, d]
    depth = 0.055
    y = FRONT - depth / 2 - 0.001 + (0.008 if down else 0)
    place(stadium('puck', d, d, depth, d / 2 * U * 0.5), RUBY, g, y)
    shoot(g, around(r, 10, 8, 26, 28), [g], fade=10)

# The tabs' trough: a clear glass rim; the desk is its floor.
WELL = [30.0, 392.0, 360.0, 68.0]
RIM = 6.0
wy = FRONT - 0.001
place(stadium('wellRim', WELL[2], WELL[3], 0.03, 0.009, holes=((WELL[2] - 2 * RIM, WELL[3] - 2 * RIM),)), CLEAR, 'desk-ui-well', wy - 0.015)
shoot('desk-ui-well', around(WELL, 10, 8, 24, 26), ['desk-ui-well'], fade=12)
SLICES['desk-ui-well'] = (WELL, WELL[3] / 2 + 4)

# A macro gauge: a round glass tube, and the clay that fills it. The fills are
# rendered alone, without a shadow (they lie inside the tube), and the page
# stretches one to the share eaten under the tube.
TW, TH = 120.0, 18.0
r = [CX - TW / 2, CY - TH / 2, TW, TH]
tube_depth = TH * U * 0.95
place(stadium('tube', TW, TH, tube_depth, TH / 2 * U * 0.9), CLEAR, 'desk-ui-tube', FRONT - tube_depth / 2 - 0.001)
shoot('desk-ui-tube', around(r, 8, 6, 16, 18), ['desk-ui-tube'], fade=8)
SLICES['desk-ui-tube'] = (r, TH / 2 + 2)
FW, FH = TW - 8, TH - 8
for k, colour in MACRO.items():
    g = 'desk-ui-fill-' + k
    fr = [CX - FW / 2, CY - FH / 2, FW, FH]
    fd = FH * U * 0.9
    place(stadium('fill', FW, FH, fd, FH / 2 * U * 0.9), clay('fill' + k, colour, rough=0.36, coat=0.45), g, FRONT - tube_depth / 2 - fd / 2)
    shoot(g, around(fr, 2, 2, 2, 2), [g], catch=False)
    SLICES[g] = (fr, FH / 2 + 1)

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
