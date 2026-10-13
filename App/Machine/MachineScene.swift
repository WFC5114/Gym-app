import RealityKit
import SwiftUI

/// The RealityKit side of the machine: one prism, its three mechanisms, the
/// orthographic camera and the lights. `apply` copies the model's current
/// presentation state onto entities every rendered frame.
@MainActor
final class MachineScene {
    let root = Entity()
    let prismRoot = Entity()
    let camera = Entity()
    var faces: [Entity] = []
    var materials = MaterialKit.make(skin: Brutal.skin, grain: nil)
    private var builtLayout: MachineLayout?
    private var prismModel: ModelEntity?
    private var subscription: EventSubscription?

    // DIET
    private let dietGroup = Entity()
    private var plinth: ModelEntity?
    private var plate: ModelEntity?
    private var posts: [ModelEntity] = []
    private var springs: [ModelEntity] = []
    private var railBlocks: [Int: ModelEntity] = [:]
    private var railBase: ModelEntity?
    private var blockEntities: [UUID: ModelEntity] = [:]
    private var pendingEntity: ModelEntity?
    private var pendingKey: UUID?
    private var slabEntities: [UUID: (entity: ModelEntity, size: CGSize)] = [:]
    private var coilMesh: MeshResource?

    private var dietNumerals: Numerals3D?
    private var facePlates: [ModelEntity] = []

    // TRAIN
    private let glassGroup = Entity()
    private let glassSpin = Entity()
    private var sandA = Entity()
    private var sandB = Entity()
    private var sandConeA: ModelEntity?
    private var sandConeB: ModelEntity?
    private var stream: ModelEntity?

    // BODY
    private var bodyEntity: ModelEntity?
    private var bodyKey: Int?
    private var bodyPlinth: ModelEntity?

    /// Depths above the face surface, in points.
    enum Depth {
        static let plate: CGFloat = 34
        static let block: CGFloat = 40
        static let lift: CGFloat = 46
    }

