import SceneKit
import simd

/// Owns the SceneKit scene graph and drives the egg game from the renderer
/// delegate. The net pivots around a fixed base; its orientation comes from the
/// calibrated AirPod attitude, with an in-game "tilt LEFT to start" gesture
/// anchoring which world direction is the player's left.
final class GameSceneController: NSObject {
    let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let netPivot = SCNNode()
    private let engine = EggGame()
    private var eggNodes: [Int: SCNNode] = [:]
    private var lastRenderTime: TimeInterval?

    /// Rotates Core Motion's reference frame (z up) into SceneKit's (y up).
    private static let motionToSceneFrame = simd_quatd(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

    /// Fixed base the net rotates around ("the wolf stands still").
    private static let netBase = SIMD3<Double>(0, 0.30, 0)

    /// Maps a raw device attitude to the net's display attitude (from
    /// calibration). Nil until the wizard has run.
    var attitudeTransform: ((simd_quatd) -> simd_quatd)?

    /// Amplifies hand tilt so comfortable wrist motion reaches the low chutes.
    var tiltGain = 1.5

    /// (score, best) — called from the render thread on every change.
    var onScoreChanged: ((Int, Int) -> Void)?
    /// Called when a round begins (start gesture recognized).
    var onGameStarted: (() -> Void)?
    /// (finalScore, best) — called when an egg breaks and the round ends.
    var onGameOver: ((Int, Int) -> Void)?

    private var anchorYaw: Double?
    private var tiltSince: TimeInterval?

    /// Forget the "which way is left" anchor (used when the grip resets).
    func resetAnchor() {
        anchorYaw = nil
        tiltSince = nil
    }

    /// The calibration resolved the heading itself (baked into the attitude
    /// transform) → skip the first-reach fallback anchoring.
    func setAnchorResolved(_ resolved: Bool) {
        anchorYaw = resolved ? 0 : nil
        tiltSince = nil
    }

    /// Begins a round.
    func startGame() {
        engine.startPlaying()
        onGameStarted?()
    }

    /// Ends a running round without a game-over (mid-round recalibration).
    func abortRound() {
        engine.abort()
        for (_, node) in eggNodes {
            node.removeFromParentNode()
        }
        eggNodes.removeAll()
    }

    private var netHeadWorld = SIMD3<Double>(0, 1.4, 0)
    private var lastReportedScore = -1
    private var lastReportedBest = -1

    override init() {
        super.init()

        scene.background.contents = PlatformColor(red: 0.55, green: 0.75, blue: 0.92, alpha: 1)
        FarmBuilder.build(in: scene.rootNode)

        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.9, 4.8)
        cameraNode.look(at: SCNVector3(0, 1.1, 0))
        scene.rootNode.addChildNode(cameraNode)

        netPivot.position = SCNVector3(Self.netBase.x, Self.netBase.y, Self.netBase.z)
        netPivot.addChildNode(NetFactory.make())
        scene.rootNode.addChildNode(netPivot)
    }

    func attach(to view: SCNView) {
        view.scene = scene
        view.pointOfView = cameraNode
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.delegate = self
        view.showsStatistics = false
    }

    // MARK: - Motion input

