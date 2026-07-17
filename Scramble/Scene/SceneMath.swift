import SceneKit

extension SCNVector3 {
    /// SceneKit's vector components are CGFloat on macOS but Float on iOS;
    /// this initializer papers over the difference.
    init(_ x: Double, _ y: Double, _ z: Double) {
        #if os(macOS)
        self.init(x: CGFloat(x), y: CGFloat(y), z: CGFloat(z))
        #else
        self.init(x: Float(x), y: Float(y), z: Float(z))
        #endif
    }
}
