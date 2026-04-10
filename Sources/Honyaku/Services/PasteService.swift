import AppKit
import CoreGraphics

enum PasteError: Error {
    case noFocusedTextField
    case simulationFailed
}

actor PasteService: PasteServiceProtocol {
    private let pasteboardClearDelaySeconds: Double = 5.0

    func paste(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        // Save prior contents
        let priorItems = (pasteboard.pasteboardItems ?? []).flatMap { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }

        // Write transcript
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate ⌘V
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            await restorePasteboard(priorItems: priorItems)
            throw PasteError.simulationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        // Give the target app ~150ms to receive the paste before restoring clipboard
        try await Task.sleep(for: .milliseconds(150))
        await restorePasteboard(priorItems: priorItems)
    }

    /// Call this on pipeline abort or error — clears transcript from pasteboard within 5s.
    func clearTranscriptFromPasteboard(after delay: Double = 0) async {
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        await MainActor.run {
            _ = NSPasteboard.general.clearContents()
        }
    }

    // MARK: - Private

    @MainActor
    private func restorePasteboard(priorItems: [(NSPasteboard.PasteboardType, Data)]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if priorItems.isEmpty { return }
        let item = NSPasteboardItem()
        for (type, data) in priorItems {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }
}
