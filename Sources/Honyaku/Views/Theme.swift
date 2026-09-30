import AppKit
import SwiftUI

/// Honyaku's design tokens. Everything not named here uses the system's own colours and materials.
enum Theme {
    /// 藍 (ai), Japanese indigo — the one accent: app tint, selection, the idle keycap glyph.
    static let ai = Color(nsColor: dynamic(light: 0x2E4A7D, dark: 0x8FA8D8))
    /// Live — the keycap and level meter while recording, and nothing else.
    static let live = Color(nsColor: dynamic(light: 0xE0484F, dark: 0xFF6B6B))

    static let keyFace = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x3A3F4A))
    static let keyLip = Color(nsColor: dynamic(light: 0xC6CBD4, dark: 0x1D2028))
    static let keyEdge = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x4C5261))

    /// The user's words are writing, not interface — set in New York.
    static let transcript = Font.system(size: 14, design: .serif)
    static let transcriptLineSpacing: CGFloat = 3

    static func keycapGlyph(size: CGFloat) -> Font {
        .system(size: size * 0.5, weight: .medium, design: .rounded)
    }

    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6

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

/// Short relative times for transcript rows: "just now", "2m ago", "3h ago", "yesterday", "Sep 28".
enum TimeAgo {
    static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(max(1, Int((seconds / 60).rounded())))m ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h ago" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }
}
