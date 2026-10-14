import SwiftUI
import UIKit

/// Type for the machine. Display numerals use Unbounded Black (SIL OFL 1.1,
/// bundled in App/Fonts with its licence); if it fails to load, SF Pro Black
/// Expanded is the fallback. Labels use SF Mono for stable alignment.
enum TypeKit {
    static let displayName = "Unbounded-Black"
    /// Tight tracking for hero numerals, in ems.
    static let heroTracking: CGFloat = -0.045

    static func displayUIFont(_ size: CGFloat) -> UIFont {
        UIFont(name: displayName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .black, width: .expanded)
    }

    static var usesBundledDisplayFont: Bool { UIFont(name: displayName, size: 12) != nil }

    static func display(_ size: CGFloat) -> Font { Font(displayUIFont(size)) }

    /// Small type. Clay skins set it in the system sans with tabular digits
    /// (mature, quieter than a typewriter); the others in SF Mono.
    static func label(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if Brutal.skin.clayUI { return Font.system(size: size, weight: weight).monospacedDigit() }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// Letter spacing for small type: the sans needs about half the mono's.
    static func tracking(_ mono: CGFloat) -> CGFloat {
        Brutal.skin.clayUI ? mono * 0.55 : mono
    }

    /// Measures the shaped width of a string at a size, including tracking.
    static func width(of text: String, size: CGFloat, tracking: CGFloat = heroTracking) -> CGFloat {
        let font = displayUIFont(size)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking * size])
        return ceil(attributed.size().width)
    }

    /// Hero size: the reference string spans `fraction` of the screen width,
    /// then the actual value shrinks only if it would overflow `maxWidth`.
    /// Never below `minimum`; never horizontally distorted.
    static func heroSize(for text: String, reference: String = "8,888", screenWidth: CGFloat,
                         fraction: CGFloat, maxWidth: CGFloat, minimum: CGFloat = 40) -> CGFloat {
        let unit = max(width(of: reference, size: 100), 1) / 100
        var size = screenWidth * fraction / unit
        let actual = width(of: text, size: size)
        if actual > maxWidth { size *= maxWidth / actual }
        return max(size, minimum)
    }
}

/// Engraved label used everywhere on the faces.
/// Small type on the faces. On black, dim labels step back by opacity; on the
/// colour plates a dim white sinks into the colour (0.45 white on DIET orange
/// was about 1.8:1), so every label keeps at least 0.88 there and the hierarchy
/// comes from size and weight instead.
enum Ink {
    /// Vivid colour plates; the graphite clay tray lets dim labels step back.
    static var onColour: Bool { Brutal.skin.faceColors != nil && !Brutal.skin.clayUI }

    static func text(_ opacity: Double) -> Color {
        Color(hex: Brutal.skin.inkHex).opacity(onColour ? max(opacity, 0.88) : max(opacity, Brutal.skin.clayUI ? 0.5 : 0))
    }
}

struct Engraved: View {
    var text: String
    var size: CGFloat = 10.5
    var color: Color = Ink.text(0.62)
    var tracking: CGFloat = 1.6
    @Environment(\.labelScale) private var scale

    var body: some View {
        Text(text)
            .font(TypeKit.label(size * scale))
            .tracking(TypeKit.tracking(tracking))
            .foregroundStyle(color)
            // A one-point engraved shadow: invisible on black, keeps small type
            // legible on the colour plates, and on clay lifts it like raised lettering.
            .shadow(color: .black.opacity(Brutal.skin.clayUI ? 0.6 : Ink.onColour ? 0.45 : 0.35),
                    radius: Brutal.skin.clayUI ? 0.6 : 0, x: 0, y: 1)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct LabelScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Dynamic Type multiplier for machine labels, capped so the instrument keeps its layout.
    var labelScale: CGFloat {
        get { self[LabelScaleKey.self] }
        set { self[LabelScaleKey.self] = newValue }
    }
}

extension DynamicTypeSize {
    var labelScale: CGFloat {
        switch self {
        case .xSmall, .small, .medium: return 0.95
        case .large: return 1
        case .xLarge: return 1.08
        case .xxLarge: return 1.16
        case .xxxLarge: return 1.24
        default: return 1.4
        }
    }
}
