import CoreGraphics
import Foundation

/// Where one food block rests in the jar (face-local points, block centre).
/// `angle` is in radians, positive turns clockwise on screen.
struct JarPose: Equatable {
    var center: CGPoint
    var angle: Double
    var size: CGSize
}

/// One block to place: its energy, a stable seed for its shape and, for blocks
/// dropped by hand this session, the x it was released at.
struct JarItem: Hashable {
    var kcal: Double
    var seed: UInt64
    var dropX: CGFloat?
}

/// A laid-out pile: one pose per item, the highest point of the pile, the
/// pile's surface (for falling blocks to meet) and whether it was shrunk to fit.
struct JarPile: Equatable {
    var poses: [JarPose]
    var top: CGFloat
    var surface: [CGFloat]
    var scale: CGFloat
    var scaled: Bool { scale < 0.999 }
}

/// Presentation mapping for the DIET jar: domain values in, bounded positions
/// out. Pure and deterministic, so the same day always piles the same way and
/// tests can check bounds and containment.
///
/// Blocks are sized by area: a food's block covers `kcal × areaPerKcal`. The
/// pile is built in logging order on a height map: each block drops at its x,
/// settles on the highest point under it and tips toward its centre of mass
/// until a second contact (or the tilt limit) holds it; an unsupported block
/// slides downhill, and a block that finds a much lower spot close by rolls
/// into it. The pile's height approximates the share of the target eaten
/// (the hero number is exact); past the mouth the pile rises out of the jar,
/// and if it would leave the mechanism region every block shrinks together.
struct JarGeometry {
    var layout: MachineLayout
    var targetKcal: Double

    var mech: CGRect { layout.mechanismRect }
    /// Space above the jar mouth for an over-target pile.
    static let overflowRoom: CGFloat = 70
    static let wall: CGFloat = 7
    static let cornerRadius: CGFloat = 30
    /// Share of the interior height the target line sits at.
    static let targetFraction: CGFloat = 0.74
    /// How densely tipped blocks fill the jar, measured on the prototype pile.
    static let packing: CGFloat = 0.72
    static let maxTilt: Double = 0.26
    static let column: CGFloat = 2

    var outer: CGRect {
        let w = (layout.contentWidth * 0.58).rounded()
        let top = mech.minY + Self.overflowRoom
        return CGRect(x: layout.faceWidth / 2 - w / 2, y: top, width: w, height: mech.maxY - 8 - top)
    }
    var interior: CGRect { outer.insetBy(dx: Self.wall, dy: Self.wall) }
    var floorY: CGFloat { interior.maxY }
    var innerRadius: CGFloat { Self.cornerRadius - Self.wall }
    /// The etched TARGET line.
    var targetLineY: CGFloat { floorY - interior.height * Self.targetFraction }
    /// The pile never rises above this.
    var ceilingY: CGFloat { mech.minY + 6 }
    var areaPerKcal: CGFloat {
        guard targetKcal > 0 else { return 1 }
        return interior.width * (floorY - targetLineY) * Self.packing / CGFloat(targetKcal)
    }

    /// Blocks released inside this rect drop into the jar.
    func landingRect(pileTop: CGFloat) -> CGRect {
        let top = mech.minY - 40
        return CGRect(x: outer.minX - 12, y: top, width: outer.width + 24, height: max(min(pileTop, outer.maxY) - top, 40))
    }

    /// Chunky blocks: area follows energy, proportions vary per food (1.2 to 2.0 wide).
    func blockSize(kcal: Double, seed: UInt64, scale: CGFloat = 1) -> CGSize {
        let u = CGFloat(Self.unit(seed >> 8))
        let aspect = 1.2 + 0.8 * u
        let area = CGFloat(max(kcal, 20)) * areaPerKcal * scale * scale
        let w = min(max((area * aspect).squareRoot(), 34 * scale), interior.width * 0.92)
        return CGSize(width: w, height: max(area / w, 18 * scale))
    }

    /// The x a block drops at when nobody dropped it by hand.
    func defaultDropX(width: CGFloat, seed: UInt64) -> CGFloat {
        interior.minX + width / 2 + CGFloat(Self.unit(Self.mix(seed ^ 0x9E37_79B9_7F4A_7C15))) * max(interior.width - width, 0)
    }

    // MARK: Pile

    var columnXs: [CGFloat] {
        let n = Int((interior.width / Self.column).rounded(.up))
        return (0..<n).map { interior.minX + (CGFloat($0) + 0.5) * Self.column }
    }

