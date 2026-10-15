import CoreGraphics
import Foundation

/// TRAIN's sand as real grains (Wei, 15 Oct 2026: "the sand in the hourglass
/// also obey physics"). A granular cellular automaton in the glass's own frame
/// (x across, z along the axis toward the A bulb, glass units from
/// night-train.json): each grain falls along gravity, slides off a slope
/// steeper than its angle of repose, piles, runs through the neck in a thin
/// stream and sloshes as the glass turns over, because gravity turns with it.
///
/// Wall-clock time stays the truth: while a rest runs, a grain may only drop
/// from the upper bulb into the lower one while the upper bulb holds more than
/// the rest's remaining share, so the glass empties exactly when the rest
/// ends. With no rest running the sand runs freely, as a real glass does.
///
/// The app draws Blender's "full" picture wherever a grain is (`mask()`), so
/// the grains are Blender's sand seen through Blender's glass.
final class SandGlass {
    /// One cell, in glass units (about 1.4 pt on the largest glass).
    static let cell = 0.004

    let cols: Int
    let rows: Int
    /// Grains in the glass; one bulb full to the sand line.
    let total: Int
    private(set) var grid: [UInt8]
    /// Grains in the A bulb (z > 0).
    private(set) var countA = 0
    /// Bumped whenever a grain moves, so views redraw only then.
    private(set) var version = 0

    private let inside: [Bool]
    /// Inside cells ordered farthest-along-gravity first, one order per
    /// direction, and each with its rows swept left to right and right to left:
    /// sweeps alternate so grains don't drift to one side.
    private var orders: [[Int32]] = Array(repeating: [], count: 16)
    private var sweep = 0
    private var lastTarget: Int?
    private var rng: UInt64 = 0x9E3779B97F4A7C15
    private var asleep = false
    /// No grain moved last step and nothing has disturbed them since.
    var isStill: Bool { asleep }
    private var lastDirection = -1

