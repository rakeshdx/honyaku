import AppKit
import CoreGraphics

enum PasteError: Error {
    case noFocusedTextField
    case simulationFailed
}

actor PasteService: PasteServiceProtocol {
    private let pasteboardClearDelaySeconds: Double = 5.0
    private let sendPasteKeystroke: @Sendable () throws -> Void
    private let restoreDelay: Duration
    /// The system clipboard in the app; tests pass a private pasteboard so the user's clipboard is never touched.
    /// NSPasteboard isn't Sendable, but it is thread-safe for the reads and writes made here.
    private nonisolated(unsafe) let pasteboard: NSPasteboard

    /// `sendPasteKeystroke` defaults to a real ⌘V; tests inject a recorder so they never type into other apps.
    /// `restoreDelay` must outlast slow clipboard readers — terminals missed the paste at 150 ms.
    init(pasteboard: NSPasteboard = .general, restoreDelay: Duration = .milliseconds(500),
         sendPasteKeystroke: @escaping @Sendable () throws -> Void = { try PasteService.postCommandV() }) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.sendPasteKeystroke = sendPasteKeystroke
    }

    private typealias ClipboardItems = [(NSPasteboard.PasteboardType, Data)]
    /// The user's clipboard waiting to be put back, and the background task that will do it
    private var pendingRestore: (items: ClipboardItems, task: Task<Void, Never>)?

    /// Pastes `text` and returns as soon as ⌘V is posted, so the next dictation isn't blocked;
    /// the previous clipboard is restored in the background after `restoreDelay`.
    func paste(_ text: String) async throws {
        // A pending restore holds the user's real clipboard — the pasteboard now holds our last transcript
        let priorItems: ClipboardItems
        if let pending = pendingRestore {
            pending.task.cancel()
            pendingRestore = nil
            priorItems = pending.items
        } else {
            priorItems = Self.items(on: pasteboard)
        }

        // Write transcript
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let transcriptChangeCount = pasteboard.changeCount

        do {
            try sendPasteKeystroke()
        } catch {
            Self.restore(priorItems, to: pasteboard)
            throw error
        }

        // Give the target app time to read the transcript, without holding up the pipeline
        let delay = restoreDelay
        let task = Task {
            try? await Task.sleep(for: delay)
            finishRestore(expectedChangeCount: transcriptChangeCount)
        }
        pendingRestore = (priorItems, task)
    }

    /// Waits for a background clipboard restore to finish (tests).
    func waitForPendingRestore() async {
        await pendingRestore?.task.value
    }

    /// Synchronous on purpose: no suspension point, so a new paste can't read the clipboard mid-restore.
    private func finishRestore(expectedChangeCount: Int) {
        guard !Task.isCancelled, let pending = pendingRestore else { return }  // superseded by a newer paste
        pendingRestore = nil
        // If anything was copied meanwhile, it's newer than what we'd restore — leave it
        guard pasteboard.changeCount == expectedChangeCount else { return }
        Self.restore(pending.items, to: pasteboard)
    }

    private static func items(on pasteboard: NSPasteboard) -> ClipboardItems {
        (pasteboard.pasteboardItems ?? []).flatMap { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }

    /// Call this on pipeline abort or error — clears transcript from pasteboard within 5s.
    func clearTranscriptFromPasteboard(after delay: Double = 0) async {
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        nonisolated(unsafe) let pasteboard = pasteboard
        await MainActor.run {
            _ = pasteboard.clearContents()
        }
    }

    /// Simulates ⌘V into the frontmost app.
    static func postCommandV() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw PasteError.simulationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    // MARK: - Private

    private static func restore(_ priorItems: ClipboardItems, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if priorItems.isEmpty { return }
        let item = NSPasteboardItem()
        for (type, data) in priorItems {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }
}