    /// The empty jar's floor, curving up into its rounded bottom corners.
    func emptySurface() -> [CGFloat] {
        let r = innerRadius
        return columnXs.map { (x: CGFloat) -> CGFloat in
            let d = min(x - interior.minX, interior.maxX - x)
            guard d < r else { return floorY }
            let dx = r - d
            return floorY - (r - (r * r - dx * dx).squareRoot())
        }
    }

    func pile(_ items: [JarItem]) -> JarPile {
        var scale: CGFloat = 1
        var result = pile(items, scale: scale)
        while result.top < ceilingY && scale > 0.3 {
            scale *= 0.92
            result = pile(items, scale: scale)
        }
        return result
    }

    func pile(_ items: [JarItem], scale: CGFloat) -> JarPile {
        let xs = columnXs
        var surface = emptySurface()
        var poses: [JarPose] = []
        for item in items {
            let size = blockSize(kcal: item.kcal, seed: item.seed, scale: scale)
            let start = clampX(item.dropX ?? defaultDropX(width: size.width, seed: item.seed), size: size, angle: 0)
            var best = settle(at: start, size: size, surface: surface, xs: xs)
            // A block that bounces off a narrow top rolls into a much lower spot close by.
            for k in [-1, 1, -2, 2, -3, 3] {
                let x = clampX(start + CGFloat(k) * size.width * 0.35, size: size, angle: 0)
                let candidate = settle(at: x, size: size, surface: surface, xs: xs)
                if candidate.bottom > best.bottom + size.height * 0.45 + CGFloat(abs(k)) * 2 { best = candidate }
            }
            var pose = Self.pose(bottomCenter: CGPoint(x: best.x, y: best.bottom), slope: best.slope, size: size)
            // Blocks that land flat still sit a little askew, like tossed ones;
            // they are lifted below so they rest on a corner instead of sinking in.
            if abs(best.slope) < 0.05 {
                pose.angle += (Self.unit(Self.mix(item.seed ^ 0xA5A5_5A5A_C3C3_3C3C)) - 0.5) * 0.24
            }
            // A tipped block is wider than it was upright: nudge its corners off the glass.
            let cornerXs = Self.corners(of: pose).map(\.x)
            if let low = cornerXs.min(), low < interior.minX { pose.center.x += interior.minX - low }
            if let high = cornerXs.max(), high > interior.maxX { pose.center.x -= high - interior.maxX }
            // Nothing may sit below the surface it fell on.
            let sink = Self.sink(Self.corners(of: pose), surface: surface, xs: xs)
            if sink > 0 { pose.center.y -= sink }
            Self.raise(&surface, xs: xs, under: Self.corners(of: pose))
            poses.append(pose)
        }
        return JarPile(poses: poses, top: surface.min() ?? floorY, surface: surface, scale: scale)
    }

    /// Highest point of the surface under a block of `width` centred at `x`.
    func surfaceTop(_ surface: [CGFloat], x: CGFloat, width: CGFloat) -> CGFloat {
        var top = floorY
        for (i, cx) in columnXs.enumerated() where abs(cx - x) <= width / 2 && i < surface.count { top = min(top, surface[i]) }
        return top
    }

    private func clampX(_ x: CGFloat, size: CGSize, angle: Double) -> CGFloat {
        let half = min((size.width * CGFloat(cos(angle)) + size.height * CGFloat(abs(sin(angle)))) / 2, interior.width / 2)
        return min(max(x, interior.minX + half), interior.maxX - half)
    }

    private struct Rest {
        var x: CGFloat
        var bottom: CGFloat
        var slope: CGFloat
    }

    /// Drops a block at `x` and lets it tip and slide until it rests.
    private func settle(at x: CGFloat, size: CGSize, surface: [CGFloat], xs: [CGFloat]) -> Rest {
        var c = x
        var contact = Self.contact(c, width: size.width, surface: surface, xs: xs)
        for _ in 0..<10 where contact.free {
            let next = clampX(c + CGFloat(contact.direction) * size.width * 0.2, size: size, angle: 0)
            if abs(next - c) < 0.5 { break }
            c = next
            contact = Self.contact(c, width: size.width, surface: surface, xs: xs)
        }
        // Tipped blocks are wider; keep their corners off the walls.
        let clamped = clampX(c, size: size, angle: Double(atan(contact.slope)))
        if clamped != c {
            c = clamped
            contact = Self.contact(c, width: size.width, surface: surface, xs: xs)
        }
        return Rest(x: c, bottom: contact.y + contact.slope * (c - contact.x), slope: contact.slope)
    }

