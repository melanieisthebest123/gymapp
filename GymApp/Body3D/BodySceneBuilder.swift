import SceneKit
import UIKit

/// Builds a stylised human figure out of primitives. Every muscle group is a separate
/// node named "muscle:<rawValue>" so it can be coloured, hit-tested and resized.
enum BodySceneBuilder {
    static let baseColor = UIColor(white: 0.55, alpha: 1)
    static let skinColor = UIColor(red: 0.85, green: 0.68, blue: 0.56, alpha: 1)

    struct Options {
        var shape = BodyShape()
        /// When set, muscles are tinted by these colours (muscle map mode). Otherwise uniform skin.
        var muscleColors: [MuscleGroup: UIColor]?
        var opacity: CGFloat = 1
    }

    static func makeBody(_ o: Options) -> SCNNode {
        let root = SCNNode()
        let s = o.shape

        func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.roughness.contents = 0.65
            m.metalness.contents = 0.0
            m.transparency = o.opacity
            if o.opacity < 1 { m.writesToDepthBuffer = false; m.blendMode = .alpha }
            return m
        }

        func color(for group: MuscleGroup?) -> UIColor {
            guard let group, let map = o.muscleColors else {
                return o.muscleColors == nil ? skinColor : baseColor
            }
            return map[group] ?? baseColor
        }

        /// Adds a part, mirrored on both sides when `mirror` is true.
        func add(_ geometry: @autoclosure () -> SCNGeometry, at p: SCNVector3,
                 scale: SCNVector3 = SCNVector3(1, 1, 1), euler: SCNVector3 = SCNVector3Zero,
                 group: MuscleGroup? = nil, mirror: Bool = false) {
            let sides: [Float] = mirror ? [1, -1] : [1]
            for side in sides {
                let g = geometry()
                g.materials = [material(color(for: group))]
                let node = SCNNode(geometry: g)
                node.position = SCNVector3(p.x * side, p.y, p.z)
                node.scale = scale
                node.eulerAngles = SCNVector3(euler.x, euler.y, euler.z * side)
                node.name = group.map { "muscle:\($0.rawValue)" } ?? "base"
                root.addChildNode(node)
            }
        }

        func girth(_ f: Double, _ x: Float = 1, _ y: Float = 1, _ z: Float = 1) -> SCNVector3 {
            SCNVector3(x * Float(f), y, z * Float(f))
        }

        let shoulderX = Float(0.21 * (0.6 + 0.4 * s.shoulders))
        let armX = shoulderX + 0.04

        // Head, neck, core (non-muscle base)
        add(SCNSphere(radius: 0.105), at: SCNVector3(0, 1.66, 0), scale: SCNVector3(0.9, 1.1, 1))
        add(SCNCylinder(radius: 0.05, height: 0.12), at: SCNVector3(0, 1.52, 0))
        add(SCNCapsule(capRadius: 0.15, height: 0.6), at: SCNVector3(0, 1.2, 0),
            scale: girth((s.chest + s.waist) / 2, 1.15, 1, 0.65))
        add(SCNBox(width: 0.3, height: 0.14, length: 0.18, chamferRadius: 0.06),
            at: SCNVector3(0, 0.93, 0), scale: girth(s.hips))

