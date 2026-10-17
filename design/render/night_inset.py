# The in-face inset (food search, serving, today's log, set) straight from
# Blender (Wei, 14 Oct 2026: "none of the objects should be created from code,
# all straight from blender"). Its contents change size with the text, the
# keyboard and the phone, so its objects are rendered once and sliced: the app
# keeps each picture's corners and stretches or tiles its middle.
#   night-inset-panel          the recessed graphite well the inset sits in
#   night-inset-key-<h>[-down] blank glass keys <h> points tall, up and pressed
#   night-inset-primary[-down] the ivory clay key (FORM BLOCK)
#   night-inset-field          the dark slot under a text field
# night-inset.json gives each picture's rect, the object's rect inside it and
# the slice insets (top, left, bottom, right) in points.
#
#   python3 night_inset.py <out dir> [samples] [only prefix]

import bpy, math
from night_kit import *


def at(px, py):
    """Face points to Blender (x, z) on the tray."""
    return ((px - FACE_W / 2) * U, ZC + (FACE_H / 2 - py) * U)


FLOOR = clay('insetFloor', 0x19171C, rough=0.7, coat=0.04, bump=0.03, grain=140)
SLOT = clay('insetSlot', 0x0F0E11, rough=0.5, coat=0.3, bump=0.02)
SLICES = {}

# --- The panel: a raised graphite rim around a sunken floor.
PANEL = [90.0, 266.0, 240.0, 320.0]
RIM, RADIUS = 9.0, 22.0
x, z = at(PANEL[0] + PANEL[2] / 2, PANEL[1] + PANEL[3] / 2)
d = 0.03
slab = link(block('panel', PANEL[2] / 2 * U, d, PANEL[3] / 2 * U, bevel=RADIUS * U, sub=3), None, TRAY, group='panel')
slab.location = (x, FRONT - 0.001 - d, z)
cut = link(block('pocket', (PANEL[2] / 2 - RIM) * U, d, (PANEL[3] / 2 - RIM) * U, bevel=(RADIUS - RIM / 2) * U, sub=3))
cut.location = (x, FRONT - 0.001 - 2 * d - d + 0.016, z)
cut.hide_render = True
boolean = slab.modifiers.new('pocket', 'BOOLEAN')
boolean.operation, boolean.object, boolean.solver = 'DIFFERENCE', cut, 'EXACT'
floor = link(block('floor', (PANEL[2] / 2 - RIM - 4) * U, 0.002, (PANEL[3] / 2 - RIM - 4) * U, bevel=(RADIUS - RIM) * U, sub=2),
             slab, FLOOR)
floor.location = (0, -d + 0.016 - 0.0025, 0)
shoot('night-inset-panel', around(PANEL, 10, 10, 24, 24), ['panel'], fade=14)
SLICES['night-inset-panel'] = (PANEL, RIM + RADIUS + 6)


# --- Keys: blank (the app prints the label), sliced across their middle.
def key(name, w, h, mat, depth=0.035, fy=0.0):
    r = [210 - w / 2, 426 - h / 2, w, h]
    kx, kz = at(210, 426)
    for down in (False, True):
        g = name + ('-down' if down else '')
        k = link(block('key', w / 2 * U, depth, h / 2 * U, bevel=min(0.056, h / 2 * U * 0.97), sub=3), None, mat, group=g)
        k.location = (kx, FRONT - 0.04 + depth * 0 + (0.012 if down else 0) + fy, kz)
        shoot(g, around(r, 12, 12, 26, 26), [g], fade=12)
        SLICES[g] = (r, h / 2)


for h in (40, 44, 56):
    key('night-inset-key-%d' % h, max(140, h + 4), h, GLASS)
key('night-inset-primary', 220, 52, BUTTON)

# The text field's slot, sunk into the panel's floor: a patch of floor (flush
# with the panel's, so its edge disappears) with a rounded pocket in it.
FIELD = [140.0, 404.0, 140.0, 44.0]
fx, fz = at(210, 426)
floor_front = FRONT - 0.001 - 2 * d + 0.016 - 0.0045
patch = link(block('slotPatch', (FIELD[2] / 2 + 8) * U, 0.01, (FIELD[3] / 2 + 8) * U, bevel=0, sub=0), None, FLOOR, smooth=False,
             group='field')
patch.location = (fx, floor_front + 0.01, fz)
hole = link(block('slotCut', FIELD[2] / 2 * U, 0.01, FIELD[3] / 2 * U, bevel=0.03, sub=3))
hole.location = (fx, floor_front + 0.006 - 0.01, fz)
hole.hide_render = True
b = patch.modifiers.new('slot', 'BOOLEAN')
b.operation, b.object, b.solver = 'DIFFERENCE', hole, 'EXACT'
bottom = link(block('slotFloor', FIELD[2] / 2 * U, 0.001, FIELD[3] / 2 * U, bevel=0.02, sub=2), None, SLOT, group='field')
bottom.location = (fx, floor_front + 0.006 - 0.0012, fz)
shoot('night-inset-field', [FIELD[0] - 8, FIELD[1] - 8, FIELD[2] + 16, FIELD[3] + 16], ['field'], catch=False)
SLICES['night-inset-field'] = (FIELD, 22)

for name, (obj, cap) in SLICES.items():
    if name not in SPRITES:
        continue
    pic = SPRITES[name]['rect']
    left, top = obj[0] - pic[0], obj[1] - pic[1]
    right, bottom = pic[0] + pic[2] - obj[0] - obj[2], pic[1] + pic[3] - obj[1] - obj[3]
    SPRITES[name]['object'] = [round(left, 2), round(top, 2), obj[2], obj[3]]
    # Never slice through the bevel: a key's ends are half its height round.
    ch = min(cap, obj[3] / 2 - 1)
    SPRITES[name]['slice'] = [round(top + ch, 2), round(left + cap, 2), round(bottom + ch, 2), round(right + cap, 2)]
write_meta('inset')
