import Foundation
import QuartzCore

/// Consumes the motion event stream on the main actor, tracks connection health
/// (StridePods-style watchdog: no sample for 2s → stalled, 5s → force restart),
/// and fans out samples to the scene while publishing a throttled HUD readout.
@MainActor
final class MotionHub: ObservableObject {

    enum Status: Equatable {
        case unavailable
        case waiting
        case streaming
        case stalled

        var label: String {
            switch self {
            case .unavailable: return "Motion not available"
            case .waiting: return "Waiting for AirPods…"
            case .streaming: return "Streaming"
            case .stalled: return "Stalled — reconnecting…"
            }
        }
    }

    struct Readout {
        var acceleration = SIMD3<Double>.zero
        var accelerationMagnitude = 0.0
        var rotationMagnitude = 0.0
        var rollDegrees = 0.0
        var pitchDegrees = 0.0
        var yawDegrees = 0.0
        var sampleRateHz = 0.0
    }

    @Published private(set) var status: Status = .waiting
    @Published private(set) var readout = Readout()

    /// Called on the main actor for every sample — drives the 3D racket gizmo.
    var onSample: ((MotionSample) -> Void)?

    private let provider = HeadphoneMotionProvider()
    private var consumeTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var lastSampleClock: Double = 0
    private var lastSampleTimestamp: TimeInterval?
    private var rateEMA: Double = 0
    private var sampleCounter = 0

    func start() {
        guard consumeTask == nil else { return }
        if !provider.isDeviceMotionAvailable {
            status = .unavailable
        }
        subscribe()

        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHealth() }
        }
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        consumeTask?.cancel()
        consumeTask = nil
        provider.stop()
    }

    private func subscribe() {
        consumeTask?.cancel()
        let stream = provider.start()
        consumeTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: MotionEvent) {
        switch event {
        case .connected:
            if status != .streaming { status = .waiting }

        case .disconnected:
            status = .waiting
            lastSampleTimestamp = nil

        case .sample(let sample):
            lastSampleClock = CACurrentMediaTime()
            if let last = lastSampleTimestamp {
                let dt = sample.timestamp - last
                if dt > 0 { rateEMA += (1.0 / dt - rateEMA) * 0.05 }
            }
            lastSampleTimestamp = sample.timestamp
            status = .streaming

            onSample?(sample)

            // Publish to SwiftUI at ~1/4 of the sensor rate; text can't usefully
            // update faster and this keeps view churn down.
            sampleCounter += 1
            if sampleCounter % 4 == 0 {
                readout = Readout(
                    acceleration: sample.userAcceleration,
                    accelerationMagnitude: sample.accelerationMagnitude,
                    rotationMagnitude: sample.rotationMagnitude,
                    rollDegrees: sample.roll * 180 / .pi,
                    pitchDegrees: sample.pitch * 180 / .pi,
                    yawDegrees: sample.yaw * 180 / .pi,
                    sampleRateHz: rateEMA
                )
            }
        }
    }

    private func checkHealth() {
        guard status == .streaming || status == .stalled else { return }
        let age = CACurrentMediaTime() - lastSampleClock
        if age > 5 {
            // Force a stop/start cycle — recovers a stalled CMHeadphoneMotionManager.
            status = .stalled
            subscribe()
        } else if age > 2 {
            status = .stalled
        }
    }
}