        // Torso muscles
        add(SCNSphere(radius: 0.1), at: SCNVector3(0.085, 1.32, 0.07),
            scale: girth(s.chest, 1.05, 0.72, 0.5), group: .chest, mirror: true)
        add(SCNCapsule(capRadius: 0.05, height: 0.3), at: SCNVector3(0, 1.46, -0.04),
            scale: girth(s.shoulders, 1, 1, 0.8), euler: SCNVector3(0, 0, Float.pi / 2), group: .traps)
        add(SCNSphere(radius: 0.072), at: SCNVector3(shoulderX, 1.39, 0),
            scale: girth(s.arms), group: .shoulders, mirror: true)
        add(SCNBox(width: 0.17, height: 0.27, length: 0.06, chamferRadius: 0.03),
            at: SCNVector3(0, 1.08, Float(0.075 * s.waist)), scale: girth(s.waist, 1, 1, 1), group: .abs)
        add(SCNBox(width: 0.05, height: 0.22, length: 0.1, chamferRadius: 0.02),
            at: SCNVector3(Float(0.115 * s.waist), 1.06, 0.03), group: .obliques, mirror: true)
        add(SCNBox(width: 0.3, height: 0.14, length: 0.06, chamferRadius: 0.03),
            at: SCNVector3(0, 1.34, -0.085), scale: girth(s.chest), group: .upperBack)
        add(SCNBox(width: 0.09, height: 0.24, length: 0.05, chamferRadius: 0.025),
            at: SCNVector3(Float(0.12 * s.chest), 1.17, -0.07), euler: SCNVector3(0, 0, 0.18),
            group: .lats, mirror: true)
        add(SCNBox(width: 0.18, height: 0.13, length: 0.05, chamferRadius: 0.025),
            at: SCNVector3(0, 0.99, Float(-0.085 * s.waist)), group: .lowerBack)
        add(SCNSphere(radius: 0.09), at: SCNVector3(0.075, 0.87, Float(-0.075 * s.hips)),
            scale: girth(s.hips, 1, 1, 0.9), group: .glutes, mirror: true)

        // Arms
        add(SCNCapsule(capRadius: 0.042, height: 0.25), at: SCNVector3(armX, 1.2, 0.02),
            scale: girth(s.arms), group: .biceps, mirror: true)
        add(SCNCapsule(capRadius: 0.045, height: 0.27), at: SCNVector3(armX, 1.2, -0.025),
            scale: girth(s.arms), group: .triceps, mirror: true)
        add(SCNCapsule(capRadius: 0.038, height: 0.27), at: SCNVector3(armX + 0.01, 0.93, 0),
            scale: girth((1 + s.arms) / 2), group: .forearms, mirror: true)
        add(SCNSphere(radius: 0.045), at: SCNVector3(armX + 0.015, 0.76, 0),
            scale: SCNVector3(0.8, 1.2, 0.6), mirror: true)

        // Legs
        add(SCNCapsule(capRadius: 0.075, height: 0.42), at: SCNVector3(0.1, 0.62, 0.025),
            scale: girth(s.thighs), group: .quads, mirror: true)
        add(SCNCapsule(capRadius: 0.065, height: 0.38), at: SCNVector3(0.1, 0.63, -0.035),
            scale: girth(s.thighs), group: .hamstrings, mirror: true)
        add(SCNCapsule(capRadius: 0.04, height: 0.36), at: SCNVector3(0.1, 0.24, 0.015),
            scale: girth(s.calves), mirror: true)
        add(SCNCapsule(capRadius: 0.052, height: 0.28), at: SCNVector3(0.1, 0.27, -0.03),
            scale: girth(s.calves), group: .calves, mirror: true)
        add(SCNBox(width: 0.08, height: 0.05, length: 0.2, chamferRadius: 0.02),
            at: SCNVector3(0.1, 0.03, 0.04), mirror: true)

        return root
    }

    static func makeScene(body: SCNNode, ghost: SCNNode? = nil) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(body)
        if let ghost { scene.rootNode.addChildNode(ghost) }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 35
        camera.position = SCNVector3(0, 0.95, 3.4)
        camera.look(at: SCNVector3(0, 0.9, 0))
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 450
        scene.rootNode.addChildNode(fill)
        return scene
    }

    /// Weekly working-set volume → colour. Grey = untrained, orange → red = well trained.
    static func heatColor(sets: Double) -> UIColor {
        guard sets > 0 else { return baseColor }
        let t = CGFloat(min(sets / 12, 1))
        return UIColor(red: 0.95, green: 0.75 - 0.6 * t, blue: 0.2 - 0.15 * t, alpha: 1)
    }
}
