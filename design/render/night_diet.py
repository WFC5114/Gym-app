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
#   python3 night_diet.py <out dir> [samples] [only-prefix]  (night_kit.py has the shared parts)
import bpy, math, os
from mathutils import Vector
from night_kit import *

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

# --- The jar, as in the mockup, fitted: bigger and centred on the face (Wei,
# 15 Oct 2026: "all objects should be bigger and in the center"), standing a
# little lower so it clears the macro gauges. Grown again over a slimmer
# quick-add row (Wei, 15 Oct: the first pass grew it only about 9%).
JAR_Z = Z(-0.49) - 62 * U
jar = empty('jar', (0.02, -0.17, JAR_Z), rot=(math.radians(6), 0, math.radians(-8)))
JS = 1.16
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


# The glass as the app's physics sees it: the front wall, outer and inner.
LAYOUT['jar'] = dict(
    outer=rect_of([project((sx * JW, -JD, z)) for sx in (-1, 1) for z in (base_top, base_top + 2 * JH)]),
    interior=rect_of([project((sx * (JW - wall_t), -JD, z)) for sx in (-1, 1) for z in (floor_z, base_top + 2 * JH)]),
    targetY=round(project((0, -JD, target_z))[1], 2))
# TARGET and its number sit on the glass just above the etched line, at its left end.
ix, ty = LAYOUT['jar']['interior'][0], LAYOUT['jar']['targetY']
LAYOUT['labels']['target.name'] = dict(x=round(ix + 10, 2), y=round(ty - 10, 2), size=round(0.02 * PT * EM[LABEL_FONT.name], 2),
                                       align='left', weight='bold')
LAYOUT['labels']['target.value'] = dict(x=round(ix + 52, 2), y=round(ty - 10, 2), size=round(0.026 * PT * EM[BODY_FONT.name], 2),
                                        align='left', weight='medium')

# --- The rail and its quick-add blocks: a slim row low on the face, so the
# jar can stand big above it.
rail_z = Z(-0.72) - 31 * U
QH = 0.7
rail = link(block('rail', 0.45, 0.06, 0.011, bevel=0.009), None, PLINTH, group='backdrop')
rail.location = (0, -0.03, rail_z)
LAYOUT['railY'] = round(face_pt(0, rail_z + 0.011)[1], 2)
LAYOUT['quick'] = {}
for i, (kcal, w, h) in enumerate([(50, 0.08, 0.05 * QH), (100, 0.085, 0.056 * QH), (250, 0.09, 0.064 * QH), (500, 0.095, 0.074 * QH)]):
    x = -0.34 + i * 0.226
    q = link(block('quick', w, 0.045, h, bevel=0.03), None, FOOD['quick'], group='quick-%d' % kcal)
    q.location = (x, -0.04, rail_z + 0.011 + h)
    text('quickNum', str(kcal), 0.034, HERO_FONT, PLINTH, (0, -0.0455, -0.002), q, align='CENTER', depth=0.003)
    text('quickUnit', 'KCAL', 0.012, LABEL_FONT, PLINTH, (0, -0.0455, -h + 0.012), q, align='CENTER', depth=0.0015, spacing=1.2)
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


# The studio and the shooter are in night_kit.py; the objects above are all built.

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

write_meta('diet')
