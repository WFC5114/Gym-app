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
    /// BODY's rendered tray (RenderedArt), shown on the face behind the live mannequin.
    private var bodyBackdrop: ModelEntity?
    /// Keys and gauges as clay and glass objects (clay skins).
    private let clayParts = ClayPartsRig()

    /// Clay skins sit every face on a thick clay tray: this many points of it
    /// stand proud of the chassis, the rest is sunk into it.
    static var trayProud: CGFloat { Brutal.skin.clayUI ? 5 : 0 }
    static let trayDepth: CGFloat = 12

    // TRAIN
    private let glassGroup = Entity()
    private let glassSpin = Entity()
    /// Sand in the glass-local top (A) and bottom (B) bulbs. Each shows either the
    /// draining shape or the pile, from meshes made once per step of sand.
    private var sandA = ModelEntity()
    private var sandB = ModelEntity()
    /// Sand meshes by step, made the first time each step shows (keyed drain 1000+, pile 0+).
    private var sandMeshes: [Int: MeshResource] = [:]
    private var sandShown: [Int] = [-1, -1]
    private var stream: ModelEntity?
    /// The clay frame and glass; it shows the REST lettering on the lower slab.
    private var hourglassRig: HourglassRig?
    /// Sand drawn in this many steps; at a 3:00 rest that is one step every 3.75 s.
    static let sandSteps = 48

    /// Called once the scene has run a few frames, so a screenshot taken after it
    /// shows the machine and not an empty view still uploading its meshes.
    var onDrawn: (() -> Void)?
    private var updates = 0
    private static let updatesBeforeDrawn = 6

    // BODY: the clay mannequin on its dial turntable; its root sits at the feet.
    private let figureRoot = Entity()
    private var figureRig: MannequinRig?

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
        // A fainter grain for clay: a fine pressed surface, not crumpled paper.
        var clayGrain: TextureResource?
        if let clayImage = MaterialKit.grainImage(seed: 0xC1A7_0001, strength: 0.3) {
            clayGrain = try? await TextureResource(image: clayImage, withName: "clayGrain",
                                                   options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll))
        }
        if let grainImage = MaterialKit.grainImage(),
           let grain = try? await TextureResource(image: grainImage, withName: "grain",
                                                   options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll)) {
            materials = MaterialKit.make(skin: Brutal.skin, grain: grain, clayGrain: clayGrain)
        } else {
            materials = MaterialKit.make(skin: Brutal.skin, grain: nil, clayGrain: clayGrain)
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
        let keyFrom = SIMD3<Float>(-2.4, 3.4, 5.0)
        if #available(iOS 27, *) {
            // iOS 27 spot lights cast soft, area-like shadows whose penumbra
            // widens with distance, like the softbox in the clay mockups. The
            // key is split: an unshadowed directional share keeps the shading,
            // a spot share from the same side casts the soft shadows.
            var keyLight = DirectionalLightComponent(color: .white, intensity: 5200 * 0.55)
            keyLight.isRealWorldProxy = false
            key.components.set(keyLight)
            let softKey = Entity()
            let distance: Float = 13
            let lux: Float = 5200 * 0.45
            softKey.components.set(SpotLightComponent(color: .white, intensity: lux * 4 * .pi * distance * distance,
                                                      innerAngleInDegrees: 34, outerAngleInDegrees: 48, attenuationRadius: 60))
            var shadow = SpotLightComponent.Shadow()
            shadow.quality = .high
            shadow.lightSize = 1.2
            shadow.depthBias = 2
            softKey.components.set(shadow)
            softKey.look(at: .zero, from: simd_normalize(keyFrom) * distance, relativeTo: nil)
            root.addChild(softKey)
        } else {
            var keyLight = DirectionalLightComponent(color: .white, intensity: 5200)
            keyLight.isRealWorldProxy = false
            key.components.set(keyLight)
            key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 2))
        }
        key.look(at: .zero, from: keyFrom, relativeTo: nil)
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
                self.updates += 1
                if self.updates == Self.updatesBeforeDrawn { self.onDrawn?() }
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
        bodyBackdrop?.removeFromParent()
        bodyBackdrop = nil
        if RenderedArt.on(.body), faces.count > 2, let plane = Self.renderedBackdrop("night-body-backdrop", layout: layout) {
            faces[2].addChild(plane)
            bodyBackdrop = plane
        }
        for (i, face) in faces.enumerated() {
            let theta = Float(i) * 2 * .pi / 3
            face.position = SIMD3(a * sin(theta), 0, a * cos(theta))
            face.orientation = simd_quatf(angle: theta, axis: SIMD3(0, 1, 0))
            // The skin's colour inlay, set just proud of the chassis inside its bevel.
            if Brutal.skin.clayUI, i < materials.facePlates.count {
                // A pressed graphite clay tray, rounded at the corners and rolled at the edges.
                let inset: CGFloat = 7
                if let mesh = try? Geometry.slab(halfWidth: World.len(layout.faceWidth / 2 - inset), halfHeight: World.len(layout.faceHeight / 2 - inset),
                                                 depth: World.len(Self.trayDepth), corner: World.len(26), bevel: World.len(5), name: "tray") {
                    let plate = ModelEntity(mesh: mesh, materials: [materials.facePlates[i]])
                    plate.position = World.point(CGPoint(x: layout.faceWidth / 2, y: layout.faceHeight / 2),
                                                 z: Self.trayProud - Self.trayDepth, in: layout)
                    face.addChild(plate)
                    facePlates.append(plate)
                }
            } else if i < materials.facePlates.count {
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

        // The jar in clay (Wei approved round 2 of design/mockups/clay/objects.py,
        // 14 Oct 2026): thick candy glass (an outer shell seen from outside, an
        // inner shell seen from inside), a cream collar round the mouth with a
        // rust seam, corner screws and a DIET plaque, raised graduations and a
        // TARGET bar on the front glass, on an indigo plinth with a knurled band.
        let clay = materials.clay
        let centerZ = Depth.jar / 2 + 2
        let frontZ = centerZ + Depth.jar / 2
        let outerGlass = box(g.outer.size, depth: Depth.jar, radius: JarGeometry.cornerRadius, material: clay.glass)
        outerGlass.position = World.point(CGPoint(x: g.outer.midX, y: g.outer.midY), z: centerZ, in: layout)
        jarGroup.addChild(outerGlass)
        var insideGlass = clay.glass
        insideGlass.faceCulling = .front
        let innerGlass = box(CGSize(width: g.interior.width, height: g.outer.height - JarGeometry.wall),
                             depth: Depth.jar - 2 * JarGeometry.wall, radius: g.innerRadius, material: insideGlass)
        innerGlass.position = World.point(CGPoint(x: g.interior.midX, y: g.outer.minY + (g.outer.height - JarGeometry.wall) / 2 - 1),
                                          z: centerZ, in: layout)
        jarGroup.addChild(innerGlass)

        // The collar is a frame of four bars, so blocks rising past the mouth pass through it.
        let collarY = g.outer.minY + 2
        func frame(height: CGFloat, bar: CGFloat, grow: CGFloat, radius: CGFloat, _ material: PhysicallyBasedMaterial) {
            let width = g.outer.width + 10 + grow, depth = Depth.jar + 10 + grow
            for z in [frontZ + 5 - bar / 2 + grow / 2, centerZ - depth / 2 + bar / 2] {
                let e = box(CGSize(width: width, height: height), depth: bar, radius: radius, material: material)
                e.position = World.point(CGPoint(x: g.outer.midX, y: collarY), z: z, in: layout)
                jarGroup.addChild(e)
            }
            for x in [g.outer.minX - 5 - grow / 2 + bar / 2, g.outer.maxX + 5 + grow / 2 - bar / 2] {
                let e = box(CGSize(width: bar, height: height), depth: depth, radius: radius, material: material)
                e.position = World.point(CGPoint(x: x, y: collarY), z: centerZ, in: layout)
                jarGroup.addChild(e)
            }
        }
        frame(height: 14, bar: 12, grow: 0, radius: 5, clay.body)
        frame(height: 2.2, bar: 12, grow: 1, radius: 1, clay.socket)
        let collarFront = frontZ + 5 + 0.5
        for x in [g.outer.minX, g.outer.maxX] {
            jarGroup.addChild(screw(radius: 3, at: World.point(CGPoint(x: x, y: collarY - 3.5), z: collarFront, in: layout)))
        }
        let plaque = box(CGSize(width: 46, height: 11), depth: 3, radius: 2.5, material: clay.hardware)
        plaque.position = World.point(CGPoint(x: g.outer.midX, y: collarY), z: collarFront + 1.5, in: layout)
        jarGroup.addChild(plaque)
        let diet = MeshResource.generateText("DIET", extrusionDepth: World.len(1.2), font: .systemFont(ofSize: CGFloat(World.len(7.5)), weight: .heavy))
        let label = ModelEntity(mesh: diet, materials: [clay.plinth])
        label.position = World.point(CGPoint(x: g.outer.midX, y: collarY), z: collarFront + 3, in: layout) - SIMD3(diet.bounds.center.x, diet.bounds.center.y, 0)
        jarGroup.addChild(label)
        for dx: CGFloat in [-17, 17] {
            jarGroup.addChild(screw(radius: 1.7, at: World.point(CGPoint(x: g.outer.midX + dx, y: collarY), z: collarFront + 3, in: layout)))
        }

        // Raised quarter graduations and the TARGET bar on the front glass.
        let span = g.floorY - g.targetLineY
        for q in 1...3 {
            let tick = box(CGSize(width: 16, height: 2.5), depth: 1.6, radius: 0.8, material: clay.rod)
            tick.position = World.point(CGPoint(x: g.interior.maxX - 14, y: g.floorY - span * CGFloat(q) / 4), z: frontZ + 0.8, in: layout)
            jarGroup.addChild(tick)
        }
        let bar = box(CGSize(width: g.interior.width * 0.92, height: 3), depth: 1.8, radius: 0.9, material: clay.accent)
        bar.position = World.point(CGPoint(x: g.interior.midX, y: g.targetLineY), z: frontZ + 0.9, in: layout)
        jarGroup.addChild(bar)

        // Plinth with a knurled butter band.
        let baseY = g.outer.maxY + 4
        let plinth = box(CGSize(width: g.outer.width + 20, height: 9), depth: Depth.jar + 16, radius: 4, material: clay.plinth)
        plinth.position = World.point(CGPoint(x: g.outer.midX, y: baseY), z: centerZ, in: layout)
        jarGroup.addChild(plinth)
        let band = box(CGSize(width: g.outer.width + 22, height: 3.5), depth: Depth.jar + 18, radius: 1.5, material: clay.hardware)
        band.position = World.point(CGPoint(x: g.outer.midX, y: baseY), z: centerZ, in: layout)
        jarGroup.addChild(band)
        let ribs = Int((g.outer.width + 16) / 4.5)
        let rib = MeshResource.generateBox(width: World.len(1.5), height: World.len(5.5), depth: World.len(1.2), cornerRadius: World.len(0.6))
        for i in 0...ribs {
            let x = g.outer.midX - (g.outer.width + 16) / 2 + CGFloat(i) * (g.outer.width + 16) / CGFloat(ribs)
            let e = ModelEntity(mesh: rib, materials: [clay.hardware])
            e.position = World.point(CGPoint(x: x, y: baseY), z: centerZ + (Depth.jar + 18) / 2 + 0.2, in: layout)
            jarGroup.addChild(e)
        }

        // The loading rail: a ledge under the quick-add blocks.
        let ledge = box(CGSize(width: rail.controls.width, height: 6), depth: 26, radius: 1.5, material: materials.plate)
        ledge.position = World.point(CGPoint(x: rail.controls.midX, y: rail.railLineY + 3), z: 13, in: layout)
        dietGroup.addChild(ledge)
        railBase = ledge

        for kcal in QuickAdd.weights {
            let size = rail.quickBlockSize(kcal: kcal)
            let block = Brutal.skin.clayUI ? foodBlock(size, tint: .quick) : box(size, depth: Depth.block, radius: 6, material: materials.food(.quick))
            block.position = World.point(rail.quickBlockHome(kcal: kcal), z: Depth.block / 2 + 6, in: layout)
            dietGroup.addChild(block)
            railBlocks[kcal] = block
        }
    }

    /// A domed clay screw head with a cross slot, facing the camera.
    private func screw(radius r: CGFloat, at position: SIMD3<Float>) -> Entity {
        let holder = Entity()
        holder.position = position
        holder.orientation = simd_quatf(from: [0, 1, 0], to: [0, 0, 1])
        let rr = World.len(r)
        let dome: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0, rr), SIMD2(rr * 0.25, rr * 0.92), SIMD2(rr * 0.45, rr * 0.6), SIMD2(rr * 0.52, 0)]
        if let mesh = try? Geometry.lathe(dome, segments: 24, name: "screw") {
            holder.addChild(ModelEntity(mesh: mesh, materials: [materials.clay.hardware]))
        }
        let slot = MeshResource.generateBox(width: rr * 1.6, height: rr * 0.4, depth: rr * 0.26)
        for a in [Float(0), .pi / 2] {
            let e = ModelEntity(mesh: slot, materials: [materials.clay.socket])
            e.position = [0, rr * 0.5, 0]
            e.orientation = simd_quatf(angle: a, axis: [0, 1, 0])
            holder.addChild(e)
        }
        return holder
    }

    /// Chunky rounded food block.
    private func foodBlock(_ size: CGSize, tint: FoodTint) -> ModelEntity {
        let round = min(10, size.height * 0.3, size.width * 0.3)
        // Clay skins: a puffy clay block with rolled edges, as in the Night mockup.
        if Brutal.skin.clayUI,
           let mesh = try? Geometry.slab(halfWidth: World.len(size.width / 2), halfHeight: World.len(size.height / 2), depth: World.len(Depth.block),
                                         corner: World.len(min(13, size.height * 0.36, size.width * 0.36)), bevel: World.len(round),
                                         puff: World.len(min(3, size.height * 0.08)), centred: true, name: "foodBlock") {
            return ModelEntity(mesh: mesh, materials: [materials.food(tint)])
        }
        return box(size, depth: Depth.block, radius: round, material: materials.food(tint))
    }

    private func buildHourglass() {
        typealias H = DeskHourglass
        // Presentation turn on the group; SET DONE flips `glassSpin` about its own z.
        glassGroup.orientation = simd_quatf(angle: H.pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: H.yaw, axis: SIMD3(0, 1, 0))
        hourglassRig = HourglassRig(clay: materials.clay, into: glassSpin)

        // Sand: meshes are made per step on first use (see `sandMesh`).
        sandA.model = ModelComponent(mesh: .generateSphere(radius: 0.001), materials: [materials.clay.sand])
        sandB.model = ModelComponent(mesh: .generateSphere(radius: 0.001), materials: [materials.clay.sand])
        sandShown = [-1, -1]
        glassSpin.addChild(sandA)
        glassSpin.addChild(sandB)
        let stream = ModelEntity(mesh: .generateCylinder(height: 1, radius: 1), materials: [materials.clay.sand])
        glassSpin.addChild(stream)
        self.stream = stream
    }

    private func positionHourglass(layout: MachineLayout) {
        let g = HourglassGeometry(layout: layout)
        glassGroup.position = World.point(g.center(forHeight: g.maxHeight), z: 60, in: layout)
    }

    /// A rendered face picture as a flat, unlit plane just proud of the tray:
    /// exactly the render's pixels, with the live 3D objects standing in front.
    private static func renderedBackdrop(_ name: String, layout: MachineLayout) -> ModelEntity? {
        guard let image = RenderedArt.image(name)?.cgImage,
              let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let plane = ModelEntity(mesh: .generatePlane(width: World.len(layout.faceWidth), height: World.len(layout.faceHeight)),
                                materials: [material])
        plane.position = World.point(CGPoint(x: layout.faceWidth / 2, y: layout.faceHeight / 2), z: trayProud + 0.2, in: layout)
        return plane
    }

    private func buildBody(layout: MachineLayout) {
        if figureRig == nil {
            faces[2].addChild(figureRoot)
            let rig = MannequinRig(clay: materials.clay)
            figureRoot.addChild(rig.root)
            figureRig = rig
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

        // A rendered face draws its tray and objects from pictures (RenderedArt).
        let dietRendered = RenderedArt.on(.diet)
        dietGroup.isEnabled = !dietRendered
        if !facePlates.isEmpty { facePlates[0].isEnabled = !dietRendered }
        let trainRendered = RenderedArt.on(.train)
        glassGroup.isEnabled = !trainRendered
        if facePlates.count > 1 { facePlates[1].isEnabled = !trainRendered }
        if facePlates.count > 2 { facePlates[2].isEnabled = bodyBackdrop == nil }
        applyDiet(model, layout: layout)
        for (face, n) in numerals {
            let glyphs = model.heroGlyphs[face]
            // DIET counts on its spring every frame; the others show their text as laid out.
            let text = face == .diet ? Readout.kcal(model.heroKcal.position.rounded()) : (glyphs?.text ?? "")
            let rendered = RenderedArt.on(face) && RenderedArt.covers(text)
            n.root.isEnabled = model.heroIn3D && glyphs != nil && !rendered
            guard model.heroIn3D, !rendered, let glyphs else { continue }
            n.update(text: text, size: glyphs.size, frame: glyphs.frame,
                     punch: face == .diet ? model.heroPunch.position : 0, layout: layout)
        }
        applyTrain(model, layout: layout)
        applyBody(model, layout: layout)
        clayParts.apply(model, faces: faces, layout: layout, chrome: materials.chrome, surface: Self.trayProud)
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
        hourglassRig?.apply(angle: Float(model.glassAngle.position))

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
            stream.scale = SIMD3(0.0028, length, 0.0028)
            stream.position = SIMD3(0, (aUp ? 1 : -1) * apex / 2, 0)
        }
    }

    private func showSand(_ entity: ModelEntity, slot: Int, amount: Float, draining: Bool, turn: simd_quatf) {
        entity.isEnabled = amount > 0.002
        let step = min(max(Int((amount * Float(Self.sandSteps)).rounded()), 0), Self.sandSteps)
        let key = (draining ? 1000 : 0) + step
        if sandShown[slot] != key, let mesh = sandMesh(key: key, step: step, draining: draining) {
            sandShown[slot] = key
            entity.model?.mesh = mesh
        }
        entity.orientation = turn
    }

    private func sandMesh(key: Int, step: Int, draining: Bool) -> MeshResource? {
        if let mesh = sandMeshes[key] { return mesh }
        let amount = Float(step) / Float(Self.sandSteps)
        let profile = draining ? DeskHourglass.drainProfile(amount) : DeskHourglass.heapProfile(amount)
        let mesh = try? Geometry.lathe(profile, segments: 56, name: draining ? "drain\(step)" : "heap\(step)")
        sandMeshes[key] = mesh
        return mesh
    }

    private func applyBody(_ model: MachineModel, layout: MachineLayout) {
        figureRig?.apply(shape: model.figure, pose: model.figurePose, yaw: model.figureYaw)
    }
}
