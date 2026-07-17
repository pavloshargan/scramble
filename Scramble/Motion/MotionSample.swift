import CoreMotion
import simd

/// A single, immutable snapshot of AirPods motion. Ported from whoisbadai, with the
/// attitude quaternion added (needed to drive the 3D racket) — everything downstream
/// (swing detection, calibration, racket pose) is decoupled from Core Motion.
struct MotionSample: Sendable {
    /// Device timestamp in seconds (monotonic, from `CMDeviceMotion.timestamp`).
    let timestamp: TimeInterval

    /// User-generated acceleration in g, gravity already removed by Core Motion.
    let userAcceleration: SIMD3<Double>

    /// Gravity direction in the *device frame*, in g (points toward the ground,
    /// magnitude ≈ 1).
    let gravity: SIMD3<Double>

    /// Angular velocity in radians/second.
    let rotationRate: SIMD3<Double>

    /// Attitude of the AirPod relative to Core Motion's reference frame.
    /// Sign-continuity (q vs -q) is already fixed up by the provider.
    let quaternion: simd_quatd

    var accelerationMagnitude: Double { simd_length(userAcceleration) }
    var rotationMagnitude: Double { simd_length(rotationRate) }

    var roll: Double { simd_quatd.roll(of: quaternion) }
    var pitch: Double { simd_quatd.pitch(of: quaternion) }
    var yaw: Double { simd_quatd.yaw(of: quaternion) }

    init(deviceMotion motion: CMDeviceMotion, quaternion: simd_quatd) {
        timestamp = motion.timestamp
        userAcceleration = SIMD3(motion.userAcceleration.x,
                                 motion.userAcceleration.y,
                                 motion.userAcceleration.z)
        gravity = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        rotationRate = SIMD3(motion.rotationRate.x,
                             motion.rotationRate.y,
                             motion.rotationRate.z)
        self.quaternion = quaternion
    }

    /// Memberwise initializer, useful for tests and synthetic input.
    init(timestamp: TimeInterval,
         userAcceleration: SIMD3<Double>,
         gravity: SIMD3<Double> = SIMD3(0, 0, -1),
         rotationRate: SIMD3<Double>,
         quaternion: simd_quatd = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)) {
        self.timestamp = timestamp
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.rotationRate = rotationRate
        self.quaternion = quaternion
    }
}

/// Connection changes and samples travel through one stream so consumers see
/// them in order.
enum MotionEvent: Sendable {
    case connected
    case disconnected
    case sample(MotionSample)
}

extension simd_quatd {
    /// Euler angles matching Core Motion's roll/pitch/yaw convention.
    static func roll(of q: simd_quatd) -> Double {
        let v = q.vector
        return atan2(2 * (v.w * v.x + v.y * v.z), 1 - 2 * (v.x * v.x + v.y * v.y))
    }
    static func pitch(of q: simd_quatd) -> Double {
        let v = q.vector
        let s = 2 * (v.w * v.y - v.z * v.x)
        return asin(max(-1, min(1, s)))
    }
    static func yaw(of q: simd_quatd) -> Double {
        let v = q.vector
        return atan2(2 * (v.w * v.z + v.x * v.y), 1 - 2 * (v.y * v.y + v.z * v.z))
    }
}
