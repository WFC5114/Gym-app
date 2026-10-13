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

    /// Chunky blocks: area follows energy, proportions vary per food (1.5 to 2.4 wide).
    func blockSize(kcal: Double, seed: UInt64, scale: CGFloat = 1) -> CGSize {
        let u = CGFloat(Self.unit(seed >> 8))
        let aspect = 1.5 + 0.9 * u
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
            // A tipped block is wider than it was upright: nudge its corners off the glass.
            let cornerXs = Self.corners(of: pose).map(\.x)
            if let low = cornerXs.min(), low < interior.minX { pose.center.x += interior.minX - low }
            if let high = cornerXs.max(), high > interior.maxX { pose.center.x -= high - interior.maxX }
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

    /// The glass stands near the bottom of the mechanism and grows upward.
    func center(forHeight h: CGFloat) -> CGPoint {
        CGPoint(x: layout.faceWidth / 2, y: mech.maxY - Self.labelClearance - h / 2)
    }

    /// Centre of the engraved rest length under the glass.
    var labelY: CGFloat { mech.maxY - Self.labelClearance / 2 + 2 }
    static let sizeRange = 30.0...360.0

    /// Height for a total rest length: 30 s is the smallest glass, 6 min the largest.
    func height(forSeconds seconds: Double) -> CGFloat {
        let s = min(max(seconds, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        let t = (s - Self.sizeRange.lowerBound) / (Self.sizeRange.upperBound - Self.sizeRange.lowerBound)
        return minHeight + (maxHeight - minHeight) * CGFloat(t.squareRoot())
    }

    /// Width is fixed to the height so the glass keeps its proportions.
    static let aspect: CGFloat = 0.56
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
