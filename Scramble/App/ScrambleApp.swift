import SwiftUI

@main
struct ScrambleApp: App {
    var body: some Scene {
        WindowGroup("Scramble") {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 600)
                #endif
        }
    }
}
