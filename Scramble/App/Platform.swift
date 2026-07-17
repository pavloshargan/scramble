import SceneKit

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#endif

/// Draws into a bitmap context and returns a platform image. Used for the
/// procedurally generated textures (net mesh).
func drawPlatformImage(size: CGSize, _ draw: (CGContext) -> Void) -> PlatformImage {
    #if os(macOS)
    let image = NSImage(size: size)
    image.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        draw(context)
    }
    image.unlockFocus()
    return image
    #else
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { rendererContext in
        draw(rendererContext.cgContext)
    }
    #endif
}
