import RealityKit
import SwiftUI

/// The RealityKit side of the machine: one prism, its three mechanisms, the
/// orthographic camera and the lights. `apply` copies the model's current
/// presentation state onto entities every rendered frame.
@MainActor
final class MachineScene {
    let root = Entity()
    let prismRoot = Entity()
    /// Holds the studio image-based light every mechanism on the prism receives.
    private let studioLight = Entity()
    let camera = Entity()
    var faces: [Entity] = []
    var materials = MaterialKit.make(skin: Brutal.skin, grain: nil)
    private var builtLayout: MachineLayout?
    private var prismModel: ModelEntity?
    private var subscription: EventSubscription?

    // DIET
    private let dietGroup = Entity()
    /// The jar and everything in it bob together.
    private let jarGroup = Entity()
    private var railBlocks: [Int: ModelEntity] = [:]
    private var railBase: ModelEntity?
    private var blockEntities: [UUID: ModelEntity] = [:]
    private var pendingEntity: ModelEntity?
    private var pendingKey: UUID?
    private var pieceEntities: [UUID: (entity: ModelEntity, size: CGSize, tint: FoodTint)] = [:]

    private var numerals: [PrismFace: Numerals3D] = [:]
    private var facePlates: [ModelEntity] = []

    // TRAIN
    private let glassGroup = Entity()
    private let glassSpin = Entity()
    /// Sand in the glass-local top (A) and bottom (B) bulbs. Each shows either the
    /// draining shape or the pile, from meshes made once per step of sand.
    private var sandA = ModelEntity()
    private var sandB = ModelEntity()
    private var drainMeshes: [MeshResource] = []
    private var heapMeshes: [MeshResource] = []
    private var sandShown: [Int] = [-1, -1]
    private var stream: ModelEntity?
    /// Sand drawn in this many steps; at a 3:00 rest that is one step every 3.75 s.
    static let sandSteps = 48

    // BODY: the figurine stands on a turntable; its root sits at the feet.
    private let figureRoot = Entity()
    private let figureTurn = Entity()
    /// `FigureShape.parts` in order, each built at the neutral shape's size and
    /// scaled to the current one.
    private var figureParts: [(entity: ModelEntity, base: SIMD3<Float>)] = []

    /// Depths above the face surface, in points.
    enum Depth {
        static let block: CGFloat = 40
        static let lift: CGFloat = 46
        /// The jar is deep enough for a block with room either side.
        static let jar: CGFloat = 84
        /// Blocks in the jar sit at its middle depth.
        static var inJar: CGFloat { jar / 2 + 2 }
    }