    func make(content: inout RealityViewCameraContent, model: MachineModel) async {
        content.camera = .virtual
        if let grainImage = MaterialKit.grainImage(),
           let grain = try? await TextureResource(image: grainImage, withName: "grain",
                                                   options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll)) {
            materials = MaterialKit.make(skin: Brutal.skin, grain: grain)
        }
        if let envImage = MaterialKit.environmentImage(),
           let env = try? await EnvironmentResource(equirectangular: envImage, withName: "studio") {
            content.environment = .skybox(env)
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

        coilMesh = try? Geometry.coil(radius: 0.18, wire: 0.035, turns: 5.5)
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
        if dietNumerals == nil {
            let numerals = Numerals3D(material: materials.numeral)
            faces[0].addChild(numerals.root)
            dietNumerals = numerals
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
        railBlocks = [:]
        blockEntities = [:]
        slabEntities = [:]
        pendingEntity = nil
        pendingKey = nil
        let g = model.deckGeometry
        let rail = model.rail

        let plinth = box(g.plinthRect.size, depth: 30, radius: 3, material: materials.plate)
        plinth.position = World.point(CGPoint(x: g.plinthRect.midX, y: g.plinthRect.midY), z: 15, in: layout)
        dietGroup.addChild(plinth)
        self.plinth = plinth

        let plate = box(CGSize(width: g.deckWidth, height: g.plateThickness), depth: Depth.plate, radius: 3, material: materials.plate)
        dietGroup.addChild(plate)
        self.plate = plate

        // Two guide posts frame the deck's travel.
        posts = []
        let postTop = g.mech.minY + 6
        let postBottom = g.plinthRect.minY
        for x in [g.centerX - g.deckWidth / 2 - 9, g.centerX + g.deckWidth / 2 + 9] {
            let post = box(CGSize(width: 6, height: postBottom - postTop), depth: 18, radius: 1.5, material: materials.plate)
            post.position = World.point(CGPoint(x: x, y: (postTop + postBottom) / 2), z: 9, in: layout)
            dietGroup.addChild(post)
            posts.append(post)
        }

        springs = []
        if let coilMesh {
            for _ in g.springXOffsets {
                let spring = ModelEntity(mesh: coilMesh, materials: [materials.spring])
                dietGroup.addChild(spring)
                springs.append(spring)
            }
        }

        // The loading rail: a ledge under the quick-add blocks.
        let ledge = box(CGSize(width: rail.controls.width, height: 6), depth: 26, radius: 1.5, material: materials.plate)
        ledge.position = World.point(CGPoint(x: rail.controls.midX, y: rail.railLineY + 3), z: 13, in: layout)
        dietGroup.addChild(ledge)
        railBase = ledge

        for kcal in Deck.weights {
            let size = rail.quickBlockSize(kcal: kcal)
            let block = box(size, depth: Depth.block, radius: 4, material: materials.weight)
            block.position = World.point(rail.quickBlockHome(kcal: kcal), z: Depth.block / 2 + 6, in: layout)
            dietGroup.addChild(block)
            railBlocks[kcal] = block
        }
    }

    private func buildHourglass() {
        guard let glassMesh = try? Geometry.glass(), let coneMesh = try? Geometry.sandCone() else { return }
        let glass = ModelEntity(mesh: glassMesh, materials: [materials.glass])
        glassSpin.addChild(glass)
        // Frame: two end plates and two posts, in glass units (height 1).
        for y: Float in [0.465, -0.465] {
            let plate = ModelEntity(mesh: .generateBox(width: 0.6, height: 0.07, depth: 0.5, cornerRadius: 0.012), materials: [materials.plate])
            plate.position = SIMD3(0, y, 0)
            glassSpin.addChild(plate)
        }
        for x: Float in [-0.26, 0.26] {
            let post = ModelEntity(mesh: .generateCylinder(height: 0.86, radius: 0.016), materials: [materials.spring])
            post.position = SIMD3(x, 0, 0.12)
            glassSpin.addChild(post)
        }
        let coneA = ModelEntity(mesh: coneMesh, materials: [materials.sand])
        let coneB = ModelEntity(mesh: coneMesh, materials: [materials.sand])
        // A sits in the glass-local top bulb and opens upward, B in the bottom bulb opening downward.
        coneA.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1))
        sandA.addChild(coneA)
        sandB.addChild(coneB)
        glassSpin.addChild(sandA)
        glassSpin.addChild(sandB)
        sandConeA = coneA
        sandConeB = coneB
        let stream = ModelEntity(mesh: .generateCylinder(height: 1, radius: 1), materials: [materials.sand])
        glassSpin.addChild(stream)
        self.stream = stream
    }

    private func positionHourglass(layout: MachineLayout) {
        let g = HourglassGeometry(layout: layout)
        glassGroup.position = World.point(g.center(forHeight: g.maxHeight), z: 60, in: layout)
    }

    private func buildBody(layout: MachineLayout) {
        bodyPlinth?.removeFromParent()
        let mech = layout.mechanismRect
        let plinth = box(CGSize(width: layout.contentWidth * 0.6, height: 16), depth: 60, radius: 3, material: materials.plate)
        plinth.position = World.point(CGPoint(x: layout.faceWidth / 2, y: mech.maxY - 8), z: 30, in: layout)
        faces[2].addChild(plinth)
        bodyPlinth = plinth
        bodyKey = nil
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
        if let numerals = dietNumerals {
            numerals.root.isEnabled = model.heroIn3D && model.dietHeroFrame != nil
            if model.heroIn3D, let frame = model.dietHeroFrame {
                numerals.update(text: Readout.kcal(model.heroKcal.position.rounded()), size: model.dietHeroSize,
                                frame: frame, punch: model.heroPunch.position, layout: layout)
            }
        }
        applyTrain(model, layout: layout)
        applyBody(model, layout: layout)
    }

    private func applyDiet(_ model: MachineModel, layout: MachineLayout) {
        let g = model.deckGeometry
        let d = CGFloat(model.deck.position)
        let plateTop = g.plateTop(displacement: d)
        plate?.position = World.point(CGPoint(x: g.centerX, y: plateTop + g.plateThickness / 2), z: Depth.plate / 2 + 4, in: layout)
        let springTop = plateTop + g.plateThickness
        let springBottom = g.plinthRect.minY
        let length = max(springBottom - springTop, 8)
        for (i, spring) in springs.enumerated() {
            let x = g.centerX + g.springXOffsets[i]
            spring.position = World.point(CGPoint(x: x, y: (springTop + springBottom) / 2), z: 22, in: layout)
            spring.scale = SIMD3(1, World.len(length), 1)
        }

        // Slabs on the deck, one per logged entry.
        let slabs = model.slabRects()
        var seen = Set<UUID>()
        for item in slabs {
            let entry = item.entry, rect = item.rect
            seen.insert(entry.id)
            let finalHeight = g.slabHeights(kcals: [entry.nutrients.kcal]).heights.first ?? rect.height
            let finalSize = CGSize(width: g.slabWidth, height: finalHeight)
            var slot = slabEntities[entry.id]
            if slot == nil || abs(slot!.size.height - finalSize.height) > 0.5 {
                slot?.entity.removeFromParent()
                let material = entry.nutrients.hasMacros ? materials.weight : materials.unknownWeight
                let entity = box(finalSize, depth: Depth.block, radius: min(3, finalSize.height / 3), material: material)
                dietGroup.addChild(entity)
                slot = (entity, finalSize)
                slabEntities[entry.id] = slot
            }
            guard let slot else { continue }
            slot.entity.position = World.point(CGPoint(x: rect.midX, y: rect.midY), z: Depth.block / 2 + 4, in: layout)
            slot.entity.scale = SIMD3(Float(rect.width / max(slot.size.width, 1)), Float(rect.height / max(slot.size.height, 1)), 1)
        }
        for (id, slot) in slabEntities where !seen.contains(id) {
            slot.entity.removeFromParent()
            slabEntities[id] = nil
        }

        // Flying blocks.
        var flying = Set<UUID>()
        var busyQuick = Set<Int>()
        for block in model.blocks {
            flying.insert(block.id)
            if case .quick(let kcal) = block.kind { busyQuick.insert(kcal) }
            var entity = blockEntities[block.id]
            if entity == nil {
                let e = box(block.size, depth: Depth.block, radius: 4, material: materials.weight)
                dietGroup.addChild(e)
                blockEntities[block.id] = e
                entity = e
            }
            let lift = CGFloat(block.lift.position)
            entity?.position = World.point(block.position, z: Depth.block / 2 + 6 + lift * Depth.lift, in: layout)
            entity?.orientation = simd_quatf(angle: Float(-block.tilt.position), axis: SIMD3(0, 0, 1))
            entity?.scale = SIMD3(repeating: Float(1 + 0.05 * lift))
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
                let e = box(size, depth: Depth.block, radius: 4, material: materials.weight)
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

    private func applyTrain(_ model: MachineModel, layout: MachineLayout) {
        let heightPoints = CGFloat(model.glassHeight.position)
        let height = World.len(heightPoints)
        glassGroup.scale = SIMD3(repeating: height)
        // Stand the glass proud of the face so its back half never enters the chassis.
        glassGroup.position = World.point(HourglassGeometry(layout: layout).center(forHeight: heightPoints), z: heightPoints * 0.3 + 8, in: layout)
        glassSpin.orientation = simd_quatf(angle: Float(model.glassAngle.position), axis: SIMD3(0, 0, 1))

        // Each bulb's sand: apex toward the neck. The world-top bulb drains from
        // its surface (anchored at the neck); the world-bottom pile grows from
        // its base. At a full bulb both anchorings coincide, so the flip is seamless.
        let full: Float = 0.36, radius: Float = 0.19, neck: Float = 0.04
        let amountA = Float(min(max(model.sandA.position, 0), 1))
        let amountB = Float(min(max(model.sandB.position, 0), 1))
        let sA = cbrt(amountA), sB = cbrt(amountB)
        let aUp = model.aIsUp
        sandA.isEnabled = amountA > 0.002
        sandB.isEnabled = amountB > 0.002
        sandA.scale = SIMD3(radius * sA, full * sA, radius * sA)
        sandB.scale = SIMD3(radius * sB, full * sB, radius * sB)
        // A: local top bulb, cone opens toward +Y from its apex.
        sandA.position = SIMD3(0, aUp ? neck : (neck + full) - full * sA, 0)
        // B: local bottom bulb, cone opens toward -Y from its apex.
        sandB.position = SIMD3(0, aUp ? -(neck + full) + full * sB : -neck, 0)

        // The falling stream, from the neck to the top of the pile.
        let topAmount = aUp ? amountA : amountB
        let pileApex: Float = aUp ? sandB.position.y : sandA.position.y
        let flowing = model.activeRest != nil && topAmount > 0.002 && model.glassAngle.isSettled(tolerance: 0.02)
        stream?.isEnabled = flowing
        if flowing, let stream {
            let neckY: Float = aUp ? -neck * 0.5 : neck * 0.5
            let lengthY = abs(neckY - pileApex)
            stream.scale = SIMD3(0.006, max(lengthY, 0.001), 0.006)
            stream.position = SIMD3(0, (neckY + pileApex) / 2, 0)
        }
    }

    private func applyBody(_ model: MachineModel, layout: MachineLayout) {
        let index = Int(model.bodyNumbers.target.rounded())
        guard index != bodyKey else { return }
        bodyKey = index
        let carried = BodyObservation.carried(model.bodyHistory, upTo: index)
        guard let mesh = try? Geometry.body(fatPercent: carried.fat, leanKg: carried.lean) else { return }
        if let bodyEntity {
            bodyEntity.model?.mesh = mesh
        } else {
            let e = ModelEntity(mesh: mesh, materials: [materials.body])
            faces[2].addChild(e)
            bodyEntity = e
        }
        let mech = layout.mechanismRect
        let h = mech.height * 0.8
        bodyEntity?.scale = SIMD3(repeating: World.len(h))
        bodyEntity?.position = World.point(CGPoint(x: layout.faceWidth / 2, y: mech.maxY - 16 - h / 2), z: h * 0.4, in: layout)
    }
}
