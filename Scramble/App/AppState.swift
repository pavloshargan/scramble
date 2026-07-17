#if os(macOS)
import AppKit
#endif
import Foundation

/// Top-level wiring and game flow. Calibration (once per launch, redoable via
/// the Recalibrate button) is a single gesture: hold upright, then spin the
/// AirPod once around its stem. The player's first reach toward the first egg
/// defines "left". The primary action (start / skip / retry) is triggered by
/// SPACE on the Mac and by the on-screen buttons on both platforms.
@MainActor
final class AppState: ObservableObject {

    enum Stage: Equatable {
        case intro          // grip card, waiting for the primary action
        case calibrating    // upright hold, then one spin around the stem
        case playing        // game handed over to the scene/engine
    }

    enum CalibrationStep: Equatable { case upright, spin }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var calibrationStep: CalibrationStep?
    @Published private(set) var countdown: Int?   // pre-round warm-up, net is live
    /// While the setup guide is on screen, the primary action is ignored — the
    /// user must explicitly press Done.
    @Published var showingSetupHelp = false
    @Published private(set) var score = 0
    @Published private(set) var bestScore = 0
    @Published private(set) var lastRoundScore: Int?   // set on game over, nil while playing
    @Published private(set) var gameStarted = false
    @Published var tiltGain = 1.5 {
        didSet { sceneController.tiltGain = tiltGain }
    }

    let sceneController = GameSceneController()
    let motionHub = MotionHub()
    let calibrator = SpinCalibrator()

    private var started = false
    private var lastSample: MotionSample?
    private var countdownTask: Task<Void, Never>?
    #if os(macOS)
    private var keyMonitor: Any?
    #endif

    func start() {
        guard !started else { return }
        started = true
        sceneController.tiltGain = tiltGain

        sceneController.onScoreChanged = { [weak self] score, best in
            Task { @MainActor in
                self?.score = score
                self?.bestScore = best
            }
        }

        sceneController.onGameStarted = { [weak self] in
            Task { @MainActor in
                self?.gameStarted = true
                self?.lastRoundScore = nil
            }
        }

        sceneController.onGameOver = { [weak self] finalScore, best in
            Task { @MainActor in
                self?.gameStarted = false
                self?.lastRoundScore = finalScore
                self?.bestScore = best
            }
        }

        calibrator.onSpinComplete = { [weak self] in
            self?.finishCalibration()
        }

        motionHub.onSample = { [weak self] sample in
            guard let self else { return }
            self.lastSample = sample
            if let transform = self.calibrator.ingest(sample) {
                self.sceneController.attitudeTransform = transform
            }
            self.sceneController.updateNet(with: sample)
        }
        motionHub.start()

        #if os(macOS)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49 else { return event }   // space
            return self.primaryAction() ? nil : event
        }
        #endif
    }

    /// SPACE / on-screen button. Returns true when it did something.
    @discardableResult
    func primaryAction() -> Bool {
        guard !showingSetupHelp, motionHub.status == .streaming else { return false }
        switch stage {
        case .calibrating:
            finishCalibration()   // skip the spin
            return true
        case .intro:
            beginCalibration()
            return true
        case .playing where !gameStarted && countdown == nil:
            // Calibration happens once per launch — retries start directly.
            calibrator.isReady ? startRoundWithCountdown() : beginCalibration()
            return true
        default:
            return false
        }
    }

    /// Redo the calibration — available anytime while playing; a running round
    /// is aborted (best score is preserved).
    func recalibrate() {
        guard stage == .playing else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        sceneController.abortRound()
        gameStarted = false
        beginCalibration()
    }

    /// Warm-up: the net is live during the 3-2-1 so the player can practice
    /// before the first egg rolls.
    private func startRoundWithCountdown() {
        guard countdownTask == nil else { return }
        countdownTask = Task { @MainActor in
            for n in [3, 2, 1] {
                countdown = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            countdownTask = nil
            sceneController.startGame()
        }
    }

    private func beginCalibration() {
        stage = .calibrating
        calibrationStep = .upright
        calibrator.begin()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if stage == .calibrating, calibrationStep == .upright {
                calibrationStep = .spin
            }
        }
    }

    private func finishCalibration() {
        guard stage == .calibrating else { return }
        calibrationStep = nil
        if let transform = calibrator.finish() {
            sceneController.attitudeTransform = transform
            sceneController.setAnchorResolved(false)   // first reach defines left
            if let summary = calibrator.lastCaptureSummary {
                CalibrationLog.record(summary)
            }
            stage = .playing
            startRoundWithCountdown()
        } else {
            // No motion data arrived — back to the intro.
            stage = .intro
        }
    }
}