    func make(content: inout RealityViewCameraContent, model: MachineModel) async {
        content.camera = .virtual
        var woodGrain: TextureResource?
        if let woodImage = MaterialKit.woodImage() {
            woodGrain = try? await TextureResource(image: woodImage, withName: "walnut",
                                                   options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        }
        if let grainImage = MaterialKit.grainImage(),
           let grain = try? await TextureResource(image: grainImage, withName: "grain",
                                                   options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll)) {
            materials = MaterialKit.make(skin: Brutal.skin, grain: grain, woodGrain: woodGrain)
        } else {
            materials = MaterialKit.make(skin: Brutal.skin, grain: nil, woodGrain: woodGrain)
        }
        if let envImage = MaterialKit.environmentImage(),
           let env = try? await EnvironmentResource(equirectangular: envImage, withName: "studio") {
            content.environment = .skybox(env)
        }
        // Reflections come from the studio the Blender mockups are lit by
        // (design/assets/studio_env.py). It lights the prism only; the skybox
        // above stays black where the orthographic camera looks, so the void stays #000.
        if let studio = MaterialKit.studioImage(),
           let env = try? await EnvironmentResource(equirectangular: studio, withName: "studio-softboxes") {
            studioLight.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.3))
            root.addChild(studioLight)
            prismRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studioLight))
        }

        var ortho = OrthographicCameraComponent()
        ortho.near = 0.1
        ortho.far = 80
        ortho.scaleDirection = .vertical
        camera.components.set(ortho)
        root.addChild(camera)

        // Key light from the upper left, in front: planes separate by tone and
        // mechanisms drop soft contact shadows onto the face.
        let key = Entity()
        var keyLight = DirectionalLightComponent(color: .white, intensity: 5200)
        keyLight.isRealWorldProxy = false
        key.components.set(keyLight)
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 2))
        key.look(at: .zero, from: SIMD3(-2.4, 3.4, 5.0), relativeTo: nil)
        root.addChild(key)

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(color: .white, intensity: 1100))
        fill.look(at: .zero, from: SIMD3(3.5, -1.0, 4.0), relativeTo: nil)
        root.addChild(fill)

        root.addChild(prismRoot)
        for i in 0..<3 {
            let face = Entity()
            prismRoot.addChild(face)
            faces.append(face)
        }
        faces[0].addChild(dietGroup)
        faces[1].addChild(glassGroup)
        glassGroup.addChild(glassSpin)
        content.add(root)

        buildHourglass()
        rebuild(for: model.layout, model: model)

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self, weak model] _ in
            MainActor.assumeIsolated {
                guard let self, let model else { return }
                self.apply(model)
            }
        }
    }

    // MARK: Building

    private func rebuild(for layout: MachineLayout, model: MachineModel) {
        builtLayout = layout
        prismModel?.removeFromParent()
        if let mesh = try? Geometry.prism(side: World.len(layout.faceWidth), height: World.len(layout.faceHeight),
                                          chamfer: World.len(3), bevel: World.len(3)) {
            let entity = ModelEntity(mesh: mesh, materials: [materials.chassis])
            prismRoot.addChild(entity)
            prismModel = entity
        }
        let a = World.len(layout.apothem)
        for plate in facePlates { plate.removeFromParent() }
        facePlates = []
        for (i, face) in faces.enumerated() {
            let theta = Float(i) * 2 * .pi / 3
            face.position = SIMD3(a * sin(theta), 0, a * cos(theta))
            face.orientation = simd_quatf(angle: theta, axis: SIMD3(0, 1, 0))
            // The skin's colour inlay, set just proud of the chassis inside its bevel.
            if i < materials.facePlates.count {
                let inset: CGFloat = 7
                let plate = box(CGSize(width: layout.faceWidth - inset * 2, height: layout.faceHeight - inset * 2),
                                depth: 1.2, radius: 6, material: materials.facePlates[i])
                plate.position = World.point(CGPoint(x: layout.faceWidth / 2, y: layout.faceHeight / 2), z: 0.4, in: layout)
                face.addChild(plate)
                facePlates.append(plate)
            }
        }
        buildDiet(layout: layout, model: model)
        if numerals.isEmpty {
            for face in [PrismFace.diet, .train, .body] {
                let n = Numerals3D(material: materials.numeral)
                faces[face.rawValue].addChild(n.root)
                numerals[face] = n
            }
        }
        positionHourglass(layout: layout)
        buildBody(layout: layout)
    }

    private func box(_ size: CGSize, depth: CGFloat, radius: CGFloat, material: PhysicallyBasedMaterial) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: World.len(size.width), height: World.len(size.height),
                                            depth: World.len(depth), cornerRadius: World.len(radius))
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func buildDiet(layout: MachineLayout, model: MachineModel) {
        for child in Array(dietGroup.children) { child.removeFromParent() }
        for child in Array(jarGroup.children) { child.removeFromParent() }
        railBlocks = [:]
        blockEntities = [:]
        pieceEntities = [:]
        pendingEntity = nil
        pendingKey = nil
        let g = model.jarGeometry
        let rail = model.rail
        dietGroup.addChild(jarGroup)

        // The jar: a deep glass body with a bright lip at the mouth. The type
        // layer adds the etched marks and the glass highlights on top.
        let glass = box(g.outer.size, depth: Depth.jar, radius: JarGeometry.cornerRadius, material: materials.glass)
        glass.position = World.point(CGPoint(x: g.outer.midX, y: g.outer.midY), z: Depth.jar / 2 + 2, in: layout)
        jarGroup.addChild(glass)
        let lip = box(CGSize(width: g.outer.width + 8, height: 9), depth: Depth.jar + 8, radius: 4, material: materials.spring)
        lip.position = World.point(CGPoint(x: g.outer.midX, y: g.outer.minY + 2), z: Depth.jar / 2 + 2, in: layout)
        jarGroup.addChild(lip)

        // The loading rail: a ledge under the quick-add blocks.
        let ledge = box(CGSize(width: rail.controls.width, height: 6), depth: 26, radius: 1.5, material: materials.plate)
        ledge.position = World.point(CGPoint(x: rail.controls.midX, y: rail.railLineY + 3), z: 13, in: layout)
        dietGroup.addChild(ledge)
        railBase = ledge

        for kcal in QuickAdd.weights {
            let size = rail.quickBlockSize(kcal: kcal)
            let block = box(size, depth: Depth.block, radius: 6, material: materials.food(.quick))
            block.position = World.point(rail.quickBlockHome(kcal: kcal), z: Depth.block / 2 + 6, in: layout)
            dietGroup.addChild(block)
            railBlocks[kcal] = block
        }
    }

    /// Chunky rounded food block.
    private func foodBlock(_ size: CGSize, tint: FoodTint) -> ModelEntity {
        box(size, depth: Depth.block, radius: min(10, size.height * 0.3, size.width * 0.3), material: materials.food(tint))
    }

    private func buildHourglass() {
        typealias H = DeskHourglass
        // Presentation turn on the group; SET DONE flips `glassSpin` about its own z.
        glassGroup.orientation = simd_quatf(angle: H.pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: H.yaw, axis: SIMD3(0, 1, 0))

        // Glass: an outer shell facing out and an inner shell facing in.
        let upper = H.profile
        let outer = upper.reversed().map { SIMD2(-$0.x, $0.y) } + upper.dropFirst()
        let inner = outer.map { SIMD2($0.x, max($0.y - H.wall, 0.004)) }
        if let outerMesh = try? Geometry.lathe(outer, segments: 72, name: "glassOuter"),
           let innerMesh = try? Geometry.lathe(Array(inner.reversed()), segments: 72, name: "glassInner") {
            glassSpin.addChild(ModelEntity(mesh: outerMesh, materials: [materials.clearGlass]))
            glassSpin.addChild(ModelEntity(mesh: innerMesh, materials: [materials.clearGlass]))
        }

        // Frame: collars and walnut plates at both ends, four posts with brass
        // sleeves, dome nuts on top and round feet underneath.
        for s: Float in [1, -1] {
            let collar = ModelEntity(mesh: .generateCylinder(height: H.collarHeight, radius: H.collarRadius), materials: [materials.blackMatte])
            collar.position = SIMD3(0, s * H.collarY, 0)
            glassSpin.addChild(collar)
            let plate = ModelEntity(mesh: .generateBox(width: H.plateSide, height: H.plateThickness, depth: H.plateSide,
                                                       cornerRadius: H.plateThickness * 0.22), materials: [materials.walnut])
            plate.position = SIMD3(0, s * H.plateY, 0)
            glassSpin.addChild(plate)
        }
        let post = MeshResource.generateCylinder(height: H.postLength, radius: H.postRadius)
        let sleeve = MeshResource.generateCylinder(height: H.sleeveHeight, radius: H.sleeveRadius)
        let nut = MeshResource.generateSphere(radius: H.nutRadius)
        for x: Float in [-H.postOffset, H.postOffset] {
            for z: Float in [-H.postOffset, H.postOffset] {
                let p = ModelEntity(mesh: post, materials: [materials.blackMatte])
                p.position = SIMD3(x, 0, z)
                glassSpin.addChild(p)
                for s: Float in [1, -1] {
                    let sl = ModelEntity(mesh: sleeve, materials: [materials.brass])
                    sl.position = SIMD3(x, s * H.sleeveY, z)
                    glassSpin.addChild(sl)
                    let n = ModelEntity(mesh: nut, materials: [materials.blackMatte])
                    n.position = SIMD3(x, s * H.nutY, z)
                    glassSpin.addChild(n)
                }
            }
        }

        // Sand: one mesh per step for each shape, made once.
        drainMeshes = (0...Self.sandSteps).compactMap {
            try? Geometry.lathe(H.drainProfile(Float($0) / Float(Self.sandSteps)), segments: 56, name: "drain\($0)")
        }
        heapMeshes = (0...Self.sandSteps).compactMap {
            try? Geometry.lathe(H.heapProfile(Float($0) / Float(Self.sandSteps)), segments: 56, name: "heap\($0)")
        }
        sandA.model = ModelComponent(mesh: drainMeshes.last ?? .generateSphere(radius: 0.01), materials: [materials.sand])
        sandB.model = ModelComponent(mesh: heapMeshes.first ?? .generateSphere(radius: 0.01), materials: [materials.sand])
        sandShown = [-1, -1]
        glassSpin.addChild(sandA)
        glassSpin.addChild(sandB)
        let stream = ModelEntity(mesh: .generateCylinder(height: 1, radius: 1), materials: [materials.sand])
        glassSpin.addChild(stream)
        self.stream = stream
    }

    private func positionHourglass(layout: MachineLayout) {
        let g = HourglassGeometry(layout: layout)
        glassGroup.position = World.point(g.center(forHeight: g.maxHeight), z: 60, in: layout)
    }

    private func buildBody(layout: MachineLayout) {
        if figureParts.isEmpty {
            faces[2].addChild(figureRoot)
            figureRoot.addChild(figureTurn)
            // Tipped toward the camera so the orthographic view sees its top.
            let disc = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.27), materials: [materials.plate])
            disc.orientation = simd_quatf(angle: 0.3, axis: SIMD3(1, 0, 0))
            disc.position = SIMD3(0, -0.025, 0)
            figureRoot.addChild(disc)
            for part in FigureShape.neutral.parts {
                let s = part.size
                let mesh: MeshResource
                var base = SIMD3<Float>(repeating: 1)
                switch part.kind {
                case .block(let rounding):
                    mesh = .generateBox(width: s.x, height: s.y, depth: s.z, cornerRadius: min(s.x, s.z) * rounding)
                    base = s
                case .ball:
                    mesh = .generateSphere(radius: 0.5)
                case .rod:
                    mesh = .generateCylinder(height: 1, radius: 0.5)
                }
                let e = ModelEntity(mesh: mesh, materials: [materials.weight])
                figureTurn.addChild(e)
                figureParts.append((e, base))
            }
        }
        let g = FigureGeometry(layout: layout)
        figureRoot.position = World.point(g.feet, z: FigureGeometry.depth, in: layout)
        figureRoot.scale = SIMD3(repeating: World.len(g.unit))
    }

    // MARK: Per frame

    func apply(_ model: MachineModel) {
        let layout = model.layout
        if layout != builtLayout { rebuild(for: layout, model: model) }

        // Camera: centred on the prism axis, level with the face centre.
        if var ortho = camera.components[OrthographicCameraComponent.self] {
            // `scale` is half the visible extent along `scaleDirection` (measured
            // from CI captures: a full-height value drew everything at 50%).
            let halfHeight = World.len(layout.size.height / 2)
            if ortho.scale != halfHeight {
                ortho.scale = halfHeight
                camera.components.set(ortho)
            }
        }
        let shake = World.len(CGFloat(model.shake.position))
        camera.position = SIMD3(-shake * 0.6, World.len(layout.faceCenterY - layout.size.height / 2) + shake, 20)

        prismRoot.orientation = simd_quatf(angle: Float(-model.yaw.position * .pi / 180), axis: SIMD3(0, 1, 0))
        // Mechanisms stand proud of their faces, so on the faces turned away they
        // would poke past the front face's silhouette. Fade them in as they turn toward the camera.
        for (i, face) in faces.enumerated() {
            let facing = cos(MachineLayout.faceAngle(index: i, yaw: model.yaw.position) * .pi / 180)
            let opacity = Float(min(max((facing + 0.25) / 0.25, 0), 1))
            face.isEnabled = opacity > 0.001
            face.components.set(OpacityComponent(opacity: opacity))
        }

        applyDiet(model, layout: layout)
        for (face, n) in numerals {
            let glyphs = model.heroGlyphs[face]
            n.root.isEnabled = model.heroIn3D && glyphs != nil
            guard model.heroIn3D, let glyphs else { continue }
            // DIET counts on its spring every frame; the others show their text as laid out.
            let text = face == .diet ? Readout.kcal(model.heroKcal.position.rounded()) : glyphs.text
            n.update(text: text, size: glyphs.size, frame: glyphs.frame,
                     punch: face == .diet ? model.heroPunch.position : 0, layout: layout)
        }
        applyTrain(model, layout: layout)
        applyBody(model, layout: layout)
    }

    private func applyDiet(_ model: MachineModel, layout: MachineLayout) {
        // The glass bobs with its load; pieces carry the bob in their own positions.
        jarGroup.position = SIMD3(0, -World.len(CGFloat(model.jarBob.position)), 0)

        // One block per logged food, in its place in the pile.
        var seen = Set<UUID>()
        for (index, piece) in model.jarPieces().enumerated() {
            seen.insert(piece.id)
            var slot = pieceEntities[piece.id]
            if slot == nil || abs(slot!.size.width - piece.size.width) > 0.5 || abs(slot!.size.height - piece.size.height) > 0.5 || slot!.tint != piece.tint {
                slot?.entity.removeFromParent()
                let entity = foodBlock(piece.size, tint: piece.tint)
                dietGroup.addChild(entity)
                slot = (entity, piece.size, piece.tint)
                pieceEntities[piece.id] = slot
            }
            guard let slot else { continue }
            // Neighbours sit at slightly different depths so touching corners never flicker.
            let z = Depth.inJar + CGFloat(index % 3 - 1) * 5
            slot.entity.position = World.point(piece.center, z: z, in: layout)
            slot.entity.orientation = simd_quatf(angle: Float(-piece.angle), axis: SIMD3(0, 0, 1))
        }
        for (id, slot) in pieceEntities where !seen.contains(id) {
            slot.entity.removeFromParent()
            pieceEntities[id] = nil
        }

        // Flying blocks.
        var flying = Set<UUID>()
        var busyQuick = Set<Int>()
        for block in model.blocks {
            flying.insert(block.id)
            if case .quick(let kcal) = block.kind { busyQuick.insert(kcal) }
            var entity = blockEntities[block.id]
            if entity == nil {
                let e = foodBlock(block.jarSize, tint: Self.tint(of: block))
                dietGroup.addChild(e)
                blockEntities[block.id] = e
                entity = e
            }
            let lift = CGFloat(block.lift.position)
            let drawn = block.drawnSize
            let inJar = block.phase == .falling || block.phase == .held
            let baseZ = inJar ? Depth.inJar : Depth.block / 2 + 6
            entity?.position = World.point(block.position, z: baseZ + lift * Depth.lift, in: layout)
            entity?.orientation = simd_quatf(angle: Float(-block.tilt.position), axis: SIMD3(0, 0, 1))
            let grow = Float(1 + 0.05 * lift)
            entity?.scale = SIMD3(Float(drawn.width / max(block.jarSize.width, 1)) * grow, Float(drawn.height / max(block.jarSize.height, 1)) * grow, grow)
        }
        for (id, entity) in blockEntities where !flying.contains(id) {
            entity.removeFromParent()
            blockEntities[id] = nil
        }
        for (kcal, entity) in railBlocks {
            entity.isEnabled = model.pending == nil && !busyQuick.contains(kcal)
        }

        // The formed food block resting on the rail.
        let pendingInFlight = model.blocks.contains { $0.entryID != nil && $0.entryID == model.pending?.entryID }
        if let pending = model.pending, !pendingInFlight {
            if pendingKey != pending.entryID {
                pendingEntity?.removeFromParent()
                let size = model.rail.foodBlockSize(kcal: pending.nutrients.kcal)
                let e = foodBlock(size, tint: FoodTint.of(pending.nutrients))
                dietGroup.addChild(e)
                pendingEntity = e
                pendingKey = pending.entryID
            }
            pendingEntity?.position = World.point(model.rail.foodBlockHome(kcal: pending.nutrients.kcal), z: Depth.block / 2 + 6, in: layout)
            pendingEntity?.isEnabled = true
        } else {
            pendingEntity?.isEnabled = false
            if model.pending == nil {
                pendingEntity?.removeFromParent()
                pendingEntity = nil
                pendingKey = nil
            }
        }
    }

    private static func tint(of block: FlyingBlock) -> FoodTint {
        switch block.kind {
        case .quick: return .quick
        case .food(let f): return FoodTint.of(f.nutrients)
        }
    }

    private func applyTrain(_ model: MachineModel, layout: MachineLayout) {
        let heightPoints = CGFloat(model.glassHeight.position)
        let height = World.len(heightPoints)
        glassGroup.scale = SIMD3(repeating: height)
        // Stand the glass proud of the face so its back half never enters the chassis.
        glassGroup.position = World.point(HourglassGeometry(layout: layout).center(forHeight: heightPoints), z: heightPoints * 0.42 + 8, in: layout)
        glassSpin.orientation = simd_quatf(angle: Float(model.glassAngle.position), axis: SIMD3(0, 0, 1))

        // Sand is drawn upright in the world: the world-top bulb shows the draining
        // shape, the world-bottom bulb the pile. After an odd number of flips the
        // spin is half a turn, so each bulb's shape is turned half a turn back.
        let amountA = Float(min(max(model.sandA.position, 0), 1))
        let amountB = Float(min(max(model.sandB.position, 0), 1))
        let aUp = model.aIsUp
        let turn = aUp ? simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)) : simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1))
        showSand(sandA, slot: 0, amount: amountA, draining: aUp, turn: turn)
        showSand(sandB, slot: 1, amount: amountB, draining: !aUp, turn: turn)

        // The falling stream, from the neck to the top of the pile.
        let topAmount = aUp ? amountA : amountB
        let bottomAmount = aUp ? amountB : amountA
        let flowing = model.activeRest != nil && topAmount > 0.002 && model.glassAngle.isSettled(tolerance: 0.02)
        stream?.isEnabled = flowing
        if flowing, let stream {
            let apex = DeskHourglass.heapApex(bottomAmount)  // world-upright, below the neck
            let length = max(abs(apex), 0.001)
            stream.scale = SIMD3(0.0035, length, 0.0035)
            stream.position = SIMD3(0, (aUp ? 1 : -1) * apex / 2, 0)
        }
    }

    private func showSand(_ entity: ModelEntity, slot: Int, amount: Float, draining: Bool, turn: simd_quatf) {
        entity.isEnabled = amount > 0.002
        let meshes = draining ? drainMeshes : heapMeshes
        guard !meshes.isEmpty else { return }
        let step = Int((amount * Float(Self.sandSteps)).rounded())
        let key = (draining ? 1000 : 0) + step
        if sandShown[slot] != key {
            sandShown[slot] = key
            entity.model?.mesh = meshes[min(step, meshes.count - 1)]
        }
        entity.orientation = turn
    }

    private func applyBody(_ model: MachineModel, layout: MachineLayout) {
        let shape = model.figure
        figureTurn.orientation = simd_quatf(angle: model.figureYaw, axis: SIMD3(0, 1, 0))
        for (slot, part) in zip(figureParts, shape.parts) {
            slot.entity.position = part.center
            slot.entity.scale = part.size / slot.base
            slot.entity.orientation = simd_quatf(angle: part.roll, axis: SIMD3(0, 0, 1))
        }
    }
}
