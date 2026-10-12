import SwiftUI

/// The GYM design system: paper, ink and one signal colour, monospaced heavy type,
/// hard borders and hard offset shadows. No gradients, no soft shadows.
enum Brutal {
    static let paper = Color(red: 0.949, green: 0.941, blue: 0.910)
    static let ink = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let signal = Color(red: 1.0, green: 0.271, blue: 0.0)
    static let muted = Color(red: 0.45, green: 0.45, blue: 0.43)

    static let border: CGFloat = 3
    static let shadowOffset: CGFloat = 6
    static let grid: CGFloat = 8

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .monospaced)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Springs used across the app so motion feels consistent.
    static let snap = Animation.spring(response: 0.35, dampingFraction: 0.72)
    static let settle = Animation.spring(response: 0.6, dampingFraction: 0.85)
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