    /// The highest point under the block, and the slope it tips to from there.
    private static func contact(_ c: CGFloat, width w: CGFloat, surface: [CGFloat], xs: [CGFloat])
        -> (x: CGFloat, y: CGFloat, slope: CGFloat, free: Bool, direction: Int) {
        let under = xs.indices.filter { abs(xs[$0] - c) <= w / 2 }
        guard !under.isEmpty else { return (c, surface.min() ?? 0, 0, false, 0) }
        let top = under.map { surface[$0] }.min()!
        let level = under.filter { surface[$0] <= top + 0.5 }
        let pivot = level.min { abs(xs[$0] - c) < abs(xs[$1] - c) }!
        let px = xs[pivot]
        let maxSlope = CGFloat(tan(maxTilt))
        if px < c - 1 {
            // Centre of mass right of the pivot: the right side goes down.
            let ratios = under.filter { xs[$0] > px + 0.5 }.map { (surface[$0] - top) / (xs[$0] - px) }
            let m = ratios.min() ?? .greatestFiniteMagnitude
            return (px, top, min(m, maxSlope), m > maxSlope, 1)
        }
        if px > c + 1 {
            let ratios = under.filter { xs[$0] < px - 0.5 }.map { (surface[$0] - top) / (xs[$0] - px) }
            let m = ratios.max() ?? -.greatestFiniteMagnitude
            return (px, top, max(m, -maxSlope), m < -maxSlope, -1)
        }
        return (px, top, 0, false, 0)
    }

    static func pose(bottomCenter b: CGPoint, slope: CGFloat, size: CGSize) -> JarPose {
        let angle = Double(atan(slope))
        let up = CGVector(dx: CGFloat(sin(angle)), dy: -CGFloat(cos(angle)))
        return JarPose(center: CGPoint(x: b.x + up.dx * size.height / 2, y: b.y + up.dy * size.height / 2), angle: angle, size: size)
    }

    /// Corners of a posed block: bottom-left, bottom-right, top-right, top-left.
    static func corners(of pose: JarPose) -> [CGPoint] {
        let c = CGFloat(cos(pose.angle)), s = CGFloat(sin(pose.angle))
        let hw = pose.size.width / 2, hh = pose.size.height / 2
        let local: [CGPoint] = [CGPoint(x: -hw, y: hh), CGPoint(x: hw, y: hh), CGPoint(x: hw, y: -hh), CGPoint(x: -hw, y: -hh)]
        return local.map { (p: CGPoint) -> CGPoint in
            let x: CGFloat = pose.center.x + p.x * c - p.y * s
            let y: CGFloat = pose.center.y + p.x * s + p.y * c
            return CGPoint(x: x, y: y)
        }
    }

    /// How far a posed block reaches below the surface (0 when it rests on or above it).
    private static func sink(_ poly: [CGPoint], surface: [CGFloat], xs: [CGFloat]) -> CGFloat {
        var deepest: CGFloat = 0
        for (i, x) in xs.enumerated() {
            var lowest: CGFloat?
            for k in 0..<poly.count {
                let a = poly[k], b = poly[(k + 1) % poly.count]
                guard a.x != b.x, (a.x - x) * (b.x - x) <= 0 else { continue }
                let y = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
                lowest = max(lowest ?? y, y)
            }
            if let lowest { deepest = max(deepest, lowest - surface[i]) }
        }
        return deepest
    }

    /// Lifts the surface to the top of a placed block, column by column.
    private static func raise(_ surface: inout [CGFloat], xs: [CGFloat], under poly: [CGPoint]) {
        for (i, x) in xs.enumerated() {
            var best: CGFloat?
            for k in 0..<poly.count {
                let a = poly[k], b = poly[(k + 1) % poly.count]
                guard a.x != b.x, (a.x - x) * (b.x - x) <= 0 else { continue }
                let y = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
                best = min(best ?? y, y)
            }
            if let best { surface[i] = min(surface[i], best) }
        }
    }

    // MARK: Seeds

    /// A stable seed from the entry's own fields (ids are random per launch,
    /// so fixtures would pile differently every run).
    static func seed(for entry: FoodEntry) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        // Energy is left out so editing the grams resizes a block without moving it.
        let key = "\(entry.name)|\(Int(entry.loggedAt.timeIntervalSinceReferenceDate))"
        for byte in key.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return mix(h)
    }

    /// splitmix64 finaliser: spreads nearby keys apart.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static func unit(_ x: UInt64) -> Double { Double(x & 0xFFFF) / 65535 }
}

