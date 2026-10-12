import RealityKit
import SwiftUI

/// The whole app: one prism. RealityKit draws the geometry; the SwiftUI type
/// layer for each face is projected with the same orthographic maths, so text
/// and controls stay printed on their face while it turns.
struct MachineView: View {
    let model: MachineModel
    @State private var scene = MachineScene()
    @State private var isReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let layout = MachineLayout(size: geo.size, safe: geo.safeAreaInsets)
            ZStack(alignment: .topLeading) {
                Color.black
                RealityView { content in
                    await scene.make(content: &content, model: model)
                    isReady = true
                }
                .accessibilityHidden(true)

                ZStack(alignment: .topLeading) {
                    ForEach(PrismFace.allCases, id: \.rawValue) { face in
                        FaceLayer(model: model, face: face, layout: layout)
                    }
                }
                .offset(x: CGFloat(model.shake.position) * 0.6, y: CGFloat(model.shake.position))

                EdgeStrips(model: model, layout: layout)

                if isReady && (model.fixtureName == nil || model.posed) {
                    Color.clear
                        .frame(width: 2, height: 2)
                        .accessibilityElement()
                        .accessibilityLabel("Machine ready")
                        .accessibilityIdentifier("machine.ready")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { configure(layout) }
            .task {
                // Fixture poses depend on the final layout, so they wait for it to settle.
                guard let name = model.fixtureName, !model.posed else { return }
                try? await Task.sleep(for: .milliseconds(400))
                Fixtures.pose(model, fixture: name)
                model.posed = true
            }
            .onChange(of: layout) { _, new in configure(new) }
            .onChange(of: reduceMotion) { _, new in model.reduceMotion = new }
            .onChange(of: scenePhase) { _, phase in
                // A rest that ran out while suspended is closed at its true end time.
                guard phase == .active, !model.isFixture else { return }
                model.store.settleElapsedRests(now: model.now())
                model.wake()
            }
        }
        .ignoresSafeArea(.container)
        .ignoresSafeArea(.keyboard)
        .overlay {
            InsetLayer(model: model)
        }
        .environment(\.labelScale, dynamicTypeSize.labelScale)
        .preferredColorScheme(.dark)
    }

    private func configure(_ layout: MachineLayout) {
        model.layout = layout
        model.reduceMotion = reduceMotion
        if !model.isFixture { model.syncGlassImmediately() }
        model.wake()
    }
}

/// One face's type and controls, projected onto the turning prism.
struct FaceLayer: View {
    let model: MachineModel
    let face: PrismFace
    let layout: MachineLayout

    var body: some View {
        let phi = MachineLayout.faceAngle(index: face.rawValue, yaw: model.yaw.position)
        let wrapped = (phi + 540).truncatingRemainder(dividingBy: 360) - 180
        let radians = wrapped * .pi / 180
        let facing = cos(radians)
        let isFront = abs(wrapped) < 0.75 && !model.isRotating
        Group {
            if facing > 0.02 {
                content
                    .frame(width: layout.faceWidth, height: layout.faceHeight, alignment: .topLeading)
                    .coordinateSpace(name: "face")
                    // Text is printed on the face, so it darkens as the face turns from the light.
                    .opacity(0.35 + 0.65 * facing)
                    .rotation3DEffect(.degrees(wrapped), axis: (x: 0, y: 1, z: 0), perspective: 0)
                    .position(x: layout.size.width / 2 + layout.apothem * CGFloat(sin(radians)), y: layout.faceCenterY)
                    .allowsHitTesting(isFront && model.inset == .closed)
                    .accessibilityHidden(!isFront)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch face {
        case .diet: DietFace(model: model, layout: layout)
        case .train: TrainFace(model: model, layout: layout)
        case .body: BodyFace(model: model, layout: layout)
        }
    }
}

/// Strips at both screen edges that always turn the prism, even over controls.
struct EdgeStrips: View {
    let model: MachineModel
    let layout: MachineLayout

    var body: some View {
        HStack(spacing: 0) {
            strip
            Spacer(minLength: 0)
            strip
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(model.inset == .closed)
    }

    private var strip: some View {
        Color.clear
            .frame(width: layout.edgeStrip)
            .contentShape(Rectangle())
            .gesture(rotateGesture)
            .accessibilityHidden(true)
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if !model.isRotating { model.beginRotate(screenX: value.startLocation.x, time: CACurrentMediaTime()) }
                model.updateRotate(screenX: value.location.x, time: CACurrentMediaTime())
            }
            .onEnded { _ in model.endRotate(time: CACurrentMediaTime()) }
    }
}

/// Swipes that start on an empty part of a face also turn the prism, but only
/// when they are clearly horizontal; vertical drags stay with the face.
struct FaceSwipe: ViewModifier {
    let model: MachineModel

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onChanged { value in
                    let dx = value.translation.width, dy = value.translation.height
                    if !model.isRotating {
                        guard abs(dx) > abs(dy) * 1.4 else { return }
                        model.beginRotate(screenX: value.location.x - dx, time: CACurrentMediaTime())
                    }
                    model.updateRotate(screenX: value.location.x, time: CACurrentMediaTime())
                }
                .onEnded { _ in model.endRotate(time: CACurrentMediaTime()) }
        )
    }
}

/// Top row shared by the three faces: face letter and the turn controls.
struct FaceHeader: View {
    let model: MachineModel
    let layout: MachineLayout
    let face: PrismFace
    let caption: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Engraved(text: face.letter + " · " + face.title, size: 11, color: .white.opacity(0.85))
                Engraved(text: caption, size: 9, color: .white.opacity(0.4))
            }
            Spacer(minLength: 4)
            Button { model.rotate(by: -1) } label: {
                Engraved(text: "‹ " + face.previous().title, size: 10.5, color: .white.opacity(0.7))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Turn to \(face.previous().title.lowercased())")
            .accessibilityIdentifier("face.previous")
            Button { model.rotate(by: 1) } label: {
                Engraved(text: face.next().title + " ›", size: 10.5, color: .white.opacity(0.7))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Turn to \(face.next().title.lowercased())")
            .accessibilityIdentifier("face.next")
        }
        .padding(.horizontal, layout.side)
        .padding(.top, 4)
        .frame(width: layout.faceWidth, alignment: .top)
    }
}

extension PrismFace {
    var title: String {
        switch self {
        case .diet: return "DIET"
        case .train: return "TRAIN"
        case .body: return "BODY"
        }
    }

    var letter: String {
        switch self {
        case .diet: return "A"
        case .train: return "B"
        case .body: return "C"
        }
    }
}
