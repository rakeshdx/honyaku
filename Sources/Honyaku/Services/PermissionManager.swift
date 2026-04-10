import AVFoundation
import ApplicationServices
import AppKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published var microphoneGranted: Bool = false
    @Published var accessibilityGranted: Bool = false

    func checkAll() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    func openMicrophoneSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        )
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    /// Prompts for Accessibility if not yet trusted; returns whether granted.
    @discardableResult
    func requestAccessibility() -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    var allGranted: Bool { microphoneGranted && accessibilityGranted }
}
