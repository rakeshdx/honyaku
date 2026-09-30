import AppKit
import SwiftUI

// MARK: - Menu bar icon

/// The menu bar icon. A click opens Settings (or first run); a right-click or Control-click shows a
/// small menu, since there's no popover to hold Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onOpen: () -> Void
    private let onSettings: () -> Void
    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Honyaku", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }()

    init(onOpen: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Honyaku")
        setSymbol(Self.symbol(for: .idle))
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

    func setSymbol(_ name: String) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Honyaku")
        image?.isTemplate = true
        item.button?.image = image
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
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

/// One window hosting SwiftUI content. Showing it again brings the same window forward rather than
/// opening a second; with `freshContentOnReopen`, a closed window starts over when it's shown again.
@MainActor
final class HostedWindow: NSObject {
    private let title: String
    private let freshContentOnReopen: Bool
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(title: String, freshContentOnReopen: Bool = false, content: @escaping () -> AnyView) {
        self.title = title
        self.freshContentOnReopen = freshContentOnReopen
        self.makeContent = content
    }

    func show() {
        if let window {
            if !window.isVisible, freshContentOnReopen {
                window.contentViewController = NSHostingController(rootView: makeContent())
            }
        } else {
            let hosting = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The Settings window: native toolbar tabs, one hosted SwiftUI view each. Built once and reused, so
/// clicking the icon again only brings it forward.
@MainActor
final class SettingsWindowController: NSObject {
    enum Tab: String, CaseIterable {
        case general, models, dictation, history, privacy

        var title: String {
            switch self {
            case .general: return "General"
            case .models: return "Models"
            case .dictation: return "Dictation"
            case .history: return "History"
            case .privacy: return "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .models: return "square.stack.3d.up"
            case .dictation: return "text.bubble"
            case .history: return "clock"
            case .privacy: return "lock"
            }
        }
    }

    /// Remembers the last tab across launches.
    static let lastTabKey = "settingsTab"

    private unowned let coordinator: AppCoordinator
    private var window: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
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
        let saved = UserDefaults.standard.string(forKey: Self.lastTabKey).flatMap(Tab.init(rawValue:)) ?? .general
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
            case .history: HistorySettings()
            case .privacy: PrivacySettings()
            }
        }
    }
}

/// Resizes the window to each tab's own size, and remembers the last tab chosen.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(id, forKey: SettingsWindowController.lastTabKey)
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
