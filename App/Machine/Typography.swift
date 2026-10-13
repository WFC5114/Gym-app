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

    static func label(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

/// Engraved monospaced label used everywhere on the faces.
struct Engraved: View {
    var text: String
    var size: CGFloat = 10.5
    var color: Color = .white.opacity(0.62)
    var tracking: CGFloat = 1.6
    @Environment(\.labelScale) private var scale

    var body: some View {
        Text(text)
            .font(TypeKit.label(size * scale))
            .tracking(tracking)
            .foregroundStyle(color)
            // A one-point engraved shadow: invisible on black, keeps small type
            // legible on the colour plates.
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
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

/// The two button weights on the machine: primary (white slab) and secondary (graphite).
struct MachineButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.labelScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeKit.label(13 * min(scale, 1.25), weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(primary ? Color(white: 0.92) : Color(white: 0.11))
            )
            .offset(y: configuration.isPressed ? 2 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.interpolatingSpring(mass: 1, stiffness: 800, damping: 35), value: configuration.isPressed)
    }
}
