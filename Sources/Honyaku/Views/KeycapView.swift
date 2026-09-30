import SwiftUI

/// The Control key, drawn as a physical keycap — Honyaku's one signature element.
/// Idle: indigo glyph. Recording: pressed in, tinted live, with the input level rising inside the face.
/// Busy: dimmed glyph (the surrounding text says "Transcribing…"). Error: orange edge.
/// The glyph keeps at least 3:1 against the face in every state.
struct KeycapView: View {
    enum KeyState: Equatable { case idle, recording, busy, error }

    var state: KeyState
    var level: Double = 0
    var size: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pressed: Bool { state == .recording }
    private var radius: CGFloat { size * 0.22 }
    private var lip: CGFloat { pressed ? 1 : max(2, size * 0.07) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.keyLip)
                .frame(width: size, height: size)

            face
                .frame(width: size, height: size - lip)
                .offset(y: pressed ? lip : 0)
        }
        .frame(width: size, height: size + (pressed ? lip : 0), alignment: .top)
        .animation(reduceMotion ? nil : .spring(duration: 0.12), value: pressed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(pressed ? Theme.live : Theme.keyFace)
            if pressed {
                // Level fill rises from the bottom of the face as the user speaks; darker, not lighter,
                // so the white glyph keeps its contrast over it
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(height: (size - lip) * min(1, max(0, level)))
                    .animation(reduceMotion ? nil : .linear(duration: 0.08), value: level)
            }
            Text("⌃")
                .font(Theme.keycapGlyph(size: size))
                .foregroundStyle(glyphColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: size * 0.03)
            if size >= 48 {
                // A Mac's Control key carries its name; big enough to read, it makes the glyph unmistakable
                Text("control")
                    .font(.system(size: size * 0.14, weight: .medium, design: .rounded))
                    .foregroundStyle(glyphColor.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, size * 0.12)
                    .padding(.bottom, size * 0.1)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(edgeColor, lineWidth: state == .error ? 1.5 : 0.75))
    }

    private var glyphColor: Color {
        switch state {
        case .recording: return .white
        case .busy: return Theme.keyGlyphBusy
        case .idle, .error: return Theme.ai
        }
    }

    private var edgeColor: Color {
        switch state {
        case .error: return .orange
        case .recording: return Theme.live
        default: return Theme.keyEdge
        }
    }

    private var accessibilityText: String {
        switch state {
        case .idle: return "Control key, ready"
        case .recording: return "Control key held, recording"
        case .busy: return "Transcribing"
        case .error: return "Control key, error"
        }
    }
}

extension KeycapView.KeyState {
    init(_ status: AppStatus) {
        switch status {
        case .idle: self = .idle
        case .recording: self = .recording
        case .transcribing, .processing: self = .busy
        case .error: self = .error
        }
    }
}