/// Block colour by what the food mostly is, so a day reads at a glance.
enum FoodTint: Int, CaseIterable {
    case carbs, protein, fat, mixed, quick

    static func of(_ n: Nutrients) -> FoodTint {
        guard n.hasMacros else { return .quick }
        let p = (n.protein ?? 0) * 4, c = (n.carbs ?? 0) * 4, f = (n.fat ?? 0) * 9
        let total = p + c + f
        guard total > 0 else { return .mixed }
        if p / total > 0.5 { return .protein }
        if c / total > 0.5 { return .carbs }
        if f / total > 0.5 { return .fat }
        return .mixed
    }
}

/// The loading rail and its block sizes, inside the controls region.
struct RailGeometry {
    var layout: MachineLayout

    var controls: CGRect { layout.controlsRect }
    var rowHeight: CGFloat { controls.height * 0.54 }
    var gap: CGFloat { 10 }
    var buttonRow: CGRect {
        let y = controls.minY + rowHeight + controls.height * 0.08
        return CGRect(x: controls.minX, y: y, width: controls.width, height: max(controls.maxY - y, 44))
    }
    var slotWidth: CGFloat { (controls.width - 3 * gap) / 4 }

    static let heightFactors: [Int: CGFloat] = [50: 0.58, 100: 0.68, 250: 0.82, 500: 1.0]

    func quickBlockSize(kcal: Int) -> CGSize {
        CGSize(width: slotWidth, height: rowHeight * (Self.heightFactors[kcal] ?? 0.7))
    }

    /// Centre of the quick block resting in its slot (bottom-aligned on the rail).
    func quickBlockHome(kcal: Int) -> CGPoint {
        let i = CGFloat(QuickAdd.weights.firstIndex(of: kcal) ?? 0)
        let size = quickBlockSize(kcal: kcal)
        return CGPoint(x: controls.minX + i * (slotWidth + gap) + slotWidth / 2,
                       y: controls.minY + rowHeight - size.height / 2)
    }

    /// A logged-food block: wider and taller with more energy, within the rail row.
    func foodBlockSize(kcal: Double) -> CGSize {
        let h = min(max(36 + CGFloat(kcal) / 9, 44), rowHeight)
        let w = min(max(controls.width * 0.42 + CGFloat(kcal) / 6, controls.width * 0.5), controls.width * 0.78)
        return CGSize(width: w, height: h)
    }

    func foodBlockHome(kcal: Double) -> CGPoint {
        let size = foodBlockSize(kcal: kcal)
        return CGPoint(x: controls.minX + size.width / 2, y: controls.minY + rowHeight - size.height / 2)
    }

    var railLineY: CGFloat { controls.minY + rowHeight }
}

/// The TRAIN hourglass: its size follows the rest length, its sand follows time.
struct HourglassGeometry {
    var layout: MachineLayout

    var mech: CGRect { layout.mechanismRect }
    /// Space kept clear above the tallest glass for the coach's note.
    static let coachClearance: CGFloat = 128
    var minHeight: CGFloat { mech.height * 0.38 }
    /// Space under the glass for its engraved rest length.
    static let labelClearance: CGFloat = 34
    var maxHeight: CGFloat { max(mech.height - Self.coachClearance - Self.labelClearance, minHeight) }

    /// The glass stands near the bottom of the mechanism and grows upward. It
    /// keeps clear of the coach's note on the left (34% of the content width),
    /// so it sits right of centre when it is wide, without leaving the face.
    func center(forHeight h: CGFloat) -> CGPoint {
        let half = h * Self.aspect / 2
        let clearOfNote = layout.side + layout.contentWidth * Self.noteShare + 12 + half
        let rightLimit = layout.side + layout.contentWidth - half
        let x = min(max(layout.faceWidth / 2, clearOfNote), max(rightLimit, layout.faceWidth / 2))
        return CGPoint(x: x, y: mech.maxY - Self.labelClearance - h / 2)
    }

    /// Share of the content width the coach's note takes on the left.
    static let noteShare: CGFloat = 0.34

    /// Centre of the engraved rest length under the glass.
    var labelY: CGFloat { mech.maxY - Self.labelClearance / 2 + 2 }
    static let sizeRange = 30.0...360.0

