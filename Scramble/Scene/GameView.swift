import SwiftUI
import SceneKit

#if os(macOS)
struct GameView: NSViewRepresentable {
    let controller: GameSceneController

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        controller.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
}
#else
struct GameView: UIViewRepresentable {
    let controller: GameSceneController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
#endif