    /// The eight grid directions counter-clockwise from +x, as (column, row)
    /// steps; rows run down the glass, so +z is a negative row step.
    private static let steps: [(Int, Int)] = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)]

    /// `inner` is the glass's inner wall from the neck out as (z, radius) in
    /// glass units; `sandLine` is how far up one bulb its full load reaches.
    init?(inner: [[Double]], sandLine: Double) {
        let wall = inner.filter { $0.count == 2 }.map { (z: $0[0], r: $0[1]) }.sorted { $0.z < $1.z }
        guard let end = wall.last, wall.count >= 2 else { return nil }
        let widest = wall.map(\.r).max() ?? 0
        cols = 2 * Int((widest / Self.cell).rounded(.up))
        rows = 2 * Int((end.z / Self.cell).rounded(.up))
        func radius(_ z: Double) -> Double {
            let z = abs(z)
            guard z <= end.z else { return -1 }
            for (a, b) in zip(wall, wall.dropFirst()) where z <= b.z {
                return a.r + (b.r - a.r) * (z - a.z) / max(b.z - a.z, 1e-9)
            }
            return end.r
        }
        var inside = [Bool](repeating: false, count: cols * rows)
        var full = 0
        for row in 0..<rows {
            let z = (Double(rows) / 2 - Double(row) - 0.5) * Self.cell
            let r = radius(z)
            for col in 0..<cols {
                let x = (Double(col) + 0.5 - Double(cols) / 2) * Self.cell
                if abs(x) <= r {
                    inside[row * cols + col] = true
                    if z > 0 && z <= sandLine { full += 1 }
                }
            }
        }
        self.inside = inside
        total = full
        grid = [UInt8](repeating: 0, count: cols * rows)
        guard total > 0 else { return nil }
        for k in 0..<8 {
            let (dc, dr) = Self.steps[k]
            var cells: [(Int32, Int)] = []
            for i in 0..<(cols * rows) where inside[i] {
                cells.append((Int32(i), (i % cols) * dc + (i / cols) * dr))
            }
            orders[k] = cells.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }.map(\.0)
            orders[k + 8] = cells.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }.map(\.0)
        }
    }

    convenience init?(glass: RenderedArt.Glass) {
        guard let inner = glass.inner, let line = glass.sandLine else { return nil }
        self.init(inner: inner.map { $0.map(Double.init) }, sandLine: Double(line))
    }

    func isInside(col: Int, row: Int) -> Bool {
        col >= 0 && col < cols && row >= 0 && row < rows && inside[row * cols + col]
    }

    // MARK: Settling

    /// Puts the sand at rest straight away: `top` grains in the upper bulb,
    /// lying on its neck with a dimple over the hole, the rest heaped in the
    /// lower one. `aIsUp` says which bulb is up.
    func settle(top: Int, aIsUp: Bool) {
        grid = [UInt8](repeating: 0, count: cols * rows)
        let top = min(max(top, 0), total)
        let half = rows / 2
        // Lower bulb: rows from its far end toward the neck, partial rows heaped in the middle.
        let lowerRows = aIsUp ? Array((half..<rows).reversed()) : Array(0..<half)
        fill(total - top, rows: lowerRows, middleFirst: true)
        // Upper bulb: rows from the neck out, a partial row against the walls.
        let upperRows = aIsUp ? Array((0..<half).reversed()) : Array(half..<rows)
        fill(top, rows: upperRows, middleFirst: false)
        countA = (0..<(half * cols)).reduce(0) { $0 + Int(grid[$1]) }
        asleep = false
        version &+= 1
    }

    private func fill(_ count: Int, rows order: [Int], middleFirst: Bool) {
        var left = count
        for row in order where left > 0 {
            let cells = (0..<cols).filter { inside[row * cols + $0] }
            let mid = Double(cols - 1) / 2
            let ranked = cells.sorted { abs(Double($0) - mid) < abs(Double($1) - mid) }
            for col in (middleFirst ? ranked : ranked.reversed()).prefix(left) {
                grid[row * cols + col] = 1
                left -= 1
            }
        }
    }

    // MARK: Stepping

    /// Grains in the upper bulb for a glass at `angle` (0 upright, π turned over).
    func upperCount(angle: Double) -> Int { cos(angle) >= 0 ? countA : total - countA }

    /// Advances the sand by `dt` seconds for a glass turned to `angle` (radians,
    /// counter-clockwise on screen, 0 with A up). `upperTarget` is what the
    /// upper bulb must still hold while a rest runs, nil for free flow.
    func step(_ dt: Double, angle: Double, upperTarget: Int?) {
        // Gravity in the glass's frame: straight down the screen, turned back by the glass.
        let gx = -sin(angle), gz = -cos(angle)
        let direction = (Int((atan2(gz, gx) / (.pi / 4)).rounded()) % 8 + 8) % 8
        if direction != lastDirection { asleep = false; lastDirection = direction }
        let aIsUp = cos(angle) >= 0
        if upperTarget != lastTarget {
            // A rest started or ended, or another grain is due through the neck.
            if upperTarget == nil || upperCount(angle: angle) > upperTarget! { asleep = false }
            lastTarget = upperTarget
        }
        guard !asleep else { return }
        let passes = max(1, min(6, Int((dt * 240).rounded())))
        var movedAny = false
        for _ in 0..<passes {
            sweep += 1
            var budget = Int.max
            if let target = upperTarget { budget = max(upperCount(angle: angle) - target, 0) }
            // Straight falls first, through the whole glass, so a hole at the
            // neck climbs its column and the upper surface caves in over the
            // neck as real sand does; then rolls and slides.
            let moved = pass(direction: direction, aIsUp: aIsUp, budget: &budget, fallOnly: true)
                + pass(direction: direction, aIsUp: aIsUp, budget: &budget, fallOnly: false)
            if moved > 0 { movedAny = true } else { break }
        }
        if movedAny { version &+= 1 } else { asleep = true }
    }

    private func random() -> UInt64 {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        return rng
    }

    /// One sweep: every grain tries to fall, then to roll diagonally, then (on a
    /// shallow slope) to slide two cells sideways and one down.
    private func pass(direction k: Int, aIsUp: Bool, budget: inout Int, fallOnly: Bool) -> Int {
        let half = rows / 2
        let down = Self.steps[k]
        let left = Self.steps[(k + 1) % 8], right = Self.steps[(k + 7) % 8]
        let axial = k % 2 == 0
        let side1 = Self.steps[(k + 2) % 8], side2 = Self.steps[(k + 6) % 8]
        var moved = 0
        var spend = budget

        /// Moves the grain at (col, row) by (dc, dr) if it can; `via` must be clear too.
        func move(_ col: Int, _ row: Int, _ dc: Int, _ dr: Int, via: (Int, Int)? = nil) -> Bool {
            let c = col + dc, rr = row + dr
            guard c >= 0, c < cols, rr >= 0, rr < rows else { return false }
            let j = rr * cols + c
            guard inside[j], grid[j] == 0 else { return false }
            if let via {
                let v = (row + via.1) * cols + col + via.0
                guard inside[v], grid[v] == 0 else { return false }
            }
            let fromA = row < half, toA = rr < half
            if fromA != toA {
                // Through the neck: downward only as fast as the rest allows.
                if fromA == aIsUp {
                    guard spend > 0 else { return false }
                    spend -= 1
                }
                countA += toA ? 1 : -1
            }
            grid[j] = 1
            grid[row * cols + col] = 0
            moved += 1
            return true
        }

        for index in orders[k + (sweep % 2) * 8] {
            let i = Int(index)
            guard grid[i] != 0 else { continue }
            let col = i % cols, row = i / cols
            if move(col, row, down.0, down.1) || fallOnly { continue }
            // In the draining upper bulb only a grain with nothing on top of it
            // rolls or slides: friction holds the packed sand, so a hole climbs
            // straight up its column and the surface caves in over the neck.
            // Below, grains land from the stream and tumble down the heap.
            if (row < half) == aIsUp {
                let ac = col - down.0, ar = row - down.1
                if ac >= 0, ac < cols, ar >= 0, ar < rows, inside[ar * cols + ac], grid[ar * cols + ac] != 0 { continue }
            }
            let r = random()
            let (d1, d2) = r & 1 == 0 ? (left, right) : (right, left)
            if move(col, row, d1.0, d1.1) || move(col, row, d2.0, d2.1) { continue }
            if axial && r & 6 != 0 {
                // A grain on a slope a little shallower than 45° still slides.
                let (s1, s2) = r & 8 == 0 ? (side1, side2) : (side2, side1)
                if move(col, row, down.0 + 2 * s1.0, down.1 + 2 * s1.1, via: s1) { continue }
                _ = move(col, row, down.0 + 2 * s2.0, down.1 + 2 * s2.1, via: s2)
            }
        }
        budget = spend
        return moved
    }

    // MARK: Drawing

    private var maskCache: (version: Int, image: CGImage)?

    /// White where a grain is, clear elsewhere; row 0 is the A end.
    func mask() -> CGImage? {
        if let cache = maskCache, cache.version == version { return cache.image }
        let bytes = grid.map { $0 == 0 ? UInt8(0) : UInt8(255) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: cols,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        maskCache = (version, image)
        return image
    }
}
