import Foundation
import simd

/// One-gesture calibration: spin the AirPod once around its stem. Gravity
/// averaged over the whole turn gives the handle axis — all the 2D tilt
/// control needs. The heading (which way is LEFT) comes from the player's
/// first reach toward the first egg, so nothing else is asked.
/// After calibration the handle axis keeps self-trimming whenever the hand is
/// still and near upright, so drift never accumulates mid-game.
@MainActor
final class SpinCalibrator: ObservableObject {

    @Published private(set) var isReady = false
    @Published private(set) var spinDegrees: Double = 0

    /// Fired once when a full spin has been detected (and the hand settled).
    var onSpinComplete: (() -> Void)?

    /// Raw values of the last completed capture, for logging/analysis.
    struct CaptureSummary {
        let handleUp: SIMD3<Double>
        let spinDegrees: Double
        let gravityWeight: Double
    }
    private(set) var lastCaptureSummary: CaptureSummary?

    /// A spin counts as full from ~315°; the integral overshoots anyway.
    private let minSpinRadians = 5.5

    private var capturing = false
    private var gravAccum = SIMD3<Double>.zero
    private var gravWeight = 0.0
    private var spinRadians = 0.0
    private var spinQuietSince: TimeInterval?
    private var spinCompleteFired = false

    private var handleUp: SIMD3<Double>?
    private var yawCorrection: simd_quatd?
    private var lastTimestamp: TimeInterval?
    private var lastQuaternion: simd_quatd?

    func begin() {
        capturing = true
        gravAccum = .zero
        gravWeight = 0
        spinRadians = 0
        spinDegrees = 0
        spinQuietSince = nil
        spinCompleteFired = false
    }

    /// Ends the capture (spin completed or skipped); nil if no data arrived.
    func finish() -> ((simd_quatd) -> simd_quatd)? {
        capturing = false
        guard gravWeight > 0, simd_length(gravAccum) > 0.1,
              let q = lastQuaternion else { return nil }
        handleUp = -simd_normalize(gravAccum / gravWeight)

        // Zero the yaw of the current pose, computed once so later trims
        // never re-zero (which would yank the display).
        let frame = simd_quatd(from: SIMD3(0, 0, 1), to: handleUp ?? SIMD3(0, 0, 1))
        let yaw = simd_quatd.yaw(of: q * frame)
        yawCorrection = simd_quatd(angle: -yaw, axis: SIMD3(0, 0, 1))

        lastCaptureSummary = CaptureSummary(handleUp: handleUp ?? SIMD3(0, 0, 1),
                                            spinDegrees: spinDegrees,
                                            gravityWeight: gravWeight)
        isReady = true
        return rebuildTransform()
    }

    /// Feeds one sample; returns an updated display transform when the grip
    /// estimate was trimmed, nil when nothing changed.
    func ingest(_ sample: MotionSample) -> ((simd_quatd) -> simd_quatd)? {
        let dt = min(max(sample.timestamp - (lastTimestamp ?? sample.timestamp), 0), 0.1)
        lastTimestamp = sample.timestamp
        lastQuaternion = sample.quaternion

        if capturing {
            gravAccum += sample.gravity * dt
            gravWeight += dt
            if sample.rotationMagnitude > 0.3 {
                spinRadians += sample.rotationMagnitude * dt
                spinQuietSince = nil
            } else if spinRadians >= minSpinRadians, !spinCompleteFired {
                if spinQuietSince == nil { spinQuietSince = sample.timestamp }
                if sample.timestamp - (spinQuietSince ?? sample.timestamp) > 0.4 {
                    spinCompleteFired = true
                    onSpinComplete?()
                }
            }
            spinDegrees = min(spinRadians * 180 / .pi, 360)
            return nil
        }

        // Continuous trim: only while still AND within ~15° of the current
        // estimate, so intentional gameplay tilts are never absorbed into it.
        let up = -simd_normalize(sample.gravity)
        let still = sample.accelerationMagnitude < 0.08 && sample.rotationMagnitude < 0.5
        guard let current = handleUp, still, dt > 0,
              simd_dot(current, up) > cos(0.26) else { return nil }
        handleUp = simd_normalize(current + (up - current) * min(dt / 4.0, 1))
        return rebuildTransform()
    }

    private func rebuildTransform() -> (simd_quatd) -> simd_quatd {
        let frame = simd_quatd(from: SIMD3(0, 0, 1), to: handleUp ?? SIMD3(0, 0, 1))
        let correction = yawCorrection ?? simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        return { attitude in correction * attitude * frame }
    }
}
