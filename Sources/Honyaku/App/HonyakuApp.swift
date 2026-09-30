import SwiftUI

@main
struct HonyakuApp: App {
    // The menu bar icon and both windows are AppKit (see AppCoordinator), so the app needs no visible scene
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs at least one scene; this one is never inserted into the menu bar
        MenuBarExtra("Honyaku", systemImage: "waveform", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
