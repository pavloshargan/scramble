import SceneKit

/// The player's egg-catching landing net: wooden handle, hoop, and a hanging
/// mesh bag. Origin at the handle butt, hoop at the top with its opening
/// facing up.
enum NetFactory {

    /// Local position of the hoop center — the catch point.
    static let headLocal = SIMD3<Double>(0, 0.98, 0)

    static func make() -> SCNNode {
        let net = SCNNode()
        net.name = "net"

        // The handle stops at the bag's bottom tip (the bag spans y ≈ 0.48–0.98),
        // so the stick never pokes through the netting.
        let handle = SCNCylinder(radius: 0.018, height: 0.5)
        handle.firstMaterial?.diffuse.contents = PlatformColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)
        let handleNode = SCNNode(geometry: handle)
        handleNode.position = SCNVector3(0, 0.25, 0)
        net.addChildNode(handleNode)

        let hoop = SCNTorus(ringRadius: 0.28, pipeRadius: 0.02)
        hoop.firstMaterial?.diffuse.contents = PlatformColor(red: 0.85, green: 0.55, blue: 0.15, alpha: 1)
        let hoopNode = SCNNode(geometry: hoop)   // torus lies flat: opening faces up
        hoopNode.position = SCNVector3(headLocal.x, headLocal.y, headLocal.z)
        net.addChildNode(hoopNode)

        let bag = SCNCone(topRadius: 0.27, bottomRadius: 0.06, height: 0.5)
        let bagMaterial = SCNMaterial()
        bagMaterial.diffuse.contents = meshTexture()
        bagMaterial.isDoubleSided = true
        bagMaterial.lightingModel = .constant
        bag.materials = [bagMaterial]
        let bagNode = SCNNode(geometry: bag)
        bagNode.name = "bag"
        bagNode.position = SCNVector3(0, headLocal.y - 0.25, 0)
        net.addChildNode(bagNode)

        return net
    }

    /// Loose white netting on a transparent background.
    private static func meshTexture() -> PlatformImage {
        let size = 256.0
        return drawPlatformImage(size: CGSize(width: size, height: size)) { context in
            context.setFillColor(PlatformColor(white: 1.0, alpha: 0.7).cgColor)
            let spacing = 22.0
            var offset = spacing / 2
            while offset < size {
                context.fill(CGRect(x: offset, y: 0, width: 1.4, height: size))
                context.fill(CGRect(x: 0, y: offset, width: size, height: 1.4))
                offset += spacing
            }
        }
    }
}
