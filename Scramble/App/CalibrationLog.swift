import Foundation

/// Appends every calibration capture to a JSON-lines file in the app's caches
/// directory (~/Library/Caches/com.kinapod.tennis/calibrations.jsonl) so grip
/// captures can be analyzed later.
enum CalibrationLog {

    static var fileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.kinapod.tennis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calibrations.jsonl")
    }

    static func record(_ summary: SpinCalibrator.CaptureSummary) {
        let entry: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "handleUp": [summary.handleUp.x, summary.handleUp.y, summary.handleUp.z],
            "spinDegrees": summary.spinDegrees,
            "gravityWeight": summary.gravityWeight,
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        data.append(0x0A)   // newline

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