    /// Height for a total rest length: 30 s is the smallest glass, 6 min the largest.
    func height(forSeconds seconds: Double) -> CGFloat {
        let s = min(max(seconds, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        let t = (s - Self.sizeRange.lowerBound) / (Self.sizeRange.upperBound - Self.sizeRange.lowerBound)
        return minHeight + (maxHeight - minHeight) * CGFloat(t.squareRoot())
    }

    /// Width is fixed to the height so the glass keeps its proportions: the desk
    /// hourglass's square plates, turned 28°, show about two thirds of its height.
    static let aspect: CGFloat = 0.67
}

/// Where the figurine stands on the BODY face.
struct FigureGeometry {
    var layout: MachineLayout

    var mech: CGRect { layout.mechanismRect }
    /// Points per figure unit.
    var unit: CGFloat { mech.height * 0.80 }
    /// The feet, in face-local points; the turntable sits just under them.
    var feet: CGPoint { CGPoint(x: layout.faceWidth / 2, y: mech.maxY - 40) }
    /// The figure stands this far proud of the face.
    static let depth: CGFloat = 90
    /// Resting three-quarter turn, so the orthographic camera sees its depth
    /// (the clay mockup's −0.42, design/mockups/body/mannequin.py).
    static let restYaw: Float = -0.42
    /// The whole stand leans its top toward the viewer by this much (radians), so
    /// the orthographic camera looks a little down onto the dial, as in the mockup.
    static let lean: Float = 0.16
    /// How far scrubbing can swing it off the resting turn.
    static let maxSwing: Double = 0.6

    /// A figure-unit point (y up) in face-local points (y down).
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: feet.x + x * unit, y: feet.y - y * unit)
    }
}

/// TRAIN's desk hourglass (Wei's pick, 13 Oct 2026, from reference photos): square
/// wood plates, four black posts with brass sleeves and dome nuts, round clear
/// bulbs and fine sand. Glass units: height 1 from the feet to the top nuts,
/// centred on the origin, y up. It mirrors concept G in
/// design/mockups/train/scene.py divided by that model's 2.48 height.
enum DeskHourglass {
    static let unit: Float = 1 / 2.48

    /// Outer bulb profile from the neck (y 0) to the bulb's end, as (y, radius).
    static let knots: [SIMD2<Float>] = [
        SIMD2(0, 0.04), SIMD2(0.06, 0.07), SIMD2(0.15, 0.27), SIMD2(0.3, 0.44), SIMD2(0.5, 0.52),
        SIMD2(0.7, 0.5), SIMD2(0.85, 0.42), SIMD2(0.95, 0.3), SIMD2(1.0, 0.2),
    ].map { $0 * unit }
    static let wall: Float = 0.03 * unit
    static var bulbEnd: Float { knots.last!.x }

    /// The outer profile, densely sampled along a Catmull-Rom spline through the knots.
    static let profile: [SIMD2<Float>] = {
        let p = [knots[0]] + knots + [knots[knots.count - 1]]
        var out: [SIMD2<Float>] = []
        for i in 1..<(p.count - 2) {
            for k in 0..<12 {
                let t = Float(k) / 12, t2 = t * t, t3 = t2 * t
                let a = 2 * p[i], b = p[i + 1] - p[i - 1]
                let c = 2 * p[i - 1] - 5 * p[i] + 4 * p[i + 1] - p[i + 2]
                let d = -p[i - 1] + 3 * p[i] - 3 * p[i + 1] + p[i + 2]
                out.append(0.5 * (a + b * t + c * t2 + d * t3))
            }
        }
        out.append(knots[knots.count - 1])
        return out
    }()

    /// Outer radius at height `y` (either bulb; the glass is symmetric about the neck).
    static func outerRadius(_ y: Float) -> Float {
        let h = min(abs(y), bulbEnd)
        guard let i = profile.firstIndex(where: { $0.x >= h }), i > 0 else { return profile[0].y }
        let a = profile[i - 1], b = profile[i]
        let t = b.x > a.x ? (h - a.x) / (b.x - a.x) : 0
        return a.y + (b.y - a.y) * t
    }

    static func innerRadius(_ y: Float) -> Float { max(outerRadius(y) - wall, 0.004) }

    // Frame, from the mockup's numbers.
    static let collarRadius: Float = 0.24 * unit, collarHeight: Float = 0.05 * unit, collarY: Float = 1.02 * unit
    static let plateSide: Float = 1.22 * unit, plateThickness: Float = 0.13 * unit
    static let plateInner: Float = 1.045 * unit
    static var plateY: Float { plateInner + plateThickness / 2 }
    static let postOffset: Float = 0.5 * unit, postRadius: Float = 0.032 * unit
    static var postLength: Float { 2 * plateInner }
    static let sleeveRadius: Float = 0.042 * unit, sleeveHeight: Float = 0.13 * unit
    static var sleeveY: Float { plateInner - sleeveHeight / 2 }
    static let nutRadius: Float = 0.055 * unit
    static var nutY: Float { plateInner + plateThickness + 0.01 * unit }

