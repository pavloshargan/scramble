import CoreMotion
import Foundation
import simd

/// Wraps `CMHeadphoneMotionManager` and exposes headphone motion as an
/// `AsyncStream<MotionEvent>`. Ported from whoisbadai; adds StridePods'
/// quaternion sign-continuity fix (q and -q encode the same rotation, and the
/// AirPods stream occasionally flips between them mid-session).
///
/// - Core Motion pushes callbacks on our dedicated serial queue; there is no
///   polling anywhere. Samples only flow while the AirPods are "active"
///   (Automatic Ear Detection off when holding one in hand).
/// - If AirPods are already connected at start, no "did connect" callback
///   fires — the first sample is the only connection signal.
final class HeadphoneMotionProvider: NSObject, CMHeadphoneMotionManagerDelegate {

    private let manager = CMHeadphoneMotionManager()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.kinapod.tennis.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var continuation: AsyncStream<MotionEvent>.Continuation?

    // Quaternion continuity state; only touched on the serial motion queue.
    private var previousQuaternion: simd_quatd?

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }

    var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    /// Starts listening and returns the event stream. Calling `start` again
    /// finishes the previous stream and begins a fresh one — that stop/start
    /// cycle is also the recovery path when the stream stalls.
    func start() -> AsyncStream<MotionEvent> {
        stop()

        let (stream, continuation) = AsyncStream.makeStream(
            of: MotionEvent.self,
            // Motion samples are perishable: better to drop stale ones than queue.
            bufferingPolicy: .bufferingNewest(16)
        )
        self.continuation = continuation

        manager.delegate = self
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let continuation = self.continuation else { return }
            if let motion {
                var q = simd_quatd(ix: motion.attitude.quaternion.x,
                                   iy: motion.attitude.quaternion.y,
                                   iz: motion.attitude.quaternion.z,
                                   r: motion.attitude.quaternion.w)
                if let previous = self.previousQuaternion,
                   simd_dot(previous.vector, q.vector) < 0 {
                    q = simd_quatd(vector: -q.vector)
                }
                self.previousQuaternion = q
                continuation.yield(.sample(MotionSample(deviceMotion: motion, quaternion: q)))
            } else if error != nil {
                // Almost always "not authorized" or "unsupported headphones".
                continuation.yield(.disconnected)
            }
        }

        return stream
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.delegate = nil
        previousQuaternion = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        continuation?.yield(.connected)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        continuation?.yield(.disconnected)
    }
}