    func updateNet(with sample: MotionSample) {
        // Before calibration the net just stands upright.
        guard var attitude = attitudeTransform?(sample.quaternion) else { return }

        // Heading anchor: the first sustained tilt after the countdown defines
        // the player's LEFT (screen -x). The first egg always rolls on the
        // upper-left chute, so the player's natural first reach is a left tilt
        // — no instruction needed. Restarts: settle upright, then tilt again.
        let axis = attitude.act(SIMD3(0, 0, 1))
        if anchorYaw == nil {
            let tilt = acos(max(-1, min(1, axis.z)))
            if tilt > 0.28 {
                if tiltSince == nil { tiltSince = sample.timestamp }
                if sample.timestamp - (tiltSince ?? sample.timestamp) > 0.2 {
                    let horizontal = SIMD3(axis.x, axis.y, 0)
                    if simd_length(horizontal) > 1e-3 {
                        anchorYaw = .pi - atan2(horizontal.y, horizontal.x)
                        tiltSince = nil
                    }
                }
            } else {
                tiltSince = nil
            }
        }

        attitude = simd_quatd(angle: anchorYaw ?? 0, axis: SIMD3(0, 0, 1)) * attitude

        // Amplify the tilt (capped short of horizontal) so the low chutes are
        // reachable without extreme wrist angles.
        if abs(tiltGain - 1) > 0.01, attitude.angle > 1e-4 {
            attitude = simd_quatd(angle: min(attitude.angle * tiltGain, 1.45),
                                  axis: attitude.axis)
        }

        let q = Self.motionToSceneFrame * attitude * Self.motionToSceneFrame.inverse
        netPivot.simdOrientation = simd_quatf(
            ix: Float(q.imag.x), iy: Float(q.imag.y), iz: Float(q.imag.z), r: Float(q.real))

        netHeadWorld = Self.netBase + q.act(NetFactory.headLocal)
    }

    // MARK: - Egg node management

    private func makeEggNode() -> SCNNode {
        let sphere = SCNSphere(radius: 0.085)
        sphere.firstMaterial?.diffuse.contents = PlatformColor(white: 0.98, alpha: 1)
        let node = SCNNode(geometry: sphere)
        node.scale = SCNVector3(1, 1.25, 1)
        return node
    }

    private func handle(_ event: EggEvent) {
        switch event {
        case .spawned(let id, _):
            let node = makeEggNode()
            eggNodes[id] = node
            scene.rootNode.addChildNode(node)

        case .caught(let id, _):
            guard let node = eggNodes.removeValue(forKey: id) else { return }
            // Reparent into the net so the egg rides with it, then let it sink
            // through the hoop to the bottom of the bag before fading.
            let local = netPivot.convertPosition(node.position, from: scene.rootNode)
            node.removeFromParentNode()
            node.position = local
            netPivot.addChildNode(node)

            let sink = SCNAction.move(to: SCNVector3(0, NetFactory.headLocal.y - 0.42, 0),
                                      duration: 0.28)
            sink.timingMode = .easeIn
            node.runAction(.sequence([
                sink,
                .group([.scale(to: 0.75, duration: 0.25), .fadeOut(duration: 0.35)]),
                .removeFromParentNode(),
            ]))

            if let bag = netPivot.childNode(withName: "bag", recursively: true) {
                bag.runAction(.sequence([
                    .scale(to: 1.18, duration: 0.09),
                    .scale(to: 1.0, duration: 0.18),
                ]))
            }

        case .broken(let id, let position):
            guard let node = eggNodes.removeValue(forKey: id) else { return }
            node.position = SCNVector3(position.x, 0.03, position.z)
            node.scale = SCNVector3(1.7, 0.18, 1.7)
            node.geometry?.firstMaterial?.diffuse.contents =
                PlatformColor(red: 0.98, green: 0.85, blue: 0.35, alpha: 1)
            node.runAction(.sequence([
                .wait(duration: 0.7),
                .fadeOut(duration: 0.4),
                .removeFromParentNode(),
            ]))

        case .gameOver(let finalScore, let best):
            // Round over: any eggs still rolling vanish.
            for (_, node) in eggNodes {
                node.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
            }
            eggNodes.removeAll()
            onGameOver?(finalScore, best)
        }
    }
}

extension GameSceneController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        defer { lastRenderTime = time }
        guard let last = lastRenderTime else { return }

        let events = engine.update(dt: min(time - last, 0.25), netHead: netHeadWorld)
        for event in events { handle(event) }

        for egg in engine.eggs {
            eggNodes[egg.id]?.position = SCNVector3(egg.position.x, egg.position.y, egg.position.z)
        }

        if engine.score != lastReportedScore || engine.bestScore != lastReportedBest {
            lastReportedScore = engine.score
            lastReportedBest = engine.bestScore
            onScoreChanged?(engine.score, engine.bestScore)
        }
    }
}
