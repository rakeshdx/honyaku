import AppKit

/// The "Rewrite as" submenu in the menu bar icon's right-click menu: Automatic (by app), then the templates,
/// with a checkmark on the current choice. It sets the same choice as Settings > Rewrite.
@MainActor
final class RewriteMenu: NSObject, NSMenuDelegate {
    let item: NSMenuItem
    private let settings: RewriteSettings

    static let automaticIdentifier = "statusMenu.rewrite.automatic"
    static func identifier(for template: RewriteTemplateID) -> String { "statusMenu.rewrite.\(template.rawValue)" }

    init(settings: RewriteSettings) {
        self.settings = settings
        item = NSMenuItem(title: "Rewrite as", action: nil, keyEquivalent: "")
        // Tells this menu apart from the app's main menu in UI tests
        item.identifier = NSUserInterfaceItemIdentifier("statusMenu.rewrite")
        super.init()
        let submenu = NSMenu(title: "Rewrite as")
        submenu.delegate = self
        let automatic = NSMenuItem(title: "Automatic (by app)", action: #selector(choose(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.identifier = NSUserInterfaceItemIdentifier(Self.automaticIdentifier)
        submenu.addItem(automatic)
        submenu.addItem(.separator())
        for template in RewriteTemplateID.allCases {
            let entry = NSMenuItem(title: template.name, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = template.rawValue
            entry.identifier = NSUserInterfaceItemIdentifier(Self.identifier(for: template))
            submenu.addItem(entry)
        }
        item.submenu = submenu
        updateCheckmarks(submenu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateCheckmarks(menu)
    }

    private func updateCheckmarks(_ menu: NSMenu) {
        for entry in menu.items where !entry.isSeparatorItem {
            let template = (entry.representedObject as? String).flatMap(RewriteTemplateID.init(rawValue:))
            entry.state = template == settings.fixedTemplate ? .on : .off
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        settings.fixedTemplate = (sender.representedObject as? String).flatMap(RewriteTemplateID.init(rawValue:))
    }
}
