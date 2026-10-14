import RealityKit
import SwiftUI

/// Claymorphic chrome (skins with `clayUI`, Wei 14 Oct 2026): keys and gauges
/// on the faces are lit clay and glass objects in the scene, like the hero
/// numerals. SwiftUI keeps the layout, the label, taps and VoiceOver, and
/// reports where each part sits on its face. Off the faces (the intake inset)
/// keys are drawn as clay in SwiftUI.
struct ClayPart: Equatable {
    enum Kind: Equatable {
        /// Primary keys are ivory clay, secondary keys smoked glass.
        case key(primary: Bool)
        /// A glass tube with a clay fill, `fill` 0...1.
        case gauge(GaugeTint, fill: Double)
        /// A low raised clay plate that groups a control or a note.
        case panel
        /// A small terracotta slider riding a scale.
        case knob

        func sameShape(as other: Kind) -> Bool {
            switch (self, other) {
            case let (.key(a), .key(b)): return a == b
            case let (.gauge(a, _), .gauge(b, _)): return a == b
            case (.panel, .panel), (.knob, .knob): return true
            default: return false
            }
        }
    }

    var face: PrismFace
    var kind: Kind
    /// Face-local points.
    var frame: CGRect
    var enabled = true
}

enum GaugeTint: Int {
    case protein, carbs, fat
}

/// Which face a view is printed on, so its parts can be built on that face.
struct ClayHost {
    let model: MachineModel
    let face: PrismFace
}

extension EnvironmentValues {
    @Entry var clayHost: ClayHost? = nil
}

/// Reports a view's frame and kind to the scene while it is on screen.
struct ClayPartReporter: ViewModifier {
    /// Nothing is reported without an id.
    let id: String?
    let kind: ClayPart.Kind
    var enabled = true
    @Environment(\.clayHost) private var host

    @ViewBuilder
    func body(content: Content) -> some View {
        if let host, let id, Brutal.skin.clayUI, !RenderedArt.on(host.face) {
            content
                .background(GeometryReader { geo in
                    let frame = geo.frame(in: .named(host.face.space))
                    Color.clear
                        .onAppear { report(host, id, frame) }
                        .onChange(of: frame) { _, new in report(host, id, new) }
                        .onChange(of: kind) { _, _ in report(host, id, frame) }
                        .onChange(of: enabled) { _, _ in report(host, id, frame) }
                })
                .onDisappear { host.model.clayParts[id] = nil }
        } else {
            content
        }
    }

    private func report(_ host: ClayHost, _ id: String, _ frame: CGRect) {
        let part = ClayPart(face: host.face, kind: kind, frame: frame, enabled: enabled)
        if host.model.clayParts[id] != part { host.model.clayParts[id] = part }
    }
}

/// The two button weights on the machine. With a clay skin on a face, a key
/// given a `part` id is a lit 3D object under its label; elsewhere it is drawn.
struct MachineButtonStyle: ButtonStyle {
    var primary = false
    var part: String? = nil

    func makeBody(configuration: Configuration) -> some View {
        MachineKey(configuration: configuration, primary: primary, part: part)
    }
}

struct MachineKey: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let part: String?
    @Environment(\.clayHost) private var host
    @Environment(\.labelScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let clay = Brutal.skin.clayUI
        // Rendered faces place their own rendered keys; other faces build lit 3D keys.
        let inScene = clay && host != nil && part != nil && !(host.map { RenderedArt.on($0.face) } ?? false)
        let pressed = configuration.isPressed
        configuration.label
            .font(TypeKit.label(13 * min(scale, 1.25), weight: .heavy))
            .tracking(clay ? 1.1 : 1.4)
            .foregroundStyle(textColor(clay))
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .background {
                if inScene {
                    Color.clear
                } else if clay {
                    ClayPill(primary: primary, pressed: pressed)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(primary ? Color(white: 0.92) : Color(white: 0.11))
                }
            }
            // In the scene the key itself sinks; the label only gives a little.
            .offset(y: pressed ? (inScene ? 1 : 2) : 0)
            .scaleEffect(pressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.interpolatingSpring(mass: 1, stiffness: 800, damping: 35), value: pressed)
            .modifier(ClayPartReporter(id: part, kind: .key(primary: primary), enabled: isEnabled))
            .onChange(of: pressed) { _, down in
                if inScene, let part { host?.model.pressKey(part, down: down) }
            }
    }

    private func textColor(_ clay: Bool) -> Color {
        if clay { return primary ? Color(hex: 0x221F24) : Ink.text(0.92) }
        return primary ? .black : .white
    }
}

/// A clay key drawn in SwiftUI, for controls that are not on a face: lit from
/// above, rolled edges, a soft shadow it lifts off.
struct ClayPill: View {
    var primary: Bool
    var pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let top = primary ? Color(hex: 0xF7F1E7) : Color(hex: 0x3A3640)
        let bottom = primary ? Color(hex: 0xD6CBBA) : Color(hex: 0x1C1A20)
        shape
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.inset(by: 1).stroke(
                    LinearGradient(colors: [.white.opacity(primary ? 0.75 : 0.22), .clear, .black.opacity(0.28)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(pressed ? 0.35 : 0.55), radius: pressed ? 2 : 7, x: 0, y: pressed ? 1 : 5)
    }
}

/// A macro gauge: a glass tube with a clay fill on clay faces, a flat bar elsewhere.
struct MacroGauge: View {
    let id: String
    let tint: GaugeTint
    let fill: Double
    @Environment(\.clayHost) private var host

