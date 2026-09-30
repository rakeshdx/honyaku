import AppKit
import SwiftUI

/// Honyaku's design tokens. Everything not named here uses the system's own colours and materials.
enum Theme {
    /// 藍 (ai), Japanese indigo — the one accent: app tint, selection, the idle keycap glyph.
    static let ai = Color(nsColor: dynamic(light: 0x2E4A7D, dark: 0x8FA8D8))
    /// `ai` behind white text (prominent buttons, the current step): white on the dark-mode `ai` is only
    /// 2.4:1, on this 6.8:1.
    static let aiFill = Color(nsColor: dynamic(light: 0x2E4A7D, dark: 0x3D5A96))
    /// Live — the keycap and level meter while recording, and nothing else. Dark enough in both modes for
    /// the white glyph on the pressed key (about 4:1).
    static let live = Color(nsColor: dynamic(light: 0xE0484F, dark: 0xE5484D))

    static let keyFace = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x3A3F4A))
    static let keyLip = Color(nsColor: dynamic(light: 0xC6CBD4, dark: 0x1D2028))
    static let keyEdge = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x4C5261))
    /// The keycap glyph while transcribing: dimmer than `ai`, still at least 3:1 on the key face.
    static let keyGlyphBusy = Color(nsColor: dynamic(light: 0x6B7A96, dark: 0x8A93A5))

    /// Window and step titles: 15 pt semibold.
    static let title = Font.system(size: 15, weight: .semibold)

    /// The user's words are writing, not interface — set in New York.
    static let transcript = Font.system(size: 14, design: .serif)
    /// Extra space between transcript lines, so each line is 1.3 × the 14 pt size.
    static let transcriptLineSpacing: CGFloat = {
        let size: CGFloat = 14
        let system = NSFont.systemFont(ofSize: size)
        let serif = system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        return max(0, size * 1.3 - NSLayoutManager().defaultLineHeight(for: serif))
    }()

    static func keycapGlyph(size: CGFloat) -> Font {
        .system(size: size * 0.5, weight: .medium, design: .rounded)
    }

    static let panelRadius: CGFloat = 10

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}
