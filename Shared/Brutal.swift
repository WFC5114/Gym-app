import SwiftUI

/// A skin is a full configuration of the machine: palette, surface material,
/// physics feel and sound kit. See docs/DESIGN_LANGUAGE.md, section 5.
struct Skin: Identifiable, Equatable {
    let id: String
    let name: String
    let base: Color
    let accent: Color
    let mid: Color
    /// PBR surface: roughness and metalness for the RealityKit material.
    let roughness: Double
    let metalness: Double
    let soundKit: String
    /// What unlocks the skin, or nil when it is available from the start.
    let unlock: String?
    /// Inlaid colour plate per face (DIET, TRAIN, BODY); nil keeps the bare chassis.
    var faceColors: [UInt32]? = nil
    /// Hero numerals, weights and slabs.
    var objectColor: UInt32 = 0xEDEDED
    /// Satin and clearcoat on objects instead of matte graphite.
    var glossy = false
    /// Claymorphic chrome: keys and gauges are lit clay and glass objects on a
    /// thick clay tray, labels are set in a sans, and dim labels may step back.
    var clayUI = false
    /// Colour of type on the faces.
    var inkHex: UInt32 = 0xFFFFFF

    static let mono = Skin(
        id: "mono", name: "MONO",
        base: Color(hex: 0x000000), accent: Color(hex: 0xFFFFFF), mid: Color(hex: 0x333333),
        roughness: 0.9, metalness: 0.0, soundKit: "Anvil",
        unlock: nil
    )
    static let concrete = Skin(
        id: "concrete", name: "CONCRETE",
        base: Color(hex: 0x4A4A4A), accent: Color(hex: 0xF5F5F7), mid: Color(hex: 0x8E8E93),
        roughness: 0.95, metalness: 0.0, soundKit: "Quarry",
        unlock: "7-day continuous logging streak"
    )
    static let signal = Skin(
        id: "signal", name: "SIGNAL",
        base: Color(hex: 0x0F0F11), accent: Color(hex: 0xFF3B30), mid: Color(hex: 0xFF9500),
        roughness: 0.15, metalness: 0.85, soundKit: "Synth-Volt",
        unlock: "100% protein target 14 days in a row"
    )
    /// Default (Wei, 13 Oct 2026): colour and light like a toy, each face its own
    /// colour so the prism reads at a glance while it turns. Objects are warm
    /// cream with satin clearcoat; white type stays readable on all three faces.
    static let flare = Skin(
        id: "flare", name: "FLARE",
        base: Color(hex: 0x000000), accent: Color(hex: 0xFFFFFF), mid: Color(hex: 0xFF5A1F),
        roughness: 0.55, metalness: 0.0, soundKit: "Anvil",
        unlock: nil,
        faceColors: [0xE8461E, 0x2340E0, 0x7B3FE4],
        objectColor: 0xFFF4E0,
        glossy: true
    )
    /// Default (Wei, 14 Oct 2026, picked "Night" of three whole-screen clay
    /// mockups, design/mockups/clay/screen.py): mature claymorphism. Graphite
    /// clay trays, ivory clay objects and numerals, clear glass, a terracotta accent.
    static let night = Skin(
        id: "night", name: "NIGHT",
        base: Color(hex: 0x000000), accent: Color(hex: 0xF1ECE4), mid: Color(hex: 0xD9774E),
        roughness: 0.55, metalness: 0.0, soundKit: "Anvil",
        unlock: nil,
        faceColors: [0x211F24, 0x211F24, 0x211F24],
        objectColor: 0xF1ECE4,
        glossy: true,
        clayUI: true,
        inkHex: 0xF1ECE4
    )
    static let all: [Skin] = [.night, .flare, .mono, .concrete, .signal]

    /// `-skin <id>` on launch picks a skin (fixtures and comparisons); otherwise NIGHT.
    static var launch: Skin {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-skin"), i + 1 < args.count, let skin = all.first(where: { $0.id == args[i + 1] }) {
            return skin
        }
        return .night
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The GYM design system for the Laboratory Measuring Deck.
enum Brutal {
    static var skin: Skin = .launch

    /// Background of the machine and the void around it.
    static var paper: Color { skin.base }
    /// Type and edges.
    static var ink: Color { skin.accent }
    /// Secondary surfaces and highlights.
    static var signal: Color { skin.mid }
    static var muted: Color { skin.mid }

    static let border: CGFloat = 3
    static let grid: CGFloat = 8

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).width(.expanded)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// SwiftUI fallbacks for flat UI. The 3D machine integrates `SpringState` per frame instead.
    static let snap = Animation.interpolatingSpring(mass: SpringConfig.piston.mass, stiffness: SpringConfig.piston.stiffness, damping: SpringConfig.piston.damping)
    static let settle = Animation.interpolatingSpring(mass: SpringConfig.bodyNumbers.mass, stiffness: SpringConfig.bodyNumbers.stiffness, damping: SpringConfig.bodyNumbers.damping)
    static let heavy = Animation.interpolatingSpring(mass: SpringConfig.jar.mass, stiffness: SpringConfig.jar.stiffness, damping: SpringConfig.jar.damping)
}
