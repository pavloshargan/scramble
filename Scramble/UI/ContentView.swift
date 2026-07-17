import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppState()
    // Shown automatically on the very first launch, then only via ⓘ.
    @AppStorage("hasSeenSetupHelp") private var hasSeenSetupHelp = false

    var body: some View {
        GameView(controller: app.sceneController)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if app.stage == .playing {
                    Text("🥚 \(app.score)    🏆 \(app.bestScore)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 12)
                }
            }
            .overlay {
                if app.stage == .intro {
                    IntroCardView(hub: app.motionHub) { app.primaryAction() }
                } else if app.stage == .calibrating {
                    CalibrationOverlay(step: app.calibrationStep,
                                       calibrator: app.calibrator) { app.primaryAction() }
                } else if let n = app.countdown {
                    VStack(spacing: 8) {
                        Text("\(n)")
                            .font(.system(size: 110, weight: .heavy, design: .rounded))
                        Text("Warm up — try moving the net!")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .id(n)
                } else if app.stage == .playing, !app.gameStarted, let last = app.lastRoundScore {
                    VStack(spacing: 12) {
                        Text("Score: \(last)")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                        Text("🏆 Best: \(app.bestScore)")
                            .font(.title2.weight(.semibold))
                        ActionPill(label: "try again") { app.primaryAction() }
                    }
                    .foregroundStyle(.white)
                    .padding(30)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    app.showingSetupHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                if app.stage == .playing {
                    Button("Recalibrate") { app.recalibrate() }
                        .buttonStyle(.bordered)
                        .padding(12)
                }
            }
            .overlay {
                if app.showingSetupHelp {
                    SetupHelpView {
                        hasSeenSetupHelp = true
                        app.showingSetupHelp = false
                    }
                }
            }
            .onAppear {
                app.start()
                if !hasSeenSetupHelp { app.showingSetupHelp = true }
            }
    }
}

/// Primary-action button: reads "press SPACE" on the Mac, "tap" on iOS —
/// clicking/tapping it works on both.
private struct ActionPill: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            #if os(macOS)
            Text("␣ Press SPACE to \(label)")
            #else
            Text("Tap to \(label)")
            #endif
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.semibold))
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.15), in: Capsule())
    }
}

/// Hold upright first, then one spin around the stem; finishes automatically.
private struct CalibrationOverlay: View {
    let step: AppState.CalibrationStep?
    @ObservedObject var calibrator: SpinCalibrator
    let skipAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if step == .spin {
                Text("Now make a spin 🔄")
                    .font(.title2.weight(.bold))
                Text("Keep it upright — one slow full turn around the stem.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ProgressView(value: calibrator.spinDegrees / 360)
                    .frame(width: 240)
                Text(String(format: "%.0f° / 360° — finishes automatically", calibrator.spinDegrees))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Skip", action: skipAction)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Hold it upright ☝️")
                    .font(.title2.weight(.bold))
                Text("Stem down, nice and steady…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 400)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Observes the hub directly so streaming state flips the CTA the moment
/// samples arrive. First-run emphasis on the AirPods setup requirements.
private struct IntroCardView: View {
    @ObservedObject var hub: MotionHub
    let startAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Ready? 🥚")
                .font(.title3.weight(.semibold))
            Text("Take the **LEFT** AirPod in your hand\nand hold it **upright** — stem pointing down.")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text("⚠️ One-time AirPods setup (required):")
                    .font(.callout.weight(.bold))
                Text("• Turn OFF “Automatic Ear Detection”")
                Text("• Set Microphone to “Always Left AirPod”")
                Text("Without these, motion stops the moment the\nAirPod leaves your ear. Details under ⓘ (top right).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(12)
            .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            if hub.status == .streaming {
                ActionPill(label: "start", action: startAction)
            } else {
                Label("Waiting for AirPods motion…", systemImage: "airpods")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 440)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Full AirPods setup walkthrough, reachable anytime via the ⓘ button.
private struct SetupHelpView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AirPods Setup")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            Text("The game reads motion from an AirPod held in your hand. Two settings are required, or the sensor stream stops as soon as the AirPod leaves your ear:")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                #if os(macOS)
                Text("1. Open **System Settings**, go to **Bluetooth**.")
                #else
                Text("1. Open **Settings**, go to **Bluetooth**.")
                #endif
                Text("2. Make sure your AirPods are connected, then press the **ⓘ icon** next to them.")
                Text("3. In the AirPods settings, **scroll down** to find the options below.")
                Text("4. Turn **OFF “Automatic Ear Detection”** — this keeps audio (and motion) active out of the ear.")
                Text("5. Set **Microphone → “Always Left AirPod”** — this keeps the left pod the active one.")
                Text("6. Hold the **left** AirPod in your playing hand; the right one can stay in the case.")
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("If the game says “Waiting for AirPods motion…” while connected, play any audio briefly or re-select the AirPods as sound output — that wakes the motion stream.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { onClose() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 480)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
    }
}
