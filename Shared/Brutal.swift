import SwiftUI

/// A swappable visual skin. The default is strictly monochrome; colour arrives
/// only through skins that are unlocked by streaks and milestones.
struct Skin: Identifiable, Equatable {
    let id: String
    let name: String
    let paper: Color
    let ink: Color
    /// The highlight colour for progress and rewards. Grey in the monochrome skin.
    let signal: Color
    let muted: Color
    /// What unlocks the skin, or nil when it is available from the start.
    let unlock: String?

    static let mono = Skin(
        id: "mono", name: "Mono",
        paper: Color(white: 0.96), ink: Color(white: 0.04),
        signal: Color(white: 0.55), muted: Color(white: 0.45),
        unlock: nil
    )
    static let concrete = Skin(
        id: "concrete", name: "Concrete",
        paper: Color(white: 0.78), ink: Color(white: 0.10),
        signal: Color(white: 0.98), muted: Color(white: 0.38),
        unlock: "7-day logging streak"
    )
    static let signalOrange = Skin(
        id: "signal", name: "Signal",
        paper: Color(red: 0.949, green: 0.941, blue: 0.910), ink: Color(white: 0.04),
        signal: Color(red: 1.0, green: 0.271, blue: 0.0), muted: Color(white: 0.45),
        unlock: "Hit protein 14 days in a row"
    )
    static let all: [Skin] = [.mono, .concrete, .signalOrange]
}

/// The GYM design system. See docs/DESIGN_LANGUAGE.md: software as a toy,
/// monochrome canvas, oversized type, 3D slabs, spring physics.
enum Brutal {
    static var skin: Skin = .mono

    static var paper: Color { skin.paper }
    static var ink: Color { skin.ink }
    static var signal: Color { skin.signal }
    static var muted: Color { skin.muted }

    static let border: CGFloat = 3
    /// Visible thickness of a slab: the side face drawn below and right of it.
    static let shadowOffset: CGFloat = 6
    static let grid: CGFloat = 8

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).width(.condensed)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Damped harmonic springs. Every animation in the app uses one of these.
    static let snap = Animation.interpolatingSpring(mass: 1, stiffness: 320, damping: 18)
    static let settle = Animation.interpolatingSpring(mass: 1.4, stiffness: 160, damping: 20)
    static let heavy = Animation.interpolatingSpring(mass: 3, stiffness: 260, damping: 26)
}

struct BrutalCard: ViewModifier {
    var fill: Color = Brutal.paper

    func body(content: Content) -> some View {
        content
            .padding(Brutal.grid * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(Rectangle().stroke(Brutal.ink, lineWidth: Brutal.border))
            .background(
                Rectangle()
                    .fill(Brutal.ink)
                    .offset(x: Brutal.shadowOffset, y: Brutal.shadowOffset)
            )
    }
}

extension View {
    func brutalCard(fill: Color = Brutal.paper) -> some View {
        modifier(BrutalCard(fill: fill))
    }
}
