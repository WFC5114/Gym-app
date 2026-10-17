import CoreGraphics
import SwiftUI

/// Where the prism and each face's three regions sit on screen.
///
/// Face-local coordinates have their origin at the face's top-left corner,
/// x to the right and y down, in points. The 3D scene and the SwiftUI type
/// layer both convert from these, so geometry and labels stay locked together.
struct MachineLayout: Equatable {
    var size: CGSize
    var safe: EdgeInsets

    static let reference = MachineLayout(
        size: CGSize(width: 440, height: 956),
        safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    )

    /// Black margin around the prism so it reads as an object, not a screen.
    var margin: CGFloat { 10 }
    var faceWidth: CGFloat { size.width - 2 * margin }
    var faceTop: CGFloat { safe.top + 4 }
    var faceHeight: CGFloat { max(size.height - safe.top - safe.bottom - 8, 200) }
    var faceSize: CGSize { CGSize(width: faceWidth, height: faceHeight) }
    var faceCenterY: CGFloat { faceTop + faceHeight / 2 }

    /// Distance from the prism axis to the middle of a face.
    var apothem: CGFloat { faceWidth / (2 * 3.0.squareRoot()) }

    /// Shared side alignment: about 6% of the viewport width (art direction §4).
    var side: CGFloat { (size.width * 0.06).rounded() }
    var contentWidth: CGFloat { faceWidth - 2 * side }

    /// Upper 30%: hero readout. Middle 50%: mechanism. Lower 20%: direct controls.
    var heroRect: CGRect { CGRect(x: side, y: 0, width: contentWidth, height: faceHeight * 0.30) }
    var mechanismRect: CGRect { CGRect(x: side, y: faceHeight * 0.30, width: contentWidth, height: faceHeight * 0.50) }
    var controlsRect: CGRect { CGRect(x: side, y: faceHeight * 0.80, width: contentWidth, height: faceHeight * 0.20 - 12) }

    /// Width of the touch strip at each screen edge that always turns the prism.
    var edgeStrip: CGFloat { 22 }

    // MARK: Projection

    /// Screen x of face-local point `x` on face `index`, with the prism turned by `yaw` degrees.
    /// Orthographic: a face at angle φ is compressed by cos φ and shifted by apothem · sin φ.
    func screenX(faceLocalX x: CGFloat, faceAngle phi: Double) -> CGFloat {
        let r = phi * .pi / 180
        return size.width / 2 + apothem * sin(r) + (x - faceWidth / 2) * cos(r)
    }

    static func faceAngle(index: Int, yaw: Double) -> Double { Double(index) * 120 - yaw }
}

/// World units for RealityKit: 1 unit = 100 pt.
enum World {
    static let unitsPerPoint: Float = 0.01

    static func len(_ points: CGFloat) -> Float { Float(points) * unitsPerPoint }

    /// Face-local point (top-left origin, y down) to the face entity's local space
    /// (centre origin, y up). `z` is height above the face surface in points.
    static func point(_ p: CGPoint, z: CGFloat = 0, in layout: MachineLayout) -> SIMD3<Float> {
        SIMD3(len(p.x - layout.faceWidth / 2), len(layout.faceHeight / 2 - p.y), len(z))
    }
}