    var body: some View {
        let f = min(max(fill, 0), 1)
        Group {
            if host != nil && Brutal.skin.clayUI {
                Color.clear
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.text(0.18))
                        Capsule().fill(Ink.text(0.9)).frame(width: max(geo.size.height, geo.size.width * f))
                    }
                }
            }
        }
        .frame(height: 12)
        .modifier(ClayPartReporter(id: id, kind: .gauge(tint, fill: f)))
        .accessibilityHidden(true)
    }
}

/// Builds and places the scene objects for every reported part.
@MainActor
final class ClayPartsRig {
    private struct Built {
        let entity: ModelEntity
        let kind: ClayPart.Kind
        let size: CGSize
        let face: PrismFace
        var fill: ModelEntity?
        var fillWidth: CGFloat = -1
    }

    private var built: [String: Built] = [:]

    /// Key depth and how far a press sinks it, in points.
    static let keyDepth: CGFloat = 14
    static let keyTravel: CGFloat = 5

    func apply(_ model: MachineModel, faces: [Entity], layout: MachineLayout, chrome: ChromeKit, surface: CGFloat) {
        let parts = model.clayParts
        for (id, b) in built where parts[id] == nil {
            b.entity.removeFromParent()
            built[id] = nil
        }
        for (id, part) in parts {
            let size = CGSize(width: part.frame.width.rounded(), height: part.frame.height.rounded())
            guard size.width >= 6, size.height >= 6, part.face.rawValue < faces.count else { continue }
            if let b = built[id], b.size != size || b.face != part.face || !b.kind.sameShape(as: part.kind) {
                b.entity.removeFromParent()
                built[id] = nil
            }
            if built[id] == nil, let b = build(part, size: size, chrome: chrome) {
                faces[part.face.rawValue].addChild(b.entity)
                built[id] = b
            }
            guard var b = built[id] else { continue }
            let center = CGPoint(x: part.frame.midX, y: part.frame.midY)
            switch part.kind {
            case .key:
                let press = CGFloat(model.keyPress[id]?.position ?? 0)
                b.entity.position = World.point(center, z: surface - 2 - press * Self.keyTravel, in: layout)
                b.entity.components.set(OpacityComponent(opacity: part.enabled ? 1 : 0.45))
            case .panel:
                b.entity.position = World.point(center, z: surface - 1, in: layout)
            case .knob:
                b.entity.position = World.point(center, z: surface + 1, in: layout)
            case .gauge(let tint, let fill):
                b.entity.position = World.point(center, z: surface + 0.5, in: layout)
                let inset: CGFloat = 2.5
                let inner = size.height - 2 * inset
                let width = max(inner, ((size.width - 2 * inset) * CGFloat(fill)).rounded())
                if abs(width - b.fillWidth) >= 1 {
                    b.fill?.removeFromParent()
                    b.fill = nil
                    if fill > 0.005, let mesh = try? Geometry.slab(halfWidth: World.len(width / 2), halfHeight: World.len(inner / 2),
                                                                  depth: World.len(inner), corner: World.len(inner / 2),
                                                                  bevel: World.len(inner / 2), name: "gaugeFill") {
                        let e = ModelEntity(mesh: mesh, materials: [chrome.fills[min(tint.rawValue, chrome.fills.count - 1)]])
                        e.position = SIMD3(World.len(-size.width / 2 + inset + width / 2), 0, World.len(inset))
                        b.entity.addChild(e)
                        b.fill = e
                    }
                    b.fillWidth = width
                    built[id] = b
                }
            }
        }
    }

    private func build(_ part: ClayPart, size: CGSize, chrome: ChromeKit) -> Built? {
        let hw = World.len(size.width / 2), hh = World.len(size.height / 2)
        switch part.kind {
        case .key(let primary):
            guard let mesh = try? Geometry.slab(halfWidth: hw, halfHeight: hh, depth: World.len(Self.keyDepth),
                                                corner: World.len(min(13, size.height / 2)), bevel: World.len(6),
                                                puff: World.len(2.5), name: "key") else { return nil }
            return Built(entity: ModelEntity(mesh: mesh, materials: [primary ? chrome.primary : chrome.secondary]),
                         kind: part.kind, size: size, face: part.face)
        case .panel:
            guard let mesh = try? Geometry.slab(halfWidth: hw, halfHeight: hh, depth: World.len(5), corner: World.len(min(14, size.height / 2)),
                                                bevel: World.len(2.5), puff: World.len(0.6), name: "panel") else { return nil }
            return Built(entity: ModelEntity(mesh: mesh, materials: [chrome.panel]), kind: part.kind, size: size, face: part.face)
        case .knob:
            guard let mesh = try? Geometry.slab(halfWidth: hw, halfHeight: hh, depth: World.len(9), corner: World.len(min(5, size.width / 2)),
                                                bevel: World.len(3.5), puff: World.len(1.5), name: "knob") else { return nil }
            return Built(entity: ModelEntity(mesh: mesh, materials: [chrome.knob]), kind: part.kind, size: size, face: part.face)
        case .gauge:
            guard let mesh = try? Geometry.slab(halfWidth: hw, halfHeight: hh, depth: World.len(size.height),
                                                corner: hh, bevel: hh, name: "gauge") else { return nil }
            return Built(entity: ModelEntity(mesh: mesh, materials: [chrome.tube]), kind: part.kind, size: size, face: part.face)
        }
    }
}

extension View {
    /// Builds a clay object of `kind` under this view on clay faces; elsewhere nothing changes.
    func clayPart(_ id: String, _ kind: ClayPart.Kind) -> some View {
        modifier(ClayPartReporter(id: id, kind: kind))
    }
}
