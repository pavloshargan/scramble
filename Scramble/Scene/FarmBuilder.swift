import SceneKit
import simd

/// Builds the farmyard: ground, lighting, and the four egg chutes with their
/// hens perched at the top ends.
enum FarmBuilder {

    static func build(in root: SCNNode) {
        root.addChildNode(groundNode())
        addLighting(to: root)
        for chute in EggGame.chutes {
            root.addChildNode(chuteNode(from: chute.start, to: chute.end))
            root.addChildNode(henNode(at: chute.start))
        }
    }

    private static func groundNode() -> SCNNode {
        let plane = SCNPlane(width: 60, height: 60)
        plane.firstMaterial?.diffuse.contents = PlatformColor(red: 0.35, green: 0.52, blue: 0.25, alpha: 1)
        plane.firstMaterial?.lightingModel = .lambert
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Double.pi / 2, 0, 0)
        return node
    }

    private static func chuteNode(from start: SIMD3<Double>, to end: SIMD3<Double>) -> SCNNode {
        let length = simd_length(end - start)
        let plank = SCNBox(width: CGFloat(length), height: 0.05, length: 0.24, chamferRadius: 0.01)
        plank.firstMaterial?.diffuse.contents = PlatformColor(red: 0.62, green: 0.45, blue: 0.25, alpha: 1)
        let node = SCNNode(geometry: plank)
        let mid = (start + end) / 2
        node.position = SCNVector3(mid.x, mid.y - 0.06, mid.z)   // just under the rolling egg
        node.eulerAngles = SCNVector3(0, 0, atan2(end.y - start.y, end.x - start.x))

        // Low side rails so the plank reads as a chute.
        for side in [-1.0, 1.0] {
            let rail = SCNBox(width: CGFloat(length), height: 0.05, length: 0.02, chamferRadius: 0)
            rail.firstMaterial?.diffuse.contents = PlatformColor(red: 0.5, green: 0.35, blue: 0.18, alpha: 1)
            let railNode = SCNNode(geometry: rail)
            railNode.position = SCNVector3(0, 0.04, side * 0.12)
            node.addChildNode(railNode)
        }
        return node
    }

    private static func henNode(at start: SIMD3<Double>) -> SCNNode {
        let hen = SCNNode()
        hen.position = SCNVector3(start.x, start.y + 0.1, start.z)

        let body = SCNSphere(radius: 0.16)
        body.firstMaterial?.diffuse.contents = PlatformColor(white: 0.96, alpha: 1)
        hen.addChildNode(SCNNode(geometry: body))

        let comb = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.1)
        comb.firstMaterial?.diffuse.contents = PlatformColor(red: 0.85, green: 0.15, blue: 0.12, alpha: 1)
        let combNode = SCNNode(geometry: comb)
        combNode.position = SCNVector3(0, 0.2, 0)
        hen.addChildNode(combNode)

        let beak = SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.09)
        beak.firstMaterial?.diffuse.contents = PlatformColor.orange
        let beakNode = SCNNode(geometry: beak)
        // Point the beak inward, toward the chute.
        beakNode.position = SCNVector3(start.x < 0 ? 0.15 : -0.15, 0.02, 0)
        beakNode.eulerAngles = SCNVector3(0, 0, start.x < 0 ? -Double.pi / 2 : Double.pi / 2)
        hen.addChildNode(beakNode)

        // Perch post down to the ground.
        let post = SCNCylinder(radius: 0.035, height: CGFloat(start.y))
        post.firstMaterial?.diffuse.contents = PlatformColor(red: 0.45, green: 0.32, blue: 0.18, alpha: 1)
        let postNode = SCNNode(geometry: post)
        postNode.position = SCNVector3(0, -0.1 - start.y / 2, 0)
        hen.addChildNode(postNode)

        return hen
    }

    private static func addLighting(to root: SCNNode) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        ambient.color = PlatformColor(white: 0.95, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 900
        sun.castsShadow = true
        sun.shadowRadius = 4
        sun.shadowSampleCount = 8
        sun.shadowColor = PlatformColor(white: 0, alpha: 0.35)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-1.0, -0.4, 0)
        root.addChildNode(sunNode)
    }
}