    /// Resting presentation: turned so all four posts show and tipped toward the
    /// camera so the plates' tops read in the orthographic view.
    static let yaw: Float = 28 * .pi / 180
    static let pitch: Float = 10 * .pi / 180

    // Sand. Both shapes are drawn upright in the world: the draining sand in the
    // top bulb (y > 0) and the pile in the bottom bulb (y < 0).
    static let neckY: Float = 0.05 * unit
    static let floorY: Float = -0.97 * unit
    /// A full load fills the top bulb from the neck to this height.
    static let fullLevel: Float = 0.6 * unit
    static let sandInset: Float = 0.006 * unit

    static func sandRadius(_ y: Float) -> Float { max(innerRadius(y) - sandInset, 0) }

    /// Sand volume between two heights against the inner wall.
    static func volume(from a: Float, to b: Float, steps: Int = 60) -> Float {
        guard b > a else { return 0 }
        let h = (b - a) / Float(steps)
        var v: Float = 0
        for i in 0..<steps {
            let r = sandRadius(a + (Float(i) + 0.5) * h)
            v += .pi * r * r * h
        }
        return v
    }

    static let fullVolume: Float = volume(from: neckY, to: fullLevel)

    /// Height whose column from `base` holds `target` volume.
    static func level(from base: Float, holding target: Float, limit: Float) -> Float {
        var lo = base, hi = limit
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if volume(from: base, to: mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Sand left in the top bulb with `amount` (0...1) of a load: it follows the
    /// wall from the neck up to its level and dishes in toward the centre. A closed
    /// lathe profile from the axis at the neck to the axis at the dish.
    static func drainProfile(_ amount: Float) -> [SIMD2<Float>] {
        let a = min(max(amount, 0), 1)
        let top = level(from: neckY, holding: a * fullVolume, limit: fullLevel + 0.05 * unit)
        let dish = min(0.07 * unit, (top - neckY) * 0.5)
        var pts: [SIMD2<Float>] = [SIMD2(neckY, 0)]
        let rings = 24
        for i in 0...rings {
            let y = neckY + (top - neckY) * Float(i) / Float(rings)
            pts.append(SIMD2(y, sandRadius(y)))
        }
        let rTop = sandRadius(top)
        pts.append(SIMD2(top - dish * 0.55, rTop * 0.5))
        pts.append(SIMD2(top - dish, 0))
        return pts
    }

    /// The pile in the bottom bulb holding `amount` (0...1) of a load: a level fill
    /// from the floor carrying a cone that peaks under the neck.
    static func heapProfile(_ amount: Float) -> [SIMD2<Float>] {
        let b = min(max(amount, 0), 1)
        let fill = level(from: floorY, holding: 0.72 * b * fullVolume, limit: -neckY - 0.1 * unit)
        let rFill = sandRadius(fill)
        let cone = rFill > 0 ? min(3 * 0.28 * b * fullVolume / (.pi * rFill * rFill), 0.32 * unit) : 0
        var pts: [SIMD2<Float>] = [SIMD2(floorY, 0)]
        let rings = 24
        for i in 0...rings {
            let y = floorY + (fill - floorY) * Float(i) / Float(rings)
            pts.append(SIMD2(y, sandRadius(y)))
        }
        pts.append(SIMD2(fill + cone * 0.35, rFill * 0.55))
        pts.append(SIMD2(fill + cone, 0.004 * unit))
        pts.append(SIMD2(fill + cone, 0))
        return pts
    }

    /// Where the stream lands: the pile's peak (y < 0).
    static func heapApex(_ amount: Float) -> Float { heapProfile(amount).last!.x }
}

/// Formats for the type layer.
enum Readout {
    static func kcal(_ value: Double) -> String {
        let n = Int(value.rounded())
        let formatted = abs(n).formatted(.number.grouping(.automatic))
        return n < 0 ? "−" + formatted : formatted
    }

    static func grams(_ value: Double?) -> String {
        guard let value else { return "?" }
        return value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    static func load(_ kg: Double) -> String {
        kg.rounded() == kg ? String(Int(kg)) : String(format: "%.1f", kg)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
