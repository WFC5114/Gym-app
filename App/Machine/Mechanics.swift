import CoreGraphics
import Foundation

/// Presentation mapping for the DIET deck: domain values in, bounded positions out.
/// Pure and deterministic so tests can check bounds and containment.
struct DeckGeometry {
    var layout: MachineLayout
    var targetKcal: Double

    var mech: CGRect { layout.mechanismRect }
    var centerX: CGFloat { layout.faceWidth / 2 }
    var deckWidth: CGFloat { layout.contentWidth * 0.92 }
    var plinthHeight: CGFloat { 18 }
    var plateThickness: CGFloat { 14 }
    var springRestLength: CGFloat { min(118, mech.height * 0.28) }
    /// Compression in points per 100% of the calorie target.
    var travelPerTarget: CGFloat { springRestLength * 0.56 }
    /// Stack height in points per 100% of the calorie target.
    var stackPerTarget: CGFloat { mech.height * 0.37 }
    var springXOffsets: [CGFloat] { [-deckWidth * 0.32, deckWidth * 0.32] }
    var slabWidth: CGFloat { deckWidth * 0.86 }
    static let minSlabHeight: CGFloat = 6

    var plinthRect: CGRect {
        CGRect(x: layout.side, y: mech.maxY - plinthHeight, width: layout.contentWidth, height: plinthHeight)
    }

    /// Plate top when nothing is loaded.
    var plateTopUnloaded: CGFloat { mech.maxY - plinthHeight - springRestLength - plateThickness }

    /// Resting compression for a load, bounded at 120% of target (`Deck.restingDepth`).
    /// The number on the face always shows the exact value; only the mechanism is bounded.
    func restingDisplacement(eaten: Double) -> CGFloat {
        CGFloat(Deck.restingDepth(eaten: eaten, target: targetKcal)) * travelPerTarget
    }

    func plateTop(displacement: CGFloat) -> CGFloat { plateTopUnloaded + displacement }

    func springLength(displacement: CGFloat) -> CGFloat { max(springRestLength - displacement, 12) }

    /// Raw slab height for an entry, before the stack is fitted.
    func rawSlabHeight(kcal: Double) -> CGFloat {
        guard targetKcal > 0 else { return Self.minSlabHeight }
        return max(CGFloat(kcal / targetKcal) * stackPerTarget, Self.minSlabHeight)
    }

    /// The tallest the stack may draw: it stops 24 pt under the mechanism top
    /// even at full compression.
    var maxStackHeight: CGFloat { plateTop(displacement: travelPerTarget * 1.2) - mech.minY - 24 }

    /// Slab heights for a day, scaled down together only if they would overflow.
    func slabHeights(kcals: [Double]) -> (heights: [CGFloat], scaled: Bool) {
        let raw = kcals.map(rawSlabHeight)
        let total = raw.reduce(0, +)
        guard total > maxStackHeight, total > 0 else { return (raw, false) }
        let f = maxStackHeight / total
        return (raw.map { $0 * f }, true)
    }

    /// Where the stack top sits at exactly 100% of target: the engraved TARGET line.
    var targetLineY: CGFloat { plateTop(displacement: travelPerTarget) - stackPerTarget }

    /// Blocks released inside this rect drop onto the deck.
    func landingRect(stackTop: CGFloat) -> CGRect {
        let top = mech.minY - 40
        return CGRect(x: centerX - deckWidth / 2, y: top, width: deckWidth, height: max(stackTop - top, 40))
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
        let i = CGFloat(Deck.weights.firstIndex(of: kcal) ?? 0)
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
