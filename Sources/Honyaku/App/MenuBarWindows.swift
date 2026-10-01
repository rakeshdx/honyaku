import AppKit
import SwiftUI

// MARK: - Menu bar icon

/// The menu bar icon. A click opens Settings (or first run); a right-click shows a small menu, since
/// there's no popover to hold Quit. Control-click is a plain click: Control is the dictation key.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpen: () -> Void
    private let onSettings: () -> Void
    /// Items between "Settings…" and the separator above Quit, such as "Rewrite as".
    private let extraItems: [NSMenuItem]
    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        // Identifiers tell this menu apart from the app's main menu, which has the same titles (UI tests)
        settings.identifier = NSUserInterfaceItemIdentifier("statusMenu.settings")
        menu.addItem(settings)
        for extra in extraItems { menu.addItem(extra) }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Honyaku", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.identifier = NSUserInterfaceItemIdentifier("statusMenu.quit")
        menu.addItem(quit)
        return menu
    }()

    init(onOpen: @escaping () -> Void, onSettings: @escaping () -> Void, extraItems: [NSMenuItem] = []) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.extraItems = extraItems
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Honyaku")
        update(for: .idle)
    }

    /// The state symbol shown in the menu bar.
    nonisolated static func symbol(for status: AppStatus) -> String {
        switch status {
        case .recording:   return "waveform.circle.fill"
        case .transcribing, .processing: return "ellipsis.circle"
        case .error:       return "exclamationmark.circle"
        default:           return "waveform"
        }
    }

    /// What VoiceOver reads after "Honyaku". `rewriting` is true while a rewrite is in progress.
    nonisolated static func accessibilityValue(for status: AppStatus, rewriting: Bool = false) -> String {
        if rewriting, status == .transcribing || status == .processing { return "Rewriting" }
        switch status {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .processing: return "Cleaning up"
        case .error(let message): return "Error: \(message)"
        }
    }

    func update(for status: AppStatus, rewriting: Bool = false) {
        let image = NSImage(systemSymbolName: Self.symbol(for: status), accessibilityDescription: "Honyaku")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityValue(Self.accessibilityValue(for: status, rewriting: rewriting))
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let button = item.button else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            onOpen()
        }
    }

    @objc private func openSettings() { onSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Single windows

extension NSWindow {
    /// Brings the window to the front, restoring it from the Dock if it was minimised.
    func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
    }
}

/// One window hosting SwiftUI content. Showing it again brings the same window forward rather than
/// opening a second; with `freshContentOnReopen`, a closed window starts over when it's shown again.
/// A minimised window is only restored, never rebuilt.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let freshContentOnReopen: Bool
    private let onClose: () -> Void
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    private var closed = false

    init(title: String, freshContentOnReopen: Bool = false, onClose: @escaping () -> Void = {},
         content: @escaping () -> AnyView) {
        self.title = title
        self.freshContentOnReopen = freshContentOnReopen
        self.onClose = onClose
        self.makeContent = content
    }

    func show() {
        if let window {
            if closed, freshContentOnReopen {
                window.contentViewController = NSHostingController(rootView: makeContent())
            }
        } else {
            let hosting = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        closed = false
        window?.bringForward()
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        onClose()
    }
}

/// The Settings window: native toolbar tabs, one hosted SwiftUI view each. Built once and reused, so
/// clicking the icon again only brings it forward.
@MainActor
final class SettingsWindowController: NSObject {
    enum Tab: String, CaseIterable {
        case general, models, dictation, vocabulary, rewrite, apps, history, privacy

        var title: String {
            switch self {
            case .general: return "General"
            case .models: return "Models"
            case .dictation: return "Dictation"
            case .vocabulary: return "Vocabulary"
            case .rewrite: return "Rewrite"
            case .apps: return "Apps"
            case .history: return "History"
            case .privacy: return "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .models: return "square.stack.3d.up"
            case .dictation: return "text.bubble"
            case .vocabulary: return "character.book.closed"
            case .rewrite: return "wand.and.stars"
            case .apps: return "square.grid.2x2"
            case .history: return "clock"
            case .privacy: return "lock"
            }
        }
    }

    /// Remembers the last tab across launches.
    static let lastTabKey = "settingsTab"
    /// Posted with a `Tab` raw value as its object to switch the open Settings window to that tab
    /// (e.g. the Rewrite tab's button to the Models tab).
    static let showTabNotification = Notification.Name("HonyakuShowSettingsTab")

    private unowned let coordinator: AppCoordinator
    private var window: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.bringForward()
    }

    private func makeWindow() -> NSWindow {
        // The app's settings, which are a separate suite in tests and UI-test launches
        let defaults = coordinator.features.defaults
        let tabs = SettingsTabViewController()
        tabs.defaults = defaults
        tabs.tabStyle = .toolbar
        for tab in Tab.allCases {
            let hosting = NSHostingController(rootView: AnyView(coordinator.withSharedState(content(for: tab))))
            hosting.sizingOptions = .preferredContentSize
            hosting.title = tab.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        let saved = defaults.string(forKey: Self.lastTabKey).flatMap(Tab.init(rawValue:)) ?? .general
        tabs.selectedTabViewItemIndex = Tab.allCases.firstIndex(of: saved) ?? 0

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.center()
        return window
    }

    private func content(for tab: Tab) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings()
            case .models: ModelsSettings()
            case .dictation: DictationSettings()
            case .vocabulary: VocabularySettings()
            case .rewrite: RewriteSettingsView()
            case .apps: AppsSettings()
            case .history: HistorySettings()
            case .privacy: PrivacySettings()
            }
        }
    }
}

/// Resizes the window to each tab's own size, and remembers the last tab chosen.
private final class SettingsTabViewController: NSTabViewController {
    var defaults: UserDefaults = .standard

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(forName: SettingsWindowController.showTabNotification, object: nil,
                                               queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let id = note.object as? String,
                      let index = self.tabViewItems.firstIndex(where: { $0.identifier as? String == id }) else { return }
                self.selectedTabViewItemIndex = index
            }
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            defaults.set(id, forKey: SettingsWindowController.lastTabKey)
        }
        fitWindow(animated: view.window?.isVisible ?? false)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        fitWindow(animated: true)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fitWindow(animated: false)
    }

    private func fitWindow(animated: Bool) {
        guard let window = view.window, selectedTabViewItemIndex >= 0,
              let content = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        let size = content.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        // Keep the title bar where it is; grow or shrink downwards
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated)
    }
}
